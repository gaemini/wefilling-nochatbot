import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

class SnackChat {
  final String id;
  final String title;
  final String creatorId;
  final List<String> participantIds;
  final List<String> visibleToCategoryIds;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isFavorited;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  final DateTime updatedAt;

  const SnackChat({
    required this.id,
    required this.title,
    required this.creatorId,
    required this.participantIds,
    required this.visibleToCategoryIds,
    required this.createdAt,
    required this.expiresAt,
    required this.isFavorited,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageSenderId,
    required this.unreadCount,
    required this.updatedAt,
  });

  int get participantCount => participantIds.length;

  bool isExpired([DateTime? now]) {
    final base = now ?? DateTime.now();
    return expiresAt.isBefore(base);
  }

  int getMyUnreadCount(String currentUserId) {
    return unreadCount[currentUserId] ?? 0;
  }

  factory SnackChat.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? <String, dynamic>{};

    DateTime parseDate(dynamic raw, DateTime fallback) {
      if (raw is Timestamp) return raw.toDate();
      return fallback;
    }

    return SnackChat(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      creatorId: (data['creatorId'] ?? '').toString(),
      participantIds:
          (data['participantIds'] as List?)?.map((e) => e.toString()).toList() ??
              const <String>[],
      visibleToCategoryIds: (data['visibleToCategoryIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      createdAt: parseDate(data['createdAt'], DateTime.now()),
      expiresAt:
          parseDate(data['expiresAt'], DateTime.now().add(const Duration(days: 1))),
      isFavorited: data['isFavorited'] == true,
      lastMessage: (data['lastMessage'] ?? '').toString(),
      lastMessageTime: parseDate(data['lastMessageTime'], DateTime.now()),
      lastMessageSenderId: (data['lastMessageSenderId'] ?? '').toString(),
      unreadCount: Map<String, int>.from(data['unreadCount'] ?? const {}),
      updatedAt: parseDate(data['updatedAt'], DateTime.now()),
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'title': title,
      'creatorId': creatorId,
      'participantIds': participantIds,
      'visibleToCategoryIds': visibleToCategoryIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'isFavorited': isFavorited,
      'lastMessage': lastMessage,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'lastMessageSenderId': lastMessageSenderId,
      'unreadCount': unreadCount,
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  SnackChat copyWith({
    String? title,
    bool? isFavorited,
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageSenderId,
    Map<String, int>? unreadCount,
    DateTime? updatedAt,
  }) {
    return SnackChat(
      id: id,
      title: title ?? this.title,
      creatorId: creatorId,
      participantIds: participantIds,
      visibleToCategoryIds: visibleToCategoryIds,
      createdAt: createdAt,
      expiresAt: expiresAt,
      isFavorited: isFavorited ?? this.isFavorited,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  String getFormattedTime(BuildContext context) {
    final now = DateTime.now();
    final difference = now.difference(lastMessageTime);
    final locale = Localizations.localeOf(context).languageCode;

    if (difference.inDays > 7) {
      return DateFormat('yyyy.MM.dd').format(lastMessageTime);
    }
    if (difference.inDays > 0) {
      return AppLocalizations.of(context)!.daysAgo(difference.inDays);
    }
    if (difference.inHours > 0) {
      return AppLocalizations.of(context)!.hoursAgo(difference.inHours);
    }
    if (difference.inMinutes > 0) {
      return AppLocalizations.of(context)!.minutesAgo(difference.inMinutes);
    }
    return locale == 'ko' ? '방금 전' : 'Just now';
  }
}
