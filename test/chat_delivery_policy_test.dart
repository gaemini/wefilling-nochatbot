import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wefilling/models/dm_message.dart';
import 'package:wefilling/models/snack_chat_message.dart';
import 'package:wefilling/services/chat_outbox_store.dart';
import 'package:wefilling/utils/chat_work_queue.dart';

void main() {
  test('slow cache write is coalesced; newest wins; accounts are isolated',
      () async {
    final writer = ChatLatestWriter();
    final slow = Completer<void>();
    final writes = <String>[];
    final first = writer.schedule('alice/room', () async {
      await slow.future;
      writes.add('old');
    });
    await Future<void>.delayed(Duration.zero);
    for (var i = 0; i < 100; i++) {
      writer.schedule('alice/room', () async => writes.add('latest-$i'));
    }
    await writer.schedule('bob/room', () async => writes.add('bob'));
    expect(writes, ['bob']);
    slow.complete();
    await first;
    expect(writes, ['bob', 'old', 'latest-99']);
  });

  test('text commits stay ordered and overtake an uploading image', () async {
    final commits = ChatWorkQueue();
    final uploads = ChatWorkQueue();
    final upload = Completer<void>();
    final delivered = <String>[];
    final image = uploads.run('alice', () async {
      await upload.future;
      await commits.run('alice/room', () async => delivered.add('image'));
    });
    final texts = List.generate(
        20,
        (i) => commits.run('alice/room', () async {
              delivered.add('text-$i');
            }));
    await Future.wait(texts);
    expect(delivered, List.generate(20, (i) => 'text-$i'));
    upload.complete();
    await image;
    expect(delivered.last, 'image');
    await expectLater(
        commits.run('alice/room', () async => throw StateError('failed')),
        throwsStateError);
    await commits.run('alice/room', () async => delivered.add('after-failure'));
    expect(delivered.last, 'after-failure');
  });

  test('DM cache/outbox roundtrip preserves reply, precision, ID and status',
      () {
    final at = Timestamp(100, 123456789);
    final m = DMMessage(
        id: 'stable',
        senderId: 'alice',
        text: '한글 中文\ntext',
        createdAt: at.toDate(),
        serverCreatedAt: at,
        isRead: true,
        replyToMessageId: 'source',
        replyToText: 'reply',
        postId: 'post',
        deliveryState: DMDeliveryState.uncertain,
        localImagePath: '/private/image');
    final copy = DMMessage.fromLocalMap(m.toLocalMap());
    expect(copy.serverCreatedAt, at);
    expect(copy.replyToMessageId, 'source');
    expect(copy.replyToText, 'reply');
    expect(copy.id, 'stable');
    expect(copy.isRead, isTrue);
    expect(copy.deliveryState, DMDeliveryState.uncertain);
    expect(copy.text, '한글 中文\ntext');
    expect(copy.toFirestore().containsKey('sequence'), isFalse);
    expect(copy.toFirestore().containsKey('deliveryState'), isFalse);
    final tied = m.copyWith(id: 'z');
    expect(DMMessage.compareDescending(m, tied), greaterThan(0));
    final later = m.copyWith(serverCreatedAt: Timestamp(100, 123456790));
    expect(DMMessage.compareDescending(m, later), greaterThan(0));
  });

  test('DM file packet keeps immutable metadata and legacy preview locally',
      () {
    final message = DMMessage(
      id: 'file-message',
      senderId: 'alice',
      text: '📎 syllabus.pdf',
      type: 'file',
      fileName: 'syllabus.pdf',
      fileExtension: 'pdf',
      fileMimeType: 'application/pdf',
      fileSize: 2048,
      fileStoragePath: 'dm_files/alice/room/file-message/file.pdf',
      localFilePath: '/private/syllabus.pdf',
      replyToMessageId: 'source-message',
      replyToSenderId: 'bob',
      replyToText: 'Please review this',
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      isRead: false,
      deliveryState: DMDeliveryState.uncertain,
    );

    final firestore = message.toFirestore();
    final restored = DMMessage.fromLocalMap(message.toLocalMap());
    expect(firestore['type'], 'file');
    expect(firestore['text'], '📎 syllabus.pdf');
    expect(firestore['fileSize'], 2048);
    expect(restored.fileStoragePath, message.fileStoragePath);
    expect(restored.localFilePath, message.localFilePath);
    expect(restored.replyToMessageId, 'source-message');
    expect(restored.deliveryState, DMDeliveryState.uncertain);
  });

  test('mixed Snack sequence/legacy/outbox ordering has no cycles', () {
    final messages = List.generate(
        12,
        (i) => SnackChatMessage(
            id: '$i',
            senderId: 'alice',
            text: '$i',
            sequence: i < 6 ? i + 1 : null,
            createdAt: DateTime.fromMillisecondsSinceEpoch(10000 - i * 100),
            sendStatus:
                i >= 9 ? MessageSendStatus.sending : MessageSendStatus.sent));
    messages.sort(SnackChatMessage.compareDescending);
    for (var a = 0; a < messages.length; a++) {
      for (var b = a + 1; b < messages.length; b++) {
        expect(SnackChatMessage.compareDescending(messages[a], messages[b]),
            lessThan(0));
      }
    }
    expect(messages.take(3).every((m) => m.isPending), isTrue);
    expect(messages.skip(3).take(6).map((m) => m.sequence), [6, 5, 4, 3, 2, 1]);
  });

  test(
      'DM pending packets remain visible despite clock skew; legacy history stays ordered',
      () {
    final saved = DMMessage(
        id: 'saved',
        senderId: 'bob',
        text: 'server',
        createdAt: DateTime.fromMillisecondsSinceEpoch(5000),
        serverCreatedAt: Timestamp.fromMillisecondsSinceEpoch(5000),
        isRead: false);
    final pending = DMMessage(
        id: 'pending',
        senderId: 'alice',
        text: 'local',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
        isRead: false,
        deliveryState: DMDeliveryState.sending);
    final legacy = DMMessage(
        id: 'legacy',
        senderId: 'bob',
        text: 'old cache',
        createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
        isRead: false);
    final messages = [saved, legacy, pending]
      ..sort(DMMessage.compareDescending);
    expect(messages.map((m) => m.id), ['pending', 'saved', 'legacy']);
    expect(
        DMMessage.compareDescending(
            pending.copyWith(deliveryState: DMDeliveryState.uncertain), saved),
        lessThan(0));
  });

  test('durable outbox retry and account/room separation', () async {
    final dir = await Directory.systemTemp.createTemp('chat-outbox-test-');
    Hive.init(dir.path);
    final store = ChatOutboxStore.instance;
    final packet = {'id': 'stable', 'text': 'keep'};
    await store.put('alice', 'room', 'stable', packet);
    await store.put('alice', 'room', 'stable', packet);
    expect(await store.load('alice', 'room'), [packet]);
    expect(await store.load('bob', 'room'), isEmpty);
    expect(await store.load('alice', 'other'), isEmpty);
    await store.remove('bob', 'room', 'stable');
    expect(await store.load('alice', 'room'), [packet]);
    await store.remove('alice', 'room', 'stable');
    expect(await store.load('alice', 'room'), isEmpty);
    await Hive.close();
    await dir.delete(recursive: true);
  });
}
