// lib/snapshot/snapshot_share_view.dart
// 스낵 만들기 공유 단계(v3): 검정 바탕, 위쪽 사진, 글자만으로 고르는 두 설정.
// 서비스·업로드를 모르는 표현 위젯이며 값과 콜백만 받는다.
// 글자 크기는 고정값이고 사용자 글자 확대만 1.25배까지 따른다.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/ui_locale.dart';
import '../models/friend_category.dart';
import '../models/snapshot.dart';
import 'snapshot_strings.dart';

const Color _accent = Color(0xFF2C6BC0);

/// 3장 표의 글자 사양. 테스트가 이 값을 그대로 검사한다.
@visibleForTesting
class ShareTextSpec {
  const ShareTextSpec(this.size, this.lineHeight, this.weight, this.alpha);
  final double size;
  final double lineHeight;
  final FontWeight weight;
  final double alpha;

  static const back = ShareTextSpec(14, 20, FontWeight.w500, 1);
  static const lifetime = ShareTextSpec(12, 16, FontWeight.w400, .7);
  static const rowTitle = ShareTextSpec(14, 20, FontWeight.w600, 1);
  static const choiceOn = ShareTextSpec(14, 20, FontWeight.w600, 1);
  static const choiceOff = ShareTextSpec(14, 20, FontWeight.w500, .4);
  static const groupOn = ShareTextSpec(13, 18, FontWeight.w600, 1);
  static const groupOff = ShareTextSpec(13, 18, FontWeight.w500, .4);
  static const hint = ShareTextSpec(12, 17, FontWeight.w400, .55);
  static const button = ShareTextSpec(15, 20, FontWeight.w600, 1);
}

TextStyle shareTextStyle(
  BuildContext context,
  ShareTextSpec spec, {
  Color? color,
}) =>
    TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: spec.size,
      height: spec.lineHeight / spec.size,
      fontWeight: spec.weight,
      letterSpacing: -0.2,
      color: color ?? Colors.white.withValues(alpha: spec.alpha),
    );

class SnapshotShareView extends StatelessWidget {
  const SnapshotShareView({
    super.key,
    required this.media,
    required this.visibility,
    required this.responseMode,
    required this.categories,
    required this.selectedCategoryIds,
    required this.uploading,
    required this.uploadProgress,
    required this.onBack,
    required this.onVisibilityChanged,
    required this.onResponseModeChanged,
    required this.onToggleCategory,
    required this.onShare,
  });

  /// 사진/영상. 이 위젯이 틀(가로 꽉, cover)을 만든다.
  final Widget media;
  final SnapshotVisibility visibility;
  final SnapshotResponseMode responseMode;
  final List<FriendCategory> categories;
  final List<String> selectedCategoryIds;
  final bool uploading;
  final double uploadProgress;
  final VoidCallback? onBack;
  final ValueChanged<SnapshotVisibility> onVisibilityChanged;
  final ValueChanged<SnapshotResponseMode> onResponseModeChanged;
  final ValueChanged<String> onToggleCategory;
  final VoidCallback onShare;

  bool get _groupMissing =>
      visibility == SnapshotVisibility.category && selectedCategoryIds.isEmpty;

  /// 공개 범위가 그룹인데 고른 그룹이 없으면 공유할 수 없다.
  bool get canShare => !uploading && !_groupMissing;

  static const double _buttonHeight = 52;
  static const double _buttonBottom = 20;

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final padding = MediaQuery.paddingOf(context);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final height = constraints.maxHeight;
          final width = constraints.maxWidth;
          final buttonArea = _buttonHeight + _buttonBottom + padding.bottom + 12;
          // 설정 영역이 쓸 수 있는 높이가 부족하면 사진을 먼저 줄인다(최소 300).
          const settingsNeed = 250.0;
          var photoHeight = math.min(470.0, height * .56);
          final maxByNeed = height + 50 - buttonArea - settingsNeed;
          photoHeight = math.max(300.0, math.min(photoHeight, maxByNeed));
          photoHeight = math.min(photoHeight, math.max(120.0, height - buttonArea));
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: photoHeight,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRect(child: media),
                    const Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 120,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0xA8000000), Color(0x00000000)],
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 200,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Color(0x00000000), Color(0xFF000000)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: padding.top + 8,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        key: const ValueKey('share_back'),
                        behavior: HitTestBehavior.opaque,
                        onTap: onBack,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                            minHeight: 44,
                            minWidth: 44,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              widthFactor: 1,
                              child: Text(
                                '‹ ${strings.shareBack}',
                                style: shareTextStyle(
                                  context,
                                  ShareTextSpec.back,
                                  color: Colors.white.withValues(
                                    alpha: onBack == null ? .5 : 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          strings.shareLifetimeNote,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: shareTextStyle(context, ShareTextSpec.lifetime),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: photoHeight - 50,
                bottom: buttonArea,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _settings(context, strings, width - 40),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: _buttonBottom + padding.bottom,
                height: _buttonHeight,
                child: _shareButton(context, strings),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _settings(BuildContext context, SnapshotStrings strings, double maxWidth) {
    final visibilityHint = switch (visibility) {
      SnapshotVisibility.public => strings.publicDescription,
      SnapshotVisibility.friends => strings.friendsDescription,
      SnapshotVisibility.category => categories.isEmpty
          ? strings.noGroups
          : (selectedCategoryIds.isEmpty
              ? strings.groupRequired
              : strings.groupsDescription),
    };
    final responseHint = responseMode == SnapshotResponseMode.reactions
        ? strings.responseFeelOnlyHint
        : strings.responseFriendReplyHint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TextChoiceRow<SnapshotVisibility>(
          keyPrefix: 'visibility',
          title: strings.shareVisibilityTitle,
          maxWidth: maxWidth,
          value: visibility,
          options: [
            (SnapshotVisibility.public, strings.shareChoicePublic),
            (SnapshotVisibility.friends, strings.shareChoiceFriends),
            (SnapshotVisibility.category, strings.shareChoiceGroups),
          ],
          onChanged: onVisibilityChanged,
        ),
        _GroupChoices(
          visible: visibility == SnapshotVisibility.category &&
              categories.isNotEmpty,
          categories: categories,
          selectedIds: selectedCategoryIds,
          onToggle: onToggleCategory,
        ),
        Text(
          visibilityHint,
          key: const ValueKey('share_visibility_hint'),
          style: shareTextStyle(
            context,
            ShareTextSpec.hint,
            color: _groupMissing && categories.isNotEmpty
                ? const Color(0xFFFFB4A9)
                : null,
          ),
        ),
        const SizedBox(height: 14),
        Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: .12),
        ),
        _TextChoiceRow<SnapshotResponseMode>(
          keyPrefix: 'response',
          title: strings.shareResponseTitle,
          maxWidth: maxWidth,
          value: responseMode,
          options: [
            (SnapshotResponseMode.reactions, strings.responseFeelOnly),
            (SnapshotResponseMode.replies, strings.responseFriendReply),
          ],
          onChanged: onResponseModeChanged,
        ),
        Text(
          responseHint,
          key: const ValueKey('share_response_hint'),
          style: shareTextStyle(context, ShareTextSpec.hint),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _shareButton(BuildContext context, SnapshotStrings strings) {
    final label = uploading
        ? strings.sharingProgress((uploadProgress.clamp(0, 1) * 100).round())
        : strings.shareSnackButton;
    return Semantics(
      button: true,
      enabled: canShare,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: canShare || uploading ? (uploading ? .85 : 1) : .35,
        child: Material(
          color: _accent,
          borderRadius: BorderRadius.circular(26),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('share_button'),
            onTap: canShare ? onShare : null,
            child: Stack(
              children: [
                Center(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: shareTextStyle(context, ShareTextSpec.button),
                  ),
                ),
                if (uploading)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 2,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        key: const ValueKey('share_progress'),
                        widthFactor: uploadProgress.clamp(0.0, 1.0),
                        child: const ColoredBox(
                          color: Colors.white,
                          child: SizedBox(height: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 줄 이름 + 글자만 있는 선택지. 한 줄에 안 들어가면 간격 18 → 14 → 다음 줄.
class _TextChoiceRow<T> extends StatelessWidget {
  const _TextChoiceRow({
    required this.keyPrefix,
    required this.title,
    required this.maxWidth,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String keyPrefix;
  final String title;
  final double maxWidth;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  double _textWidth(BuildContext context, String text, ShareTextSpec spec) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: shareTextStyle(context, spec)),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width;
    painter.dispose();
    return width;
  }

  /// 선택지 상자 폭: 글자 + 간격, 최소 44.
  double _optionsWidth(BuildContext context, double gap) {
    var sum = 0.0;
    for (final option in options) {
      sum += math.max(
        44.0,
        _textWidth(context, option.$2, ShareTextSpec.choiceOn) + gap,
      );
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    final titleWidth = _textWidth(context, title, ShareTextSpec.rowTitle);
    double? gap;
    for (final candidate in const [18.0, 14.0]) {
      if (titleWidth + 12 + _optionsWidth(context, candidate) <= maxWidth) {
        gap = candidate;
        break;
      }
    }
    Widget choices(double g) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in options)
              _Choice(
                key: ValueKey<String>('$keyPrefix-choice-${option.$1}'),
                label: option.$2,
                selected: option.$1 == value,
                gap: g,
                onTap: () => onChanged(option.$1),
              ),
          ],
        );
    final titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: shareTextStyle(context, ShareTextSpec.rowTitle),
    );
    if (gap != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 0),
        child: Row(
          key: ValueKey<String>('$keyPrefix-row'),
          children: [
            Expanded(child: titleText),
            choices(gap),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Column(
        key: ValueKey<String>('$keyPrefix-row'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleText,
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: choices(14),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    super.key,
    required this.label,
    required this.selected,
    required this.gap,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final double gap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final spec = selected ? ShareTextSpec.choiceOn : ShareTextSpec.choiceOff;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gap / 2),
            child: Center(
              widthFactor: 1,
              child: IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      label,
                      maxLines: 1,
                      softWrap: false,
                      textAlign: TextAlign.center,
                      style: shareTextStyle(context, spec),
                    ),
                    const SizedBox(height: 2),
                    SizedBox(
                      height: 2,
                      child: AnimatedScale(
                        scale: selected ? 1 : 0,
                        duration: reduce
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 그룹 이름을 글자 버튼으로 펼친다. 선택된 그룹 앞에는 `✓` 글자를 붙인다.
class _GroupChoices extends StatelessWidget {
  const _GroupChoices({
    required this.visible,
    required this.categories,
    required this.selectedIds,
    required this.onToggle,
  });

  final bool visible;
  final List<FriendCategory> categories;
  final List<String> selectedIds;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 180);
    return AnimatedSize(
      duration: duration,
      alignment: Alignment.topCenter,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        child: visible
            ? SingleChildScrollView(
                key: const ValueKey('share_groups'),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final category in categories)
                      _group(context, category),
                  ],
                ),
              )
            : const SizedBox(width: double.infinity),
      ),
    );
  }

  Widget _group(BuildContext context, FriendCategory category) {
    final selected = selectedIds.contains(category.id);
    final spec = selected ? ShareTextSpec.groupOn : ShareTextSpec.groupOff;
    return Semantics(
      button: true,
      selected: selected,
      label: category.name,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey<String>('share-group-${category.id}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => onToggle(category.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
          child: Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              widthFactor: 1,
              child: Text(
                selected ? '✓ ${category.name}' : category.name,
                maxLines: 1,
                softWrap: false,
                style: shareTextStyle(context, spec),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
