import 'package:cloud_firestore/cloud_firestore.dart';

class SnackChatMessage {
  final String id;
  final String senderId;
  final String? senderName;
  final String text;
  final String? imageUrl;
  final DateTime createdAt;
  final List<String> readBy;

  const SnackChatMessage({
    required this.id,
    required this.senderId,
    this.senderName,
    required this.text,
    this.imageUrl,
    required this.createdAt,
    required this.readBy,
  });

  factory SnackChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};
    final created = data['createdAt'];
    final rawSenderName = data['senderName'];
    return SnackChatMessage(
      id: doc.id,
      senderId: (data['senderId'] ?? '').toString(),
      senderName: rawSenderName is String && rawSenderName.trim().isNotEmpty
          ? rawSenderName.trim()
          : null,
      text: (data['text'] ?? '').toString(),
      imageUrl: (data['imageUrl'] as String?)?.trim().isEmpty == true
          ? null
          : data['imageUrl'] as String?,
      createdAt: created is Timestamp ? created.toDate() : DateTime.now(),
      readBy: (data['readBy'] as List?)?.map((e) => e.toString()).toList() ??
          const <String>[],
    );
  }
}
