import 'package:flutter/widgets.dart';

/// 학기별 안내를 개인화하기 위한 사용자 유형입니다.
///
/// 언어/국적과는 별개의 명시적 값이며, 기존 사용자는 null을 유지하다가
/// To-do 첫 진입 시 직접 선택합니다.
enum StudentType {
  exchange('exchange'),
  korean('korean');

  const StudentType(this.value);

  final String value;

  static StudentType? tryParse(Object? raw) {
    final value = raw?.toString().trim().toLowerCase();
    for (final type in StudentType.values) {
      if (type.value == value) return type;
    }
    return null;
  }

  String title(BuildContext context) {
    final koreanUi = Localizations.localeOf(context).languageCode == 'ko';
    return switch (this) {
      StudentType.exchange => koreanUi ? '교환학생' : 'Exchange student',
      StudentType.korean => koreanUi ? '한국인 학생' : 'Korean student',
    };
  }

  String description(BuildContext context) {
    final koreanUi = Localizations.localeOf(context).languageCode == 'ko';
    return switch (this) {
      StudentType.exchange => koreanUi
          ? '한국 생활, 학교 행사와 교류 활동을 중심으로 안내해요.'
          : 'Get guidance for campus life, local events, and cultural exchange.',
      StudentType.korean => koreanUi
          ? '학사 일정, 교내 활동과 교환학생 교류 기회를 중심으로 안내해요.'
          : 'Get guidance for academics, campus activities, and exchange events.',
    };
  }
}
