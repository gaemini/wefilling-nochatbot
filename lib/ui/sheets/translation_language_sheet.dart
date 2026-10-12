import 'package:flutter/material.dart';

import '../../services/content_translation_service.dart';
import '../../l10n/ui_locale.dart';

Future<String?> showTranslationLanguageSheet(
  BuildContext context, {
  bool forSnackChat = false,
}) async {
  final service = ContentTranslationService.instance;
  final selected = await service.targetLanguage(
    uiLanguageCode: Localizations.localeOf(context).languageCode,
  );
  if (!context.mounted) return null;

  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (sheetContext) => TranslationLanguageSheet(
      selectedCode: selected,
      forSnackChat: forSnackChat,
      onSelected: (code) async {
        await service.setPreferredLanguage(code);
        if (sheetContext.mounted) Navigator.pop(sheetContext, code);
      },
    ),
  );
}

class TranslationLanguageSheet extends StatefulWidget {
  const TranslationLanguageSheet({
    super.key,
    required this.selectedCode,
    required this.onSelected,
    this.forSnackChat = false,
  });

  final String selectedCode;
  final Future<void> Function(String code) onSelected;
  final bool forSnackChat;

  @override
  State<TranslationLanguageSheet> createState() =>
      _TranslationLanguageSheetState();
}

class _TranslationLanguageSheetState extends State<TranslationLanguageSheet> {
  String? _savingCode;

  Future<void> _select(String code) async {
    if (_savingCode != null) return;
    setState(() => _savingCode = code);
    try {
      await widget.onSelected(code);
    } finally {
      if (mounted) setState(() => _savingCode = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.78,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD6D6D6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Text(
                (isChineseUi(context)
                    ? '翻译目标语言'
                    : isKo
                        ? '번역해서 볼 언어'
                        : 'Language to translate into'),
                key: const ValueKey('translation_language_sheet_title'),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF000000),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: Text(
                widget.forSnackChat
                    ? ((isChineseUi(context)
                        ? '选择查看他人消息时使用的翻译语言。你发送的消息仍显示原文。'
                        : isKo
                            ? '상대방 메시지를 번역해서 보고 싶은 언어를 선택해 주세요. 내 메시지는 입력한 원문으로 표시됩니다.'
                            : 'Choose the language for translating messages from other people. Your messages stay in the original text.'))
                    : ((isChineseUi(context)
                        ? '选择动态和评论的翻译目标语言，而不是原文语言。'
                        : isKo
                            ? '원문의 언어가 아니라, 포스트와 댓글을 번역해서 보고 싶은 언어를 선택해 주세요.'
                            : 'Choose the language you want posts and comments translated into, not the language of the original text.')),
                key: const ValueKey('translation_language_sheet_guidance'),
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: isChineseUi(context) ? 1.4 : 18 / 13,
                  color: Color(0xFF5F5F5F),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children:
                    ContentTranslationService.supportedLanguages.entries.map(
                  (entry) {
                    final selected = entry.key == widget.selectedCode;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: ListTile(
                        key: ValueKey<String>(
                          'translation_language_${entry.key}',
                        ),
                        minTileHeight: 48,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        selected: selected,
                        selectedTileColor: const Color(0xFFF4F4F4),
                        selectedColor: const Color(0xFF000000),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        title: Text(
                          entry.value,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: ['NotoSansKR'],
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
                            color: const Color(0xFF000000),
                          ),
                        ),
                        trailing: _savingCode == entry.key
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF2C6BC0),
                                ),
                              )
                            : selected
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Color(0xFF2C6BC0),
                                  )
                                : null,
                        onTap: _savingCode == null
                            ? () => _select(entry.key)
                            : null,
                      ),
                    );
                  },
                ).toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
