// lib/ui/motion/motion_strings.dart
// 모션 2부에서 새로 생긴 짧은 문구(한국어·영어·중국어).

import 'package:flutter/widgets.dart';

import '../../l10n/ui_locale.dart';

class MotionStrings {
  MotionStrings._();

  static String _pick(
    BuildContext context, {
    required String ko,
    required String en,
    required String zh,
  }) {
    if (isChineseUi(context)) return zh;
    return Localizations.localeOf(context).languageCode == 'ko' ? ko : en;
  }

  static String saved(BuildContext context) =>
      _pick(context, ko: '저장했어요', en: 'Saved', zh: '已收藏');

  static String undo(BuildContext context) =>
      _pick(context, ko: '되돌리기', en: 'Undo', zh: '撤销');

  static String saveFailed(BuildContext context) => _pick(
        context,
        ko: '저장하지 못했어요',
        en: "Couldn't save",
        zh: '收藏失败',
      );

  static String copied(BuildContext context) =>
      _pick(context, ko: '복사됨', en: 'Copied', zh: '已复制');

  static String slowConnection(BuildContext context) => _pick(
        context,
        ko: '연결이 느려요 · 계속 불러오는 중',
        en: 'Slow connection · Still loading',
        zh: '网络较慢 · 仍在加载',
      );

  static String newPosts(BuildContext context, int count) => _pick(
        context,
        ko: '새 포스트 $count',
        en: '$count new ${count == 1 ? 'post' : 'posts'}',
        zh: '新动态 $count',
      );

  static String loadMoreFailed(BuildContext context) => _pick(
        context,
        ko: '더 불러오지 못했어요',
        en: "Couldn't load more",
        zh: '加载失败',
      );

  static String retry(BuildContext context) =>
      _pick(context, ko: '다시 시도', en: 'Retry', zh: '重试');
}
