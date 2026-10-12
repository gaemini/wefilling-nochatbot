import 'package:flutter/widgets.dart';

/// Chinese is a UI locale; existing Korean/English branches remain unchanged.
bool isChineseUi(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'zh';

/// Message shown when a removed user tries to open or rejoin a meetup.
/// Keep this scoped to the access guard so ordinary join failures continue
/// using their existing localized copy.
String kickedMeetupAccessMessage(BuildContext context) {
  if (isChineseUi(context)) return '抱歉，你无法参加该聚会。';
  if (Localizations.localeOf(context).languageCode == 'ko') {
    return '죄송합니다. 모임에 참여할 수 없습니다';
  }
  return "Sorry, you can't join this meetup.";
}

Locale uiLocale(String code) => code == 'zh' || code.startsWith('zh_')
    ? const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans')
    : Locale(code);

String uiFontFamily(BuildContext context, String existingFamily) =>
    isChineseUi(context) ? 'NotoSansSC' : existingFamily;

/// Preserve the original style exactly for Korean/English. Chinese glyphs need
/// enough vertical space, without reducing the original font size or weight.
TextStyle uiTextStyle(BuildContext context, TextStyle style) =>
    !isChineseUi(context)
        ? style
        : style.copyWith(
            fontFamily: 'NotoSansSC',
            height: style.height == null || style.height! < 1.3
                ? 1.3
                : style.height,
          );
