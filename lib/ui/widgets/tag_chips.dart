import 'package:flutter/material.dart';

import '../../l10n/ui_locale.dart';
import 'motion_press.dart';

/// #태그 화면 공통 색.
abstract final class TagColors {
  static const blue = Color(0xFF2E6CC2);
  static const bluePressed = Color(0xFF255CA8);
  static const blueSoft = Color(0xFFEEF4FC);
  static const disabled = Color(0xFFE5E7EB);
  static const disabledText = Color(0xFF9CA3AF);
  static const secondary = Color(0xFFF2F2F2);
  static const ink = Color(0xFF111111);
  static const muted = Color(0xFF6B7280);
  static const line = Color(0xFFE3E6EA);
}

TextStyle tagTextStyle(
        BuildContext context, double size, FontWeight weight, Color color) =>
    TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: isChineseUi(context) ? 1.3 : 1.2,
    );

/// 칩 안의 태그 글자: '# 러닝'(# 뒤 한 칸). 글·카드 안의 짧은 표기는 '#러닝'.
String hashText(String label) => '# $label';

/// 고를 수 있는 태그(공개 범위 시트): 고르면 연파랑 + 파란 ✓, 아니면 흰 바탕 + 빈 원.
class ToggleTagChip extends StatelessWidget {
  const ToggleTagChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '#$label',
      excludeSemantics: true,
      child: MotionPress(
        enabled: onTap != null,
        child: Material(
          color: selected ? TagColors.blueSoft : Colors.white,
          shape: StadiumBorder(
            side: BorderSide(
                color: selected ? TagColors.blueSoft : TagColors.line),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.only(left: 9, right: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? TagColors.blue : Colors.white,
                      border: Border.all(
                          color: selected ? TagColors.blue : TagColors.line,
                          width: 1.5),
                    ),
                    child: selected
                        ? const Icon(Icons.check_rounded,
                            size: 12, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      hashText(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(context, 14, FontWeight.w700,
                          selected ? TagColors.blue : TagColors.ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 고르는 태그 필터(검색 '태그로 친구 찾기'): 높이 32 알약, '#러닝'.
/// 기본 연회색 바탕 + 진회색 글자, 고르면 파랑 채움 + 흰 글자.
class TagFilterChip extends StatelessWidget {
  const TagFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '#$label',
      excludeSemantics: true,
      child: MotionPress(
        child: Material(
          color: selected ? TagColors.blue : const Color(0xFFF2F4F7),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 32),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '#$label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                        context,
                        13.5,
                        selected ? FontWeight.w700 : FontWeight.w600,
                        selected ? Colors.white : const Color(0xFF344054),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 글·카드·프로필에 붙은 태그(누르면 태그 페이지). 연파랑 바탕 + 파란 글자.
class TagChip extends StatelessWidget {
  const TagChip(
      {super.key, required this.label, this.onTap, this.small = false});

  final String label;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '#$label',
      excludeSemantics: true,
      child: MotionPress(
        enabled: onTap != null,
        child: Material(
          color: TagColors.blueSoft,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(minHeight: small ? 26 : 30),
              padding: EdgeInsets.symmetric(horizontal: small ? 9 : 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      '#$label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(context, small ? 12.5 : 13.5,
                          FontWeight.w600, TagColors.blue),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 고른 태그: 파랑 채움 + ✕. 누르면 빠진다. 길게 누르면 [onLongPress].
class SelectedTagChip extends StatelessWidget {
  const SelectedTagChip({
    super.key,
    required this.label,
    required this.onRemove,
    this.onLongPress,
  });

  final String label;
  final VoidCallback onRemove;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '#$label',
      excludeSemantics: true,
      child: MotionPress(
        child: Material(
          color: TagColors.blue,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onRemove,
            onLongPress: onLongPress,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.only(left: 13, right: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      hashText(label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 14, FontWeight.w700, Colors.white),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Color(0x33FFFFFF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded,
                        size: 12, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 추천 태그: 흰 바탕 + 회색 테두리, 오른쪽 숫자. 누르면 추가.
class SuggestTagChip extends StatelessWidget {
  const SuggestTagChip({
    super.key,
    required this.label,
    required this.onTap,
    this.meta,
    this.plus = false,
    this.hash = true,
  });

  final String label;
  final VoidCallback? onTap;

  /// 오른쪽 회색 보조 글자(예: '8명', '+34').
  final String? meta;

  /// '＋ #영화'처럼 앞에 ＋.
  final bool plus;

  /// false면 '#' 없이(예: '＋ 태그 찾기·만들기').
  final bool hash;

  String get _text => '${plus ? '＋ ' : ''}${hash ? hashText(label) : label}';

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: _text,
      excludeSemantics: true,
      child: MotionPress(
        enabled: onTap != null,
        child: Material(
          color: Colors.white,
          shape: const StadiumBorder(side: BorderSide(color: TagColors.line)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      _text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context,
                          14,
                          FontWeight.w600,
                          onTap == null
                              ? TagColors.disabledText
                              : TagColors.ink),
                    ),
                  ),
                  if (meta != null && meta!.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(
                      meta!,
                      style: tagTextStyle(context, 12.5, FontWeight.w500,
                          TagColors.disabledText),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 주제·종류·같이 하고 싶은 것('#' 없음). 고르면 연파랑 + ✓.
class PlainChoiceChip extends StatelessWidget {
  const PlainChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.small = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final foreground =
        selected ? const Color(0xFF1F6FB5) : const Color(0xFF3D4651);
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: MotionPress(
        enabled: onTap != null,
        child: Material(
          color: selected ? const Color(0xFFE6F2FB) : const Color(0xFFF1F3F5),
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: BoxConstraints(minHeight: small ? 26 : 36),
              padding: EdgeInsets.symmetric(horizontal: small ? 9 : 13),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Container(
                      width: 17,
                      height: 17,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1F6FB5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 12, color: Colors.white),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(context, small ? 12 : 14,
                          FontWeight.w600, foreground),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 주 버튼(파랑, 높이 48, 모서리 12, 15/700). onPressed가 null이면 회색.
class TagPrimaryButton extends StatelessWidget {
  const TagPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 48,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return MotionPress(
      enabled: enabled,
      child: SizedBox(
        height: height,
        child: FilledButton(
          onPressed: enabled ? onPressed : null,
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 16)),
            elevation: const WidgetStatePropertyAll(0),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (busy) return TagColors.blue;
              if (states.contains(WidgetState.disabled)) {
                return TagColors.disabled;
              }
              if (states.contains(WidgetState.pressed)) {
                return TagColors.bluePressed;
              }
              return TagColors.blue;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((states) =>
                states.contains(WidgetState.disabled) && !busy
                    ? TagColors.disabledText
                    : Colors.white),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          ),
          child: busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 18),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tagTextStyle(context, height < 40 ? 13.5 : 15,
                                FontWeight.w700, Colors.white)
                            .copyWith(color: null),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

/// 보조 버튼(#F2F2F2, 높이 48, 모서리 12, 15/700).
class TagSecondaryButton extends StatelessWidget {
  const TagSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 48,
    this.background = TagColors.secondary,
    this.foreground = TagColors.ink,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final double height;
  final Color background;
  final Color foreground;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return MotionPress(
      enabled: onPressed != null,
      child: SizedBox(
        height: height,
        child: TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            backgroundColor: background,
            foregroundColor: foreground,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tagTextStyle(context, height < 40 ? 13.5 : 15,
                      FontWeight.w700, foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 44/56/72 원·둥근 사각 타일 안의 '#'.
class TagHashTile extends StatelessWidget {
  const TagHashTile({super.key, this.size = 44, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: TagColors.blueSoft,
        borderRadius: BorderRadius.circular(radius ?? size / 2),
      ),
      child: Text(
        '#',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: size * .47,
          fontWeight: FontWeight.w800,
          color: TagColors.blue,
          height: 1,
        ),
      ),
    );
  }
}
