/// 채팅형 화면(스낵챗, 포스트 대화)이 함께 쓰는 날짜 라벨.

/// 날짜 구분선의 전체 날짜. ko/en/zh 외 언어는 yyyy.MM.dd.
String formatChatCalendarDate(DateTime date, {required String languageCode}) {
  final local = date.toLocal();
  if (languageCode == 'zh') {
    const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
    return '${local.year}年${local.month}月${local.day}日 ${weekdays[local.weekday - 1]}';
  }
  if (languageCode == 'ko') {
    const weekdays = <String>[
      '월요일',
      '화요일',
      '수요일',
      '목요일',
      '금요일',
      '토요일',
      '일요일',
    ];
    return '${local.year}년 ${local.month}월 ${local.day}일 '
        '${weekdays[local.weekday - 1]}';
  }

  if (languageCode == 'en') {
    const weekdays = <String>[
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = <String>[
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    return '${weekdays[local.weekday - 1]}, '
        '${months[local.month - 1]} ${local.day}, ${local.year}';
  }

  return '${local.year}.${local.month.toString().padLeft(2, '0')}.'
      '${local.day.toString().padLeft(2, '0')}';
}

/// 포스트 대화의 날짜 구분 라벨. 오늘·어제는 [today]/[yesterday] 문구를,
/// 그 밖의 날은 [formatChatCalendarDate]를 쓴다.
String chatDayLabel(
  DateTime date, {
  required String languageCode,
  required String today,
  required String yesterday,
  DateTime? now,
}) {
  final local = date.toLocal();
  final current = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final todayDate = DateTime(current.year, current.month, current.day);
  final diff = todayDate.difference(day).inDays;
  if (diff == 0) return today;
  if (diff == 1) return yesterday;
  return formatChatCalendarDate(date, languageCode: languageCode);
}

/// 같은 로컬 날짜인지.
bool isSameLocalDay(DateTime a, DateTime b) {
  final x = a.toLocal();
  final y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}
