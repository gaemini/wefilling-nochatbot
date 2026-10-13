// lib/l10n/profile_share_strings.dart
// 프로필 공유 시트 문구(ko / en / zh).

import 'package:flutter/widgets.dart';

class ProfileShareStrings {
  const ProfileShareStrings._(this._code);
  final String _code;

  static ProfileShareStrings of(BuildContext context) =>
      ProfileShareStrings._(Localizations.localeOf(context).languageCode);

  String _t(String zh, String ko, String en) =>
      _code == 'zh' ? zh : (_code == 'ko' ? ko : en);

  String get title => _t('分享我的主页', '내 프로필 공유', 'Share my profile');
  String get qrCaption =>
      _t('扫描二维码查看主页', 'QR을 스캔하면 프로필을 볼 수 있어요', 'Scan to view my profile');
  String get copy => _t('复制链接', '링크 복사', 'Copy link');
  String get share => _t('分享', '공유', 'Share');
  String get copied => _t('链接已复制', '링크를 복사했어요', 'Link copied');
  String shareText(String name, String link) => _t(
        '来 Wefilling 看看$name的主页\n$link',
        'Wefilling에서 $name님의 프로필을 확인해 보세요\n$link',
        'See $name\'s profile on Wefilling\n$link',
      );
}
