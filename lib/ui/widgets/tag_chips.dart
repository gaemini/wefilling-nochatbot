import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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

/// 칩 안의 태그 글자: '#러닝'(검색·카드·고르기 칩 모두 같은 표기).
String hashText(String label) => '#$label';

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
/// 칩 글자: 이모지가 있으면 '☕ 카페', 없으면 '#카페'('새로 알게 될 사람' 칩과 같게).
String tagChipText(String label, String? emoji) =>
    emoji == null || emoji.isEmpty ? '#$label' : '$emoji $label';

/// 칩 공통 모양: 높이 36, 회색 면(#F3F4F6) / 고르면 ink 바탕 흰 글자, 14/w700.
const _chipSurface = Color(0xFFF3F4F6);
const _chipInk = Color(0xFF111827);
const _chipText = Color(0xFF374151);

class TagFilterChip extends StatelessWidget {
  const TagFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.emoji,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '#$label',
      excludeSemantics: true,
      child: MotionPress(
        child: Material(
          color: selected ? _chipInk : _chipSurface,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      tagChipText(label, emoji),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                        context,
                        14,
                        FontWeight.w700,
                        selected ? Colors.white : _chipText,
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

/// 고른 태그: 검색 칩과 같은 크기(32)·파랑 채움 + 작은 ✕. 누르면 빠지고, 길게 누르면 [onLongPress].
class SelectedTagChip extends StatelessWidget {
  const SelectedTagChip({
    super.key,
    required this.label,
    required this.onRemove,
    this.onLongPress,
    this.emoji,
  });

  final String label;
  final VoidCallback onRemove;
  final VoidCallback? onLongPress;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '#$label',
      excludeSemantics: true,
      child: MotionPress(
        child: Material(
          color: _chipInk,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onRemove,
            onLongPress: onLongPress,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.only(left: 14, right: 10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      tagChipText(label, emoji),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 14, FontWeight.w700, Colors.white),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.close_rounded,
                      size: 14, color: Color(0xCCFFFFFF)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 추천 태그: 검색 칩과 같은 크기(32)·연회색 바탕, 오른쪽 회색 보조('8명', '+34'). 누르면 추가.
class SuggestTagChip extends StatelessWidget {
  const SuggestTagChip({
    super.key,
    required this.label,
    required this.onTap,
    this.meta,
    this.plus = false,
    this.hash = true,
    this.emoji,
  });

  final String label;
  final VoidCallback? onTap;

  /// 있으면 '☕ 카페 8명'처럼 앞에 이모지(# 없이).
  final String? emoji;

  /// 오른쪽 회색 보조 글자(예: '8명', '+34').
  final String? meta;

  /// '＋ #영화'처럼 앞에 ＋.
  final bool plus;

  /// false면 '#' 없이(예: '＋ 태그 찾기·만들기').
  final bool hash;

  String get _text => '${plus ? '＋ ' : ''}'
      '${emoji != null && emoji!.isNotEmpty ? '$emoji $label' : hash ? hashText(label) : label}';

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: _text,
      excludeSemantics: true,
      child: MotionPress(
        enabled: enabled,
        child: Material(
          color: _chipSurface,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
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
                          FontWeight.w700,
                          enabled ? _chipText : TagColors.disabledText),
                    ),
                  ),
                  if (meta != null && meta!.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Text(
                      meta!,
                      // 숫자는 w600, 글자색의 60%('새로 알게 될 사람' 칩과 같게).
                      style: tagTextStyle(context, 13, FontWeight.w600,
                          _chipText.withValues(alpha: .6)),
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

/// 태그 화면 버튼 크기: 큰 버튼 44(글자 14), 작은 버튼 32(글자 13).
/// 앱 테마의 버튼 최소 크기(120×48)를 쓰지 않고 글자 폭에 맞춘다.
ButtonStyle _tagButtonStyle({
  required double height,
  required Color background,
  required Color foreground,
  Color? pressed,
  bool enabled = true,
}) {
  final small = height < 40;
  return ButtonStyle(
    minimumSize: WidgetStatePropertyAll(Size(0, height)),
    fixedSize: WidgetStatePropertyAll(Size.fromHeight(height)),
    maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 56)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: small ? 12 : 16)),
    elevation: const WidgetStatePropertyAll(0),
    shape: WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(small ? 9 : 12))),
    backgroundColor: WidgetStateProperty.resolveWith((states) {
      if (!enabled || states.contains(WidgetState.disabled)) {
        return enabled ? background : TagColors.disabled;
      }
      if (states.contains(WidgetState.pressed) && pressed != null) {
        return pressed;
      }
      return background;
    }),
    foregroundColor:
        WidgetStatePropertyAll(enabled ? foreground : TagColors.disabledText),
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
  );
}

Widget _buttonLabel(BuildContext context, String label, IconData? icon,
    double height, Color color) {
  final small = height < 40;
  // 큰 글자 배율에서도 버튼 밖으로 넘치지 않게 줄여 맞춘다.
  return FittedBox(
    fit: BoxFit.scaleDown,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: small ? 15 : 17, color: color),
          const SizedBox(width: 4),
        ],
        Text(
          label,
          maxLines: 1,
          style: tagTextStyle(context, small ? 13 : 14, FontWeight.w700, color),
        ),
      ],
    ),
  );
}

/// 주 버튼(파랑). onPressed가 null이면 회색.
class TagPrimaryButton extends StatelessWidget {
  const TagPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 44,
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
    final enabled = onPressed != null || busy;
    return MotionPress(
      enabled: onPressed != null && !busy,
      child: FilledButton(
        onPressed: busy ? () {} : onPressed,
        style: _tagButtonStyle(
          height: height,
          background: TagColors.blue,
          pressed: TagColors.bluePressed,
          foreground: Colors.white,
          enabled: enabled,
        ),
        child: busy
            ? SizedBox.square(
                dimension: height < 40 ? 14 : 18,
                child: const CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : _buttonLabel(context, label, icon, height,
                enabled ? Colors.white : TagColors.disabledText),
      ),
    );
  }
}

/// 보조 버튼(기본 #F2F2F2). 큰 버튼 44, 작은 버튼 32.
class TagSecondaryButton extends StatelessWidget {
  const TagSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.height = 44,
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
      child: TextButton(
        onPressed: onPressed,
        style: _tagButtonStyle(
            height: height, background: background, foreground: foreground),
        child: _buttonLabel(context, label, icon, height, foreground),
      ),
    );
  }
}

/// 태그 줄 오른쪽 버튼: [추가](연파랑) / [추가됨](연회색). 높이 30, 두 상태 같은 폭.
class TagRowActionButton extends StatelessWidget {
  const TagRowActionButton({
    super.key,
    required this.added,
    required this.onPressed,
    this.busy = false,
  });

  final bool added;
  final VoidCallback onPressed;
  final bool busy;

  static const double width = 68;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      width: width,
      child: busy
          ? Container(
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: TagColors.blueSoft,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: TagColors.blue),
              ),
            )
          : TagSecondaryButton(
              label: added ? l10n.tagAddedShort : l10n.tagAdd,
              height: 30,
              background: added ? TagColors.secondary : TagColors.blueSoft,
              foreground: added ? TagColors.muted : TagColors.blue,
              onPressed: onPressed,
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
