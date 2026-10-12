// Opt-in real FlutterFire SDK test. Uses ONLY loopback emulators/demo data.
// flutter test --platform chrome --dart-define=RUN_CHAT_EMULATOR_TESTS=true \
//   test/dm_delivery_client_web_test.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;

import 'package:wefilling/models/dm_message.dart';
import 'package:wefilling/services/dm_service.dart';
import 'support/chat_test_plugins_stub.dart'
    if (dart.library.js_interop) 'support/chat_test_plugins_web.dart';

const _project = 'demo-chat-delivery';
const _documents = 'http://127.0.0.1:8787/v1/projects/$_project/'
    'databases/(default)/documents';

Map<String, dynamic> _value(Object value) {
  if (value is String) return {'stringValue': value};
  if (value is bool) return {'booleanValue': value};
  if (value is Timestamp)
    return {'timestampValue': value.toDate().toUtc().toIso8601String()};
  if (value is List) {
    return {
      'arrayValue': {'values': value.map((v) => _value(v as Object)).toList()}
    };
  }
  throw ArgumentError('Unsupported fixture value');
}

Future<void> _seed(String path, Map<String, Object> fields) async {
  // Emulator-only admin bypass is for fixtures, never for the code under test.
  final response = await http.patch(Uri.parse('$_documents/$path'),
      headers: {
        'Authorization': 'Bearer owner',
        'Content-Type': 'application/json'
      },
      body:
          jsonEncode({'fields': fields.map((k, v) => MapEntry(k, _value(v)))}));
  expect(response.statusCode, 200, reason: response.body);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'real SDK: first room, rapid sends, retry, cursor, offline and account switch',
      () async {
    registerChatTestPlugins();
    await Firebase.initializeApp(
        options: const FirebaseOptions(
      apiKey: 'demo-chat-delivery-key',
      appId: '1:123:web:chatdelivery',
      messagingSenderId: '123',
      projectId: _project,
    )).timeout(const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException(
            'Firebase Web SDK initialization (before emulator access)'));
    debugPrint('SDK initialized; connecting to loopback emulators');
    final auth = FirebaseAuth.instance;
    final db = FirebaseFirestore.instance;
    await auth.useAuthEmulator('127.0.0.1', 9099);
    db.settings = const Settings(persistenceEnabled: false);
    db.useFirestoreEmulator('127.0.0.1', 8788); // local fault-injection proxy
    expect(
        (await http.post(Uri.parse('http://127.0.0.1:8789/online'))).statusCode,
        200);
    Hive.init('chat-client-test');
    final run = DateTime.now().microsecondsSinceEpoch;
    const password = 'Emulator-only-password';
    final bobEmail = 'bob-$run@test.invalid';
    final bob = (await auth.createUserWithEmailAndPassword(
            email: bobEmail, password: password))
        .user!
        .uid;
    final alice = (await auth.createUserWithEmailAndPassword(
            email: 'alice-$run@test.invalid', password: password))
        .user!
        .uid;
    for (final uid in [alice, bob]) {
      await _seed('users/$uid',
          {'nickname': 'TestUser', 'registrationStatus': 'complete'});
    }
    final service = DMService();
    debugPrint('Fixture accounts ready; testing first-room creation');
    final room = service.generateConversationId(bob);
    final rooms = await Future.wait(List.generate(
        4,
        (_) => service.getOrCreateConversation(bob,
            requestedConversationId: room)));
    expect(rooms, everyElement(room));
    debugPrint('First room ready; testing ordered delivery and idempotency');
    final ref = db.collection('conversations').doc(room);
    DMMessage packet(String id, {String text = '안녕 你好 hello'}) => DMMessage(
        id: id,
        senderId: alice,
        text: text,
        isRead: false,
        createdAt: DateTime.now().add(const Duration(days: 1)),
        deliveryState: DMDeliveryState.sending);
    final received = Completer<void>();
    Object? streamError;
    final subscription =
        service.watchRecentMessagesAndCache(room).listen((messages) {
      if (messages.length >= 8 && !received.isCompleted) received.complete();
    }, onError: (Object error) {
      streamError = error;
    });
    addTearDown(subscription.cancel);
    final packets = List.generate(8, (i) => packet('rapid-$i'));
    expect(await Future.wait(packets.map((m) => service.sendMessage(room, m))),
        everyElement(DMDeliveryState.sent));
    await received.future.timeout(const Duration(seconds: 10));
    expect(streamError, isNull);
    var saved = await ref.collection('messages').orderBy('createdAt').get();
    expect(saved.docs.map((d) => d.id), packets.map((m) => m.id));
    expect(
        (saved.docs.first.get('createdAt') as Timestamp)
            .toDate()
            .isBefore(packets.first.createdAt),
        isTrue,
        reason: 'Server, not device clock');
    final firstData = saved.docs.first.data();
    await _seed('conversations/$room/messages/rapid-0', {
      'senderId': alice,
      'text': firstData['text'] as String,
      'isRead': true,
      'createdAt': firstData['createdAt'] as Timestamp,
    });
    expect(
        await service.sendMessage(
            room, packet('rapid-0', text: 'must not overwrite')),
        DMDeliveryState.sent);
    expect(
        (await ref.collection('messages').doc('rapid-0').get()).get('isRead'),
        isTrue);
    expect((await ref.get()).get('lastMessageId'), 'rapid-7');
    expect((await ref.collection('messages').get()).size, 8);

    // Equal server timestamps, including the old millisecond-only cache cursor.
    final pagesRoom = '${room}__pages';
    await _seed('conversations/$pagesRoom', {
      'participants': [alice, bob]
    });
    // The pinned Web adapter encodes Timestamp cursors as JS Date (milliseconds).
    // Native nanosecond ordering is covered by the model + backend tests; keep
    // this cross-SDK fixture millisecond-aligned rather than changing app queries.
    final stamp = Timestamp(1700000000, 123000000);
    for (var i = 0; i < 7; i++) {
      await _seed('conversations/$pagesRoom/messages/page-$i', {
        'senderId': alice,
        'text': 'page-$i',
        'isRead': false,
        'createdAt': stamp,
      });
    }
    final first = await service.getMessages(pagesRoom, limit: 3).first;
    final cursor = first.last;
    final older = await service.fetchOlderMessages(pagesRoom,
        before: DateTime.fromMillisecondsSinceEpoch(
            cursor.createdAt.millisecondsSinceEpoch - 1),
        beforeId: cursor.id); // intentionally no exact timestamp: legacy cache
    expect({...first.map((m) => m.id), ...older.map((m) => m.id)}.length, 7);
    expect(older.length, 4);

    // Drop real SDK transport, including transaction RPCs. Web disableNetwork()
    // alone only pauses streams and does not reliably cut transaction requests.
    expect(
        (await http.post(Uri.parse('http://127.0.0.1:8789/offline')))
            .statusCode,
        200);
    debugPrint('Testing offline outcome and reconnect');
    final offline = packet('offline-same-id');
    try {
      expect(
          await service
              .sendMessage(room, offline)
              .timeout(const Duration(seconds: 40)),
          DMDeliveryState.uncertain);
    } finally {
      await http.post(Uri.parse('http://127.0.0.1:8789/online'));
    }
    expect(await service.sendMessage(room, offline), DMDeliveryState.sent);
    expect(await service.sendMessage(room, offline), DMDeliveryState.sent);
    saved = await ref.collection('messages').get();
    expect(saved.docs.where((d) => d.id == offline.id).length, 1);
    await subscription.cancel();
    await http.post(Uri.parse('http://127.0.0.1:8789/offline'));
    final oldAccountSend =
        service.sendMessage(room, packet('inflight-old-account'));
    try {
      await auth.signInWithEmailAndPassword(
          email: bobEmail, password: password);
    } finally {
      await http.post(Uri.parse('http://127.0.0.1:8789/online'));
    }
    expect(await oldAccountSend, isNot(DMDeliveryState.sent));
    expect(
        (await ref.collection('messages').doc('inflight-old-account').get())
            .exists,
        isFalse);
    expect(await service.sendMessage(room, packet('wrong-account')),
        DMDeliveryState.failed);
    expect((await ref.collection('messages').doc('wrong-account').get()).exists,
        isFalse);
    await auth.signOut();
    await Hive.close();
  },
      skip: !kIsWeb || !const bool.fromEnvironment('RUN_CHAT_EMULATOR_TESTS'),
      timeout: const Timeout(Duration(minutes: 3)));
}
