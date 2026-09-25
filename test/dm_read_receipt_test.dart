import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/dm_message.dart';

DMMessage message(String id, {Timestamp? committed, bool read = false,
    DMDeliveryState state = DMDeliveryState.sent}) => DMMessage(
  id: id, senderId: 'alice', text: id,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1),
  // The old misleading field deliberately disagrees with server commit time.
  serverCreatedAt: Timestamp(1, 0), receiptCreatedAt: committed,
  isRead: read, deliveryState: state,
);

void main() {
  test('room watermark renders receipts outside the recent 40 without worker', () {
    final loaded = List.generate(90,
        (i) => message('$i', committed: Timestamp(100, i * 1000)));
    final boundary = Timestamp(100, 80000);
    expect(loaded.where((m) => m.isReadThrough(boundary)).length, 81);
    expect(loaded.first.isRead, isFalse); // display does not persist receipts
    expect(loaded.last.isReadThrough(boundary), isFalse);
  });

  test('exact timestamp boundary, equal-time peers and submillisecond successor', () {
    final boundary = Timestamp(100, 123456000);
    expect(message('equal-a', committed: boundary).isReadThrough(boundary), isTrue);
    expect(message('equal-b', committed: boundary).isReadThrough(boundary), isTrue);
    expect(message('later', committed: Timestamp(100, 123457000))
        .isReadThrough(boundary), isFalse);
  });

  test('legacy device clock, unresolved and pending timestamps are not evidence', () {
    final boundary = Timestamp(200, 0);
    expect(message('legacy').isReadThrough(boundary), isFalse);
    expect(message('pending', committed: Timestamp(100, 0),
        state: DMDeliveryState.sending).isReadThrough(boundary), isFalse);
    expect(message('legacy-receipt', read: true).isReadThrough(null), isTrue);
  });

  test('cache roundtrip retains full commit precision; legacy cache stays untrusted', () {
    final original = message('m', committed: Timestamp(100, 123456789));
    final copy = DMMessage.fromLocalMap(original.toLocalMap());
    expect(copy.receiptCreatedAt, original.receiptCreatedAt);
    final legacy = original.toLocalMap()
      ..remove('receiptSeconds')..remove('receiptNanos');
    expect(DMMessage.fromLocalMap(legacy).isReadThrough(Timestamp(999, 0)), isFalse);
  });

  test('older page or cache cannot undo true while content updates still apply', () {
    final confirmed = message('m', read: true);
    final stale = message('m').copyWith(text: 'new text');
    final merged = stale.preserveConfirmedReceipt(confirmed);
    expect(merged.isRead, isTrue);
    expect(merged.text, 'new text');
    expect(message('unrelated').preserveConfirmedReceipt(null).isRead, isFalse);
  });

  test('stale legacy packet cannot discard an already verified server timestamp', () {
    final at = Timestamp(100, 123456000);
    final merged = message('m').preserveConfirmedReceipt(message('m', committed: at));
    expect(merged.isReadThrough(at), isTrue);
    expect(merged.isRead, isFalse);
  });
}
