import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
// Use the Firebase plugins' public platform test seams, with no network I/O.
// ignore: depend_on_referenced_packages
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/models/content_translation.dart';
import 'package:wefilling/services/content_translation_service.dart';

class _SignedOutAuth extends FirebaseAuthPlatform {
  @override
  FirebaseAuthPlatform delegateFor({required FirebaseApp app}) => this;

  @override
  FirebaseAuthPlatform setInitialValues({currentUser, String? languageCode}) =>
      this;

  @override
  UserPlatform? get currentUser => null;

  @override
  Stream<UserPlatform?> authStateChanges() => const Stream.empty();
}

const _completed = ContentTranslationResult(
  status: 'completed',
  sourceHash: 'source',
  sourceLanguage: 'ko',
  targetLanguage: 'en',
  translatedFields: {'content': 'I like music'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ContentTranslationService service;
  late Directory cacheDirectory;

  setUpAll(() async {
    setupFirebaseCoreMocks();
    FirebaseAuthPlatform.instance = _SignedOutAuth();
    SharedPreferences.setMockInitialValues({});
    await Firebase.initializeApp();
    cacheDirectory =
        await Directory.systemTemp.createTemp('translation-tests-');
    Hive.init(cacheDirectory.path);
    await Hive.openBox<dynamic>('content_translations_v1');
    service = ContentTranslationService.instance;
  });

  tearDownAll(() async {
    await Hive.close();
    await cacheDirectory.delete(recursive: true);
  });

  test('five completed scope items commit immediately and notify once',
      () async {
    const scope = 'post:coalesced';
    final tokens = List.generate(5, (_) => Object());
    var notifications = 0;
    void listener() => notifications++;
    service.addListener(listener);
    try {
      for (final token in tokens) {
        service.resolveScopeTranslation(scope, token, _completed);
      }
      expect(service.canToggleScope(scope), isTrue);
      expect(notifications, 0);
      await Future<void>.value();
      expect(notifications, 1);
      for (final token in tokens) {
        service.resolveScopeTranslation(scope, token, _completed);
      }
      await Future<void>.value();
      expect(notifications, 1, reason: 'unchanged results do not wake widgets');
    } finally {
      service.removeListener(listener);
      for (final token in tokens) {
        service.clearScopeTranslation(scope, token, notify: false);
      }
    }
  });

  test('loading and original toggle notifications remain immediate', () {
    const scope = 'post:interactive';
    final token = Object();
    var notifications = 0;
    void listener() => notifications++;
    service.addListener(listener);
    try {
      service.beginScopeLoading(scope, token);
      expect(service.isScopeLoading(scope), isTrue);
      expect(notifications, 1);
      service.endScopeLoading(scope, token);
      expect(service.isScopeLoading(scope), isFalse);
      expect(notifications, 2);
      service.toggleScope(scope);
      expect(service.showsOriginal(scope), isTrue);
      expect(notifications, 3);
      service.toggleScope(scope);
      expect(service.showsOriginal(scope), isFalse);
    } finally {
      service.removeListener(listener);
    }
  });

  test('result revisions advance for new text but not repeated cache hits',
      () async {
    await service.setPreferredLanguage('ko');
    final fields = {'content': '음악을 좋아해요'};
    final request = ContentTranslationRequest(
      contentType: 'comment',
      contentId: 'cached-comment',
      parentId: 'post',
      sourceFields: fields,
    );
    final before = service.resultsRevision;
    final original = await service.request(request);
    expect(original?.isSameLanguage, isTrue);
    expect(service.resultsRevision, before + 1);
    expect(service.latestResultFor(request), same(original));
    expect(await service.request(request), same(original));
    expect(service.resultsRevision, before + 1);

    fields['content'] = '카페에 가요';
    expect(service.latestResultFor(request), isNull);
    final edited = await service.request(request);
    expect(edited?.isSameLanguage, isTrue);
    expect(edited?.sourceHash, isNot(original?.sourceHash));
    expect(service.resultsRevision, before + 2);
    expect(service.latestResultFor(request), same(edited));
  });

  test('queued notification cannot restore old scope after language switch',
      () async {
    await service.setPreferredLanguage('en');
    const scope = 'post:old-language';
    final before = service.languageRevision;
    service.resolveScopeTranslation(scope, Object(), _completed);
    await service.setPreferredLanguage('ro');
    await Future<void>.value();
    expect(service.languageRevision, greaterThan(before));
    expect(service.canToggleScope(scope), isFalse);
    expect(service.sourceLanguageForScope(scope), isNull);
    expect(await service.targetLanguage(), 'ro');
  });
}
