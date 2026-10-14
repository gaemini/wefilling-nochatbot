// lib/ui/widgets/translate_hints.dart
// 번역 스위치 선택 항목(기본 꺼짐, 기능 플래그로 켠다).
// - [TranslateSingleMessageButton]: 방 번역이 꺼져 있을 때 다른 언어로 알려진
//   상대 메시지 옆의 작은 번역 단추(그 메시지 하나만 번역).
// - [TranslateFirstHintBar]: 입력창 위 "다른 언어 메시지가 있어요" 알림 줄.
// - [TranslateHintStore]: 알림 줄을 닫았는지 방별로 기억한다.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../design/tokens.dart';
import '../../l10n/ui_locale.dart';
import '../../services/feature_flag_service.dart';

const Color _kPoint = Color(0xFF2C6BC0);

class TranslateHintFlags {
  TranslateHintFlags._();

  static bool get singleMessageButton => FeatureFlagService()
      .isFeatureEnabled(FeatureFlagService.FEATURE_TRANSLATE_SINGLE_MESSAGE_BUTTON);

  static bool get firstHint => FeatureFlagService()
      .isFeatureEnabled(FeatureFlagService.FEATURE_TRANSLATE_FIRST_HINT);
}

class TranslateHintStrings {
  TranslateHintStrings._();

  static String _pick(BuildContext context, String ko, String en, String zh) {
    if (isChineseUi(context)) return zh;
    return Localizations.localeOf(context).languageCode == 'ko' ? ko : en;
  }

  static String singleA11y(BuildContext context) =>
      _pick(context, '이 메시지 번역', 'Translate this message', '翻译这条消息');

  static String hintTitle(BuildContext context) => _pick(
      context, '다른 언어 메시지가 있어요', 'Messages in other languages', '有其他语言的消息');

  static String hintBody(BuildContext context, String language) => _pick(
        context,
        '$language로 바꿔서 볼 수 있어요',
        'You can read them in $language',
        '可以用$language查看',
      );

  static String hintAction(BuildContext context) =>
      _pick(context, '번역해서 보기', 'Translate', '翻译查看');

  static String close(BuildContext context) => _pick(context, '닫기', 'Close', '关闭');
}

/// 지름 30 흰 원 + 번역 아이콘(누름 영역 44). 누르면 .92로 작아지고 그림자가 사라진다.
class TranslateSingleMessageButton extends StatefulWidget {
  const TranslateSingleMessageButton({
    super.key,
    required this.onPressed,
    this.busy = false,
  });

  final VoidCallback? onPressed;
  final bool busy;

  @override
  State<TranslateSingleMessageButton> createState() =>
      _TranslateSingleMessageButtonState();
}

class _TranslateSingleMessageButtonState
    extends State<TranslateSingleMessageButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _pressed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant TranslateSingleMessageButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    final spin = widget.busy && !MotionTokens.reduceMotion(context);
    if (spin && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!spin && _spin.isAnimating) {
      _spin
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = MotionTokens.of(context, MotionTokens.fast);
    final enabled = widget.onPressed != null && !widget.busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: TranslateHintStrings.singleA11y(context),
      excludeSemantics: true,
      onTap: enabled ? widget.onPressed : null,
      child: GestureDetector(
        key: const ValueKey('translate_single_message_button'),
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: () => setState(() => _pressed = false),
        onTap: enabled ? widget.onPressed : null,
        child: SizedBox.square(
          dimension: 44,
          child: Center(
            child: AnimatedScale(
              scale: _pressed ? .92 : 1,
              duration: duration,
              curve: MotionTokens.curve,
              child: AnimatedContainer(
                duration: duration,
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0x0F000000), width: .5),
                  boxShadow: _pressed
                      ? const []
                      : const [
                          BoxShadow(
                            color: Color(0x26000000),
                            offset: Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                ),
                child: AnimatedBuilder(
                  animation: _spin,
                  builder: (context, child) => Transform.rotate(
                    angle: _spin.value * 6.283185307179586,
                    child: child,
                  ),
                  child: Opacity(
                    opacity: widget.busy && MotionTokens.reduceMotion(context)
                        ? .5
                        : 1,
                    child: const Icon(Icons.translate, size: 15, color: _kPoint),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 입력창 위 알림 줄: 왼쪽 두 줄 글자, 오른쪽 [번역해서 보기] + ×.
class TranslateFirstHintBar extends StatelessWidget {
  const TranslateFirstHintBar({
    super.key,
    required this.languageLabel,
    required this.onTranslate,
    required this.onDismiss,
  });

  final String languageLabel;
  final VoidCallback onTranslate;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
    );
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Container(
        key: const ValueKey('translate_first_hint'),
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1F000000),
              offset: Offset(0, 4),
              blurRadius: 18,
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    TranslateHintStrings.hintTitle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: base.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111111),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    TranslateHintStrings.hintBody(context, languageLabel),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: base.copyWith(
                      fontSize: 12.5,
                      color: const Color(0xFF707070),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                boxShadow: const [
                  BoxShadow(color: Color(0xFF1E4F92), offset: Offset(0, 2)),
                ],
              ),
              child: Material(
                color: _kPoint,
                borderRadius: BorderRadius.circular(11),
                child: InkWell(
                  key: const ValueKey('translate_first_hint_action'),
                  borderRadius: BorderRadius.circular(11),
                  onTap: onTranslate,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 34),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          TranslateHintStrings.hintAction(context),
                          style: base.copyWith(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              key: const ValueKey('translate_first_hint_close'),
              tooltip: TranslateHintStrings.close(context),
              onPressed: onDismiss,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: const Color(0xFF8A8A8A),
            ),
          ],
        ),
      ),
    );
  }
}

/// 알림 줄을 닫았는지(또는 번역을 켰는지) 방별로 기억한다.
class TranslateHintStore {
  TranslateHintStore._();

  static String _key(String uid, String room) =>
      'translate_hint_dismissed:$uid:$room';

  static Future<bool> isDismissed(String uid, String room) async {
    if (uid.isEmpty || room.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(uid, room)) ?? false;
  }

  static Future<void> dismiss(String uid, String room) async {
    if (uid.isEmpty || room.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(uid, room), true);
  }
}
