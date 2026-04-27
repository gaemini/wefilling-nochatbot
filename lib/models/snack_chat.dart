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
  final int retentionHours;
  final bool isFavorited;
  final Map<String, bool> favoriteBy;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  final DateTime updatedAt;
  final String sourceType;
  final String sourcePostId;
  final String sourceCollectionPath;

  const SnackChat({
    required this.id,
    required this.title,
    required this.creatorId,
    required this.participantIds,
    required this.visibleToCategoryIds,
    required this.createdAt,
    required this.expiresAt,
    required this.retentionHours,
    required this.isFavorited,
    this.favoriteBy = const <String, bool>{},
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageSenderId,
    required this.unreadCount,
    required this.updatedAt,
    this.sourceType = '',
    this.sourcePostId = '',
    this.sourceCollectionPath = '',
  });

  int get participantCount => participantIds.length;

  bool isExpired([DateTime? now]) {
    final base = now ?? DateTime.now();
    return activityExpiresAt.isBefore(base);
  }

  DateTime get activityExpiresAt =>
      lastMessageTime.add(Duration(hours: retentionHours));

  bool get isSharingOrigin => sourceType == 'sharing';

  bool isFavoritedBy(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return favoriteBy[userId] == true;
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
      participantIds: (data['participantIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      visibleToCategoryIds: (data['visibleToCategoryIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      createdAt: parseDate(data['createdAt'], DateTime.now()),
      expiresAt: parseDate(
          data['expiresAt'], DateTime.now().add(const Duration(days: 1))),
      retentionHours:
          (data['retentionHours'] is int) ? data['retentionHours'] as int : 24,
      isFavorited: data['isFavorited'] == true,
      favoriteBy: (data['favoriteBy'] as Map?)?.map(
            (key, value) => MapEntry(key.toString(), value == true),
          ) ??
          const <String, bool>{},
      lastMessage: (data['lastMessage'] ?? '').toString(),
      lastMessageTime: parseDate(data['lastMessageTime'], DateTime.now()),
      lastMessageSenderId: (data['lastMessageSenderId'] ?? '').toString(),
      unreadCount: Map<String, int>.from(data['unreadCount'] ?? const {}),
      updatedAt: parseDate(data['updatedAt'], DateTime.now()),
      sourceType: (data['sourceType'] ?? '').toString(),
      sourcePostId: (data['sourcePostId'] ?? '').toString(),
      sourceCollectionPath: (data['sourceCollectionPath'] ?? '').toString(),
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
      'retentionHours': retentionHours,
      'isFavorited': isFavorited,
      'favoriteBy': favoriteBy,
      'lastMessage': lastMessage,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'lastMessageSenderId': lastMessageSenderId,
      'unreadCount': unreadCount,
      'updatedAt': Timestamp.fromDate(updatedAt),
      'sourceType': sourceType,
      'sourcePostId': sourcePostId,
      'sourceCollectionPath': sourceCollectionPath,
    };
  }

  SnackChat copyWith({
    String? title,
    bool? isFavorited,
    Map<String, bool>? favoriteBy,
    String? lastMessage,
    DateTime? lastMessageTime,
    String? lastMessageSenderId,
    Map<String, int>? unreadCount,
    DateTime? updatedAt,
    int? retentionHours,
  }) {
    return SnackChat(
      id: id,
      title: title ?? this.title,
      creatorId: creatorId,
      participantIds: participantIds,
      visibleToCategoryIds: visibleToCategoryIds,
      createdAt: createdAt,
      expiresAt: expiresAt,
      retentionHours: retentionHours ?? this.retentionHours,
      isFavorited: isFavorited ?? this.isFavorited,
      favoriteBy: favoriteBy ?? this.favoriteBy,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
      sourceType: sourceType,
      sourcePostId: sourcePostId,
      sourceCollectionPath: sourceCollectionPath,
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
