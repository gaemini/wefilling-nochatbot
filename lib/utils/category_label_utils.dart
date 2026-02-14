import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

/// 카테고리 키/레거시 값을 사용자에게 보여줄 라벨로 변환합니다.
///
/// - 최신 데이터: `study|meal|cafe|drink|culture|other|etc|hobby|food` 같은 키가 들어올 수 있음
/// - 레거시 데이터: `스터디|식사|카페|술|문화|기타` 같은 한글 값이 들어올 수 있음
///
/// UI 표시 목적이며, DB 저장/필터링용 값은 변경하지 않습니다.
String localizedCategoryLabel(BuildContext context, String rawCategory) {
  final l10n = AppLocalizations.of(context)!;
  final raw = rawCategory.trim();
  final key = raw.toLowerCase();

  // (A) 키 기반 (영문)
  switch (key) {
    case 'study':
      return l10n.study;
    case 'meal':
    case 'food':
      return l10n.meal;
    case 'cafe':
    case 'hobby': // 일부 구버전/추천장소 키에서 cafe를 hobby로 사용
      return l10n.cafe;
    case 'drink':
      return l10n.drink;
    case 'culture':
      return l10n.culture;
    case 'etc':
    case 'other':
      return l10n.other;
  }

  // (B) 레거시 한글 값
  switch (raw) {
    case '스터디':
      return l10n.study;
    case '식사':
    case '밥':
      return l10n.meal;
    case '카페':
      return l10n.cafe;
    case '술':
      return l10n.drink;
    case '문화':
      return l10n.culture;
    case '기타':
      return l10n.other;
  }

  return rawCategory;
}

