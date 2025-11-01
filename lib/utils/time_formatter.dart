// lib/utils/time_formatter.dart
// DM 시간 표시 유틸리티
// 로케일에 따라 시간을 다양한 형식으로 표시

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';

class TimeFormatter {
  /// 메시지 시간 표시 (상세 형식)
  /// 1분 이내: "방금"
  /// 1시간 이내: "5분 전"
  /// 24시간 이내: "3시간 전"
  /// 7일 이내: "2일 전"
  /// 그 외: "10월 15일" (한국어) / "Oct 15" (영어)
  static String formatMessageTime(BuildContext context, DateTime time) {
    final now = DateTime.now();
    final difference = now.difference(time);
    final locale = AppLocalizations.of(context)!;
    
    if (difference.inMinutes < 1) {
      return locale.justNow;
    } else if (difference.inHours < 1) {
      return locale.minutesAgo(difference.inMinutes);
    } else if (difference.inHours < 24) {
      return locale.hoursAgo(difference.inHours);
    } else if (difference.inDays == 1) {
      return locale.yesterday;
    } else if (difference.inDays < 7) {
      return locale.daysAgo(difference.inDays);
    } else {
      // 로케일에 따라 날짜 형식 변경
      final languageCode = Localizations.localeOf(context).languageCode;
      if (languageCode == 'ko') {
        return '${time.month}월 ${time.day}일';
      } else {
        return DateFormat('MMM d', 'en').format(time);
      }
    }
  }
  
  /// 대화방 목록 시간 표시 (간략 형식)
  /// 오늘: "14:30"
  /// 어제: "어제"
  /// 그 외: "10/15" (한국어) / "10/15" (영어)
  static String formatConversationTime(BuildContext context, DateTime time) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final messageDate = DateTime(time.year, time.month, time.day);
    final locale = AppLocalizations.of(context)!;
    
    if (messageDate == today) {
      return DateFormat('HH:mm').format(time);
    } else if (messageDate == today.subtract(const Duration(days: 1))) {
      return locale.yesterday;
    } else {
      final languageCode = Localizations.localeOf(context).languageCode;
      if (languageCode == 'ko') {
        return '${time.month}/${time.day}';
      } else {
        return DateFormat('M/d', 'en').format(time);
      }
    }
  }
}

