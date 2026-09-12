import 'package:flutter/widgets.dart';

/// Chinese is a UI locale; existing Korean/English branches remain unchanged.
bool isChineseUi(BuildContext context) =>
    Localizations.localeOf(context).languageCode == 'zh';

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
