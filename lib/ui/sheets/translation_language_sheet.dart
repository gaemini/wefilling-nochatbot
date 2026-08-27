import 'package:flutter/material.dart';

import '../../services/content_translation_service.dart';

Future<String?> showTranslationLanguageSheet(BuildContext context) async {
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) => TranslationLanguageSheet(
      selectedCode: selected,
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
  });

  final String selectedCode;
  final Future<void> Function(String code) onSelected;

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
            const Align(
              alignment: Alignment.center,
              child: SizedBox(
                width: 40,
                child: Divider(
                  height: 4,
                  thickness: 4,
                  color: Color(0xFFD1D5DB),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
              child: Text(
                isKo ? '번역해서 볼 언어' : 'Language to translate into',
                key: const ValueKey('translation_language_sheet_title'),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F8FE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 18,
                          color: Color(0xFF2F9BE8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isKo
                              ? '원문의 언어가 아니라, 포스트와 댓글을 번역해서 보고 싶은 언어를 선택해 주세요.'
                              : 'Choose the language you want posts and comments translated into, not the language of the original text.',
                          key: const ValueKey(
                            'translation_language_sheet_guidance',
                          ),
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: ['NotoSansKR'],
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            height: 1.4,
                            color: Color(0xFF36566F),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: ContentTranslationService.supportedLanguages.entries
                    .map(
                      (entry) => ListTile(
                        key: ValueKey<String>(
                          'translation_language_${entry.key}',
                        ),
                        dense: true,
                        title: Text(
                          entry.value,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: ['NotoSansKR'],
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        trailing: _savingCode == entry.key
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Color(0xFF2F9BE8),
                                ),
                              )
                            : entry.key == widget.selectedCode
                                ? const Icon(
                                    Icons.check_rounded,
                                    color: Color(0xFF2F9BE8),
                                  )
                                : null,
                        onTap: _savingCode == null
                            ? () => _select(entry.key)
                            : null,
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
