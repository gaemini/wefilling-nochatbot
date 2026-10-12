import 'dart:async';
import 'dart:typed_data';

// ignore: depend_on_referenced_packages
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/models/content_translation.dart';
import 'package:wefilling/services/content_translation_service.dart';
import 'package:wefilling/utils/translation_source_hash_cache.dart';

class TranslationTestAuth extends FirebaseAuthPlatform {
  UserPlatform? user;
  final changes = StreamController<UserPlatform?>.broadcast(sync: true);
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;
  @override
  FirebaseAuthPlatform setInitialValues({currentUser, String? languageCode}) =>
      this;
  @override
  UserPlatform? get currentUser => user;
  @override
  Stream<UserPlatform?> authStateChanges() => changes.stream;
}

class _TestMultiFactor extends MultiFactorPlatform {
  _TestMultiFactor(super.auth);
}

class _TestUser extends UserPlatform {
  _TestUser(TranslationTestAuth auth, String uid)
      : super(
            auth,
            _TestMultiFactor(auth),
            PigeonUserDetails(
                userInfo: PigeonUserInfo(
                    uid: uid, isAnonymous: false, isEmailVerified: true),
                providerData: []));
}

class TranslationTestBackend extends FirebaseFunctionsPlatform {
  TranslationTestBackend() : super(null, 'us-central1');
  late FutureOr<Object?> Function(Map<String, dynamic> data) handler;
  final List<Map<String, dynamic>> calls = [];
  final Map<String, ContentTranslationRequest> sources = {};
  final TranslationSourceHashCache hashes = TranslationSourceHashCache();
  final auth = TranslationTestAuth();
  int active = 0;
  int peak = 0;

  Future<void> initialize() async {
    setupFirebaseCoreMocks();
    FirebaseAuthPlatform.instance = auth;
    FirebaseFunctionsPlatform.instance = this;
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
    // Exercise the real Hive cache using its public in-memory backend. Native
    // file I/O is unrelated to queue behavior and escapes the widget fake clock.
    await Hive.openBox<dynamic>('content_translations_v1', bytes: Uint8List(0));
    handler = completedBatch;
    await ContentTranslationService.instance.setPreferredLanguage('en');
  }

  Future<void> close() async {
    await auth.changes.close();
    await Hive.close();
  }

  Future<void> setAccount(String? uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'preferred_translation_language_code:${uid ?? 'signed_out'}', 'en');
    await prefs.setString(
        'preferred_translation_language_source:${uid ?? 'signed_out'}',
        'manual');
    auth.user = uid == null ? null : _TestUser(auth, uid);
    auth.changes.add(auth.user);
  }

  ContentTranslationRequest request(String id,
      {String type = 'post', String? parentId, Map<String, String>? fields}) {
    final request = ContentTranslationRequest(
        contentType: type,
        contentId: id,
        parentId: parentId,
        sourceFields: fields ?? {'content': '나는 음악을 좋아해요'});
    sources[request.serverId] = request;
    return request;
  }

  String idOf(Map raw) =>
      '${raw['contentType']}:${raw['parentId'] ?? ''}:${raw['contentId']}';

  Map<String, Object?> completedItem(Map raw, String target,
      {Map<String, String>? fields}) {
    final id = idOf(raw);
    final request = sources[id]!;
    return {
      'id': id,
      'status': 'completed',
      'sourceLanguage': 'ko',
      'targetLanguage': target,
      'sourceHash': hashes.hashFor(request.sourceFields),
      'translatedFields': fields ??
          request.sourceFields.map(
              (key, _) => MapEntry(key, 'Translated ${request.contentId}')),
      'modelUsed': 'gemini-3.5-flash-lite',
      'translationVersion': 7,
      'promptVersion': 7,
      'translationPolicyVersion': '2026-09-temporal-quality-v7',
      'glossaryVersion': 1,
      'qualityPolicyVersion': 2,
      'contextHash': 'test-context',
      'sourceIntent': 'statement',
      'cacheSource': 'gemini',
    };
  }

  Map<String, Object?> completedBatch(Map<String, dynamic> data) => {
        'items': (data['items'] as List)
            .cast<Map>()
            .map((raw) => completedItem(raw, data['targetLanguage'] as String))
            .toList(),
      };

  @override
  FirebaseFunctionsPlatform delegateFor(
          {FirebaseApp? app, required String region}) =>
      this;
  @override
  HttpsCallablePlatform httpsCallable(
          String? origin, String name, HttpsCallableOptions options) =>
      _TranslationTestCallable(this, origin, name, options);
}

class _TranslationTestCallable extends HttpsCallablePlatform {
  _TranslationTestCallable(
      this.backend, String? origin, String name, HttpsCallableOptions options)
      : super(backend, origin, name, options, null);
  final TranslationTestBackend backend;
  @override
  Future<dynamic> call([dynamic parameters]) async {
    final data = Map<String, dynamic>.from(parameters as Map);
    backend.calls.add(data);
    backend.active++;
    if (backend.active > backend.peak) backend.peak = backend.active;
    try {
      return await backend.handler(data);
    } finally {
      backend.active--;
    }
  }
}
