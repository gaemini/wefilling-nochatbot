// lib/ui/widgets/snack_chat_translation_split_button.dart
// 스낵챗 상단 바의 [文A | 언어 ⌄] 번역 분할 버튼.
// 왼쪽은 방 번역 켜기/끄기, 오른쪽은 번역 언어 시트를 연다.

import 'package:flutter/material.dart';

import '../../l10n/ui_locale.dart';
import 'snack_chat_chrome.dart';

class SnackChatTranslationSplitButton extends StatelessWidget {
  const SnackChatTranslationSplitButton({
    super.key,
    required this.translationOn,
    required this.enabled,
    required this.languageLabel,
    required this.toggleSemanticLabel,
    required this.languageSemanticLabel,
    required this.onToggle,
    required this.onOpenLanguage,
    this.toggleKey = const ValueKey('snack_translation_toggle'),
    this.languageKey = const ValueKey('snack_translation_language_settings'),
    this.languageMaxWidth = 132,
  });

  /// 테스트·화면별 키(DM은 dm_translation_toggle 등).
  final Key toggleKey;
  final Key languageKey;

  /// 언어 부분 최대 폭(넘치면 언어 이름이 말줄임).
  final double languageMaxWidth;

  /// 방 번역이 켜져 있는지(!showsOriginal).
  final bool translationOn;

  /// 방 모드 로딩이 끝났는지. false면 토글이 반투명·비활성이다.
  final bool enabled;

  /// 현재 번역 언어의 고유 이름(한국어, English, 日本語 …). 비면 아이콘만.
  final String languageLabel;

  /// 토글을 눌렀을 때 일어날 일(번역 보기 / 원문 보기).
  final String toggleSemanticLabel;
  final String languageSemanticLabel;
  final VoidCallback onToggle;
  final VoidCallback onOpenLanguage;

  static const double height = 36;
  static const double toggleWidth = 40;
  static const double minTouch = 44;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    final toggleFill =
        translationOn ? SnackChatPalette.pointStrong : Colors.transparent;
    final toggleIcon = translationOn ? Colors.white : SnackChatPalette.ink;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      // 보이는 알약은 36, 터치 줄은 44. 알약을 뒤에 깔고 그 위에 터치 줄을 둔다.
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Center(
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  color: SnackChatPalette.fillSubtle,
                  borderRadius: BorderRadius.circular(height / 2),
                ),
              ),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                enabled: enabled,
                toggled: translationOn,
                label: toggleSemanticLabel,
                excludeSemantics: true,
                onTap: enabled ? onToggle : null,
                child: Tooltip(
                  message: toggleSemanticLabel,
                  child: GestureDetector(
                    key: toggleKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: enabled ? onToggle : null,
                    child: SizedBox(
                      width: minTouch,
                      height: minTouch,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: enabled ? 1 : .45,
                          duration: duration,
                          child: AnimatedContainer(
                            key:
                                const ValueKey('snack_translation_toggle_fill'),
                            duration: duration,
                            curve: Curves.easeOut,
                            width: toggleWidth,
                            height: height,
                            decoration: BoxDecoration(
                              color: toggleFill,
                              borderRadius: BorderRadius.circular(height / 2),
                            ),
                            child: Icon(
                              Icons.translate_rounded,
                              key: const ValueKey(
                                  'snack_translation_toggle_icon'),
                              size: 18,
                              color: toggleIcon,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: languageSemanticLabel,
                excludeSemantics: true,
                onTap: onOpenLanguage,
                child: Tooltip(
                  message: languageSemanticLabel,
                  child: GestureDetector(
                    key: languageKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenLanguage,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: minTouch,
                        minHeight: minTouch,
                        maxWidth: languageMaxWidth,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 6, right: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (languageLabel.isNotEmpty)
                              Flexible(
                                child: Text(
                                  languageLabel,
                                  key: const ValueKey(
                                    'snack_translation_language_label',
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                  style: TextStyle(
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: SnackChatPalette.ink,
                                    height:
                                        isChineseUi(context) ? 1.38 : 18 / 13,
                                  ),
                                ),
                              ),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: SnackChatPalette.ink,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
