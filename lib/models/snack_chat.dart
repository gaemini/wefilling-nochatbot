import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';

List<Object?> _safeSnackChatList(Object? raw) =>
    raw is List ? List<Object?>.from(raw) : const <Object?>[];

class SnackChat {
  static final DateTime noExpirationDate = DateTime.utc(9999, 12, 31);
  static const int currentParticipantIntegrityVersion = 3;

  final String id;
  final String title;
  final String creatorId;
  final List<String> participantIds;
  final int participantIntegrityVersion;
  final List<String> visibleToCategoryIds;
  final DateTime createdAt;
  final int activeDurationHours;
  final DateTime expiresAt;
  final List<String> favoriteUserIds;
  final String lastMessage;
  final String lastMessageId;
  final DateTime lastMessageTime;
  final String lastMessageSenderId;
  final String? lastMessageType;
  final DateTime? lastMessageExpiresAt;
  final int lastMessageSequence;
  final Map<String, int> unreadCount;
  final DateTime updatedAt;
  final String? meetupId;
  final bool allowMeetupJoin;

  const SnackChat({
    required this.id,
    required this.title,
    required this.creatorId,
    required this.participantIds,
    this.participantIntegrityVersion = 0,
    required this.visibleToCategoryIds,
    required this.createdAt,
    required this.activeDurationHours,
    required this.expiresAt,
    required this.favoriteUserIds,
    required this.lastMessage,
    this.lastMessageId = '',
    required this.lastMessageTime,
    required this.lastMessageSenderId,
    this.lastMessageType,
    this.lastMessageExpiresAt,
    this.lastMessageSequence = 0,
    required this.unreadCount,
    required this.updatedAt,
    this.meetupId,
    this.allowMeetupJoin = false,
  }) : assert(
          activeDurationHours == 0 || activeDurationHours == 24,
          'Snack Chat duration must be 0 or 24 hours.',
        );

  int get participantCount => participantIds.length;
  bool get hasVerifiedParticipantIntegrity =>
      participantIntegrityVersion >= currentParticipantIntegrityVersion;
  bool get hasNoExpiration => activeDurationHours == 0;

  bool isExpired([DateTime? now]) {
    if (hasNoExpiration) return false;
    final base = now ?? DateTime.now();
    return !base.isBefore(expiresAt);
  }

  bool isHardExpired([DateTime? now]) {
    return false;
  }

  bool isFavoritedBy(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return favoriteUserIds.contains(userId);
  }

  /// 일반 Snack Chat은 방장 여부와 관계없이 현재 참여자 누구나 자신의
  /// 친구를 초대할 수 있다. Meetup 연결 방은 Meetup 참여 흐름만 사용한다.
  bool canInviteMembers(String? userId) {
    if (userId == null || userId.isEmpty) return false;
    return participantIds.contains(userId) &&
        !allowMeetupJoin &&
        !(meetupId?.isNotEmpty ?? false);
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

    Map<String, int> parseUnreadCount(Object? raw) {
      if (raw is! Map) return const <String, int>{};
      final result = <String, int>{};
      for (final entry in raw.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value;
        if (key.isEmpty || value is! num || !value.isFinite) continue;
        result[key] = value.toInt().clamp(0, 1 << 30).toInt();
      }
      return result;
    }

    return SnackChat(
      id: doc.id,
      title: (data['title'] ?? '').toString(),
      creatorId: (data['creatorId'] ?? '').toString(),
      participantIds: _safeSnackChatList(data['participantIds'])
          .map((e) => e.toString())
          .toList(),
      participantIntegrityVersion: data['participantIntegrityVersion'] is num
          ? (data['participantIntegrityVersion'] as num)
              .toInt()
              .clamp(0, 100)
              .toInt()
          : 0,
      visibleToCategoryIds: _safeSnackChatList(data['visibleToCategoryIds'])
          .map((e) => e.toString())
          .toList(),
      createdAt: parseDate(data['createdAt'], DateTime.now()),
      activeDurationHours: (() {
        final raw = data['activeDurationHours'];
        return raw == 0 ? 0 : 24;
      })(),
      expiresAt: parseDate(
        data['expiresAt'],
        data['activeDurationHours'] == 0
            ? noExpirationDate
            : DateTime.now().add(const Duration(days: 1)),
      ),
      favoriteUserIds: data['favoriteUserIds'] is List
          ? _safeSnackChatList(data['favoriteUserIds'])
              .map((e) => e.toString())
              .toList()
          : ((data['isFavorited'] == true &&
                  (data['creatorId'] ?? '').toString().isNotEmpty)
              ? <String>[(data['creatorId'] ?? '').toString()]
              : const <String>[]),
      lastMessage: (data['lastMessage'] ?? '').toString(),
      lastMessageId: (data['lastMessageId'] ?? '').toString().trim(),
      lastMessageTime: parseDate(data['lastMessageTime'], DateTime.now()),
      lastMessageSenderId: (data['lastMessageSenderId'] ?? '').toString(),
      lastMessageType: (data['lastMessageType'] ?? '').toString().trim().isEmpty
          ? null
          : data['lastMessageType'].toString().trim(),
      lastMessageExpiresAt: data['lastMessageExpiresAt'] is Timestamp
          ? (data['lastMessageExpiresAt'] as Timestamp).toDate()
          : null,
      lastMessageSequence: data['lastMessageSequence'] is num
          ? (data['lastMessageSequence'] as num)
              .toInt()
              .clamp(0, 1 << 30)
              .toInt()
          : 0,
      // One malformed legacy counter must not make the entire room disappear.
      unreadCount: parseUnreadCount(data['unreadCount']),
      updatedAt: parseDate(data['updatedAt'], DateTime.now()),
      meetupId: (data['meetupId'] ?? '').toString().trim().isEmpty
          ? null
          : data['meetupId'].toString().trim(),
      allowMeetupJoin: data['allowMeetupJoin'] == true,
    );
  }

  Map<String, dynamic> toFirestore() {
    return <String, dynamic>{
      'title': title,
      'creatorId': creatorId,
      'participantIds': participantIds,
      'participantIntegrityVersion': participantIntegrityVersion,
      'visibleToCategoryIds': visibleToCategoryIds,
      'createdAt': Timestamp.fromDate(createdAt),
      'activeDurationHours': activeDurationHours,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'favoriteUserIds': favoriteUserIds,
      'lastMessage': lastMessage,
      'lastMessageId': lastMessageId,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'lastMessageSenderId': lastMessageSenderId,
      if (lastMessageType != null) 'lastMessageType': lastMessageType,
      if (lastMessageExpiresAt != null)
        'lastMessageExpiresAt': Timestamp.fromDate(lastMessageExpiresAt!),
      'lastMessageSequence': lastMessageSequence,
      'unreadCount': unreadCount,
      'updatedAt': Timestamp.fromDate(updatedAt),
      if (meetupId != null && meetupId!.isNotEmpty) 'meetupId': meetupId,
      'allowMeetupJoin': allowMeetupJoin,
    };
  }

  SnackChat copyWith({
    String? title,
    List<String>? favoriteUserIds,
    String? lastMessage,
    String? lastMessageId,
    DateTime? lastMessageTime,
    String? lastMessageSenderId,
    String? lastMessageType,
    DateTime? lastMessageExpiresAt,
    int? lastMessageSequence,
    Map<String, int>? unreadCount,
    DateTime? updatedAt,
    String? meetupId,
    bool? allowMeetupJoin,
  }) {
    return SnackChat(
      id: id,
      title: title ?? this.title,
      creatorId: creatorId,
      participantIds: participantIds,
      participantIntegrityVersion: participantIntegrityVersion,
      visibleToCategoryIds: visibleToCategoryIds,
      createdAt: createdAt,
      activeDurationHours: activeDurationHours,
      expiresAt: expiresAt,
      favoriteUserIds: favoriteUserIds ?? this.favoriteUserIds,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageId: lastMessageId ?? this.lastMessageId,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageExpiresAt: lastMessageExpiresAt ?? this.lastMessageExpiresAt,
      lastMessageSequence: lastMessageSequence ?? this.lastMessageSequence,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
      meetupId: meetupId ?? this.meetupId,
      allowMeetupJoin: allowMeetupJoin ?? this.allowMeetupJoin,
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
