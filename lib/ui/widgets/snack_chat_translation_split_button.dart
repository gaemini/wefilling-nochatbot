// lib/ui/widgets/snack_chat_translation_split_button.dart
// 상단 바 번역 묶음: [번역 스위치] [언어 ⌄]. 공개 API는 이전 분할 버튼과 같다.
// 스낵챗·DM·포스트 상세·스낵 댓글 시트가 함께 쓴다.

import 'package:flutter/material.dart';

import 'translate_switch.dart';

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
    this.languageMaxWidth = 96,
    this.busy = false,
    this.failed = false,
  });

  /// 테스트·화면별 키(DM은 dm_translation_toggle 등).
  final Key toggleKey;
  final Key languageKey;

  /// 언어 버튼 최대 폭(넘치면 언어 이름이 말줄임).
  final double languageMaxWidth;

  /// 방 번역이 켜져 있는지(!showsOriginal).
  final bool translationOn;

  /// 방 모드 로딩이 끝났는지. false면 스위치가 비활성이다.
  final bool enabled;

  /// 현재 번역 언어의 고유 이름(한국어, English, 日本語 …). 비면 `언어`.
  final String languageLabel;

  /// 스위치를 눌렀을 때 일어날 일(번역 보기 / 원문 보기).
  final String toggleSemanticLabel;
  final String languageSemanticLabel;
  final VoidCallback onToggle;
  final VoidCallback onOpenLanguage;

  /// 번역 중(아이콘이 돈다) · 마지막 번역 실패(누르면 다시 시도).
  final bool busy;
  final bool failed;

  @override
  Widget build(BuildContext context) {
    // 글자 없는 번역 스위치 + `{언어} ⌄` 글자 버튼.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TranslateSwitch(
            key: toggleKey,
            value: translationOn,
            busy: busy,
            failed: failed,
            semanticLabel: toggleSemanticLabel,
            onChanged: enabled ? (_) => onToggle() : null,
          ),
          const SizedBox(width: 2),
          TranslateLanguageButton(
            key: languageKey,
            languageLabel: languageLabel,
            semanticLabel: languageSemanticLabel,
            maxWidth: languageMaxWidth,
            onPressed: onOpenLanguage,
          ),
        ],
      ),
    );
  }
}
