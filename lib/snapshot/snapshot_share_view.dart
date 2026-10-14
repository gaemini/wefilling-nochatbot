// lib/snapshot/snapshot_share_view.dart
// 스낵 만들기 공유 단계(v3): 검정 바탕, 위쪽 사진, 글자만으로 고르는 두 설정.
// 서비스·업로드를 모르는 표현 위젯이며 값과 콜백만 받는다.
// 글자 크기는 고정값이고 사용자 글자 확대만 1.25배까지 따른다.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../l10n/ui_locale.dart';
import '../models/friend_category.dart';
import '../models/snapshot.dart';
import '../ui/widgets/user_avatar.dart';
import 'snapshot_strings.dart';
import '../design/tokens.dart';

const Color _accent = Color(0xFF2C6BC0);

/// 3장 표의 글자 사양. 테스트가 이 값을 그대로 검사한다.
/// 고르기·편집 단계(snapshot_create_widgets.dart)도 같은 사양을 쓴다.
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
  static const groupName = ShareTextSpec(14, 20, FontWeight.w600, 1);
  static const groupCount = ShareTextSpec(12, 17, FontWeight.w400, .45);
  static const audienceTitle = ShareTextSpec(12, 17, FontWeight.w400, .55);
  static const audienceName = ShareTextSpec(11, 15, FontWeight.w400, .8);
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

/// 그룹 공개 대상 한 명(표시용). 업로드 값에는 쓰지 않는다.
class ShareAudienceMember {
  const ShareAudienceMember({
    required this.uid,
    required this.name,
    this.photoUrl = '',
  });

  final String uid;
  final String name;
  final String photoUrl;
}

/// 그룹의 멤버 중 지금도 친구인 사람만(서버 조회 없음, 구독 중인 친구 목록 기준).
/// [friends]가 null이면 아직 로딩 중이다.
@visibleForTesting
List<ShareAudienceMember>? shareCategoryMembers(
  FriendCategory category,
  List<ShareAudienceMember>? friends,
) {
  if (friends == null) return null;
  final ids = category.friendIds.toSet();
  return friends.where((friend) => ids.contains(friend.uid)).toList();
}

/// 선택한 그룹 멤버의 합집합(uid 중복 제거). 선택한 그룹 순서, 그룹 안에서는
/// 친구 목록 순서를 유지한다.
@visibleForTesting
List<ShareAudienceMember>? shareAudience(
  List<FriendCategory> categories,
  List<String> selectedIds,
  List<ShareAudienceMember>? friends,
) {
  if (friends == null) return null;
  final byId = {for (final category in categories) category.id: category};
  final seen = <String>{};
  final result = <ShareAudienceMember>[];
  for (final id in selectedIds) {
    final category = byId[id];
    if (category == null) continue;
    for (final member in shareCategoryMembers(category, friends)!) {
      if (seen.add(member.uid)) result.add(member);
    }
  }
  return result;
}

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
    this.friends,
    this.shareCompleted = false,
  });

  /// 업로드가 끝나 닫히기 직전(체크를 보인다, 모션 2부 G-4).
  final bool shareCompleted;

  /// 구독 중인 친구 목록(표시용). null이면 로딩 중.
  final List<ShareAudienceMember>? friends;

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
          // 그룹을 고르면 사진을 250으로 줄여 목록이 들어갈 자리를 만든다.
          final groupMode = visibility == SnapshotVisibility.category;
          final targetPhoto = groupMode ? 250.0 : photoHeight;
          final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
          return TweenAnimationBuilder<double>(
            tween: Tween<double>(end: targetPhoto),
            duration: reduce ? Duration.zero : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            builder: (context, photoHeight, _) => Stack(
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
                top: photoHeight - (groupMode ? 44 : 50),
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
          ),
          );
        },
      ),
    );
  }

  Widget _settings(BuildContext context, SnapshotStrings strings, double maxWidth) {
    final audience = shareAudience(categories, selectedCategoryIds, friends);
    final visibilityHint = switch (visibility) {
      SnapshotVisibility.public => strings.publicDescription,
      SnapshotVisibility.friends => strings.friendsDescription,
      SnapshotVisibility.category => categories.isEmpty
          ? strings.noGroups
          : strings.groupVisibilityHint,
    };
    final responseHint = responseMode == SnapshotResponseMode.reactions
        ? strings.responseFeelOnlyHint
        : strings.responseFriendReplyHint;
    final groupMode = visibility == SnapshotVisibility.category;
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
        Text(
          visibilityHint,
          key: const ValueKey('share_visibility_hint'),
          style: shareTextStyle(context, ShareTextSpec.hint),
        ),
        if (groupMode && categories.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var i = 0; i < categories.length; i++)
            _AudienceGroupRow(
              key: ValueKey<String>('share-group-${categories[i].id}'),
              category: categories[i],
              members: shareCategoryMembers(categories[i], friends),
              selected: selectedCategoryIds.contains(categories[i].id),
              showDivider: i > 0,
              onTap: () => onToggleCategory(categories[i].id),
            ),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.white.withValues(alpha: .12),
          ),
          _AudiencePreviewStrip(audience: audience),
        ],
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
    final audience = shareAudience(categories, selectedCategoryIds, friends);
    final showCount = visibility == SnapshotVisibility.category &&
        audience != null &&
        audience.isNotEmpty;
    final label = uploading
        ? strings.sharingProgress((uploadProgress.clamp(0, 1) * 100).round())
        : (showCount
            ? strings.shareSnackCount(audience.length)
            : strings.shareSnackButton);
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
                  child: shareCompleted
                      // 100%: 체크가 0 → 1.15 → 1로 튀어나온다(delight).
                      ? TweenAnimationBuilder<double>(
                          key: const ValueKey('share_done_check'),
                          tween: Tween<double>(
                            begin: MotionTokens.reduceMotion(context) ? 1 : 0,
                            end: 1,
                          ),
                          duration:
                              MotionTokens.of(context, MotionTokens.delight),
                          builder: (context, t, child) => Transform.scale(
                            scale: t < .5
                                ? 1.15 * (t / .5)
                                : 1.15 - .15 * ((t - .5) / .5),
                            child: child,
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 26,
                          ),
                        )
                      : Text(
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
                      // 진행 값 사이를 튀지 않게 state로 보간한다.
                      child: TweenAnimationBuilder<double>(
                        tween: Tween<double>(
                          end: shareCompleted
                              ? 1
                              : uploadProgress.clamp(0.0, 1.0).toDouble(),
                        ),
                        duration: MotionTokens.of(context, MotionTokens.state),
                        curve: MotionTokens.curve,
                        builder: (context, value, child) =>
                            FractionallySizedBox(
                          key: const ValueKey('share_progress'),
                          widthFactor: value,
                          child: child,
                        ),
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

/// 글자 선택지 묶음(선택 600 흰색 + 2pt 밑줄, 비선택 500 흰색 40%).
/// 공유 단계의 [_TextChoiceRow]와 같은 선택지를 고르기·편집 단계에서 재사용한다.
class ShareChoiceGroup<T> extends StatelessWidget {
  const ShareChoiceGroup({
    super.key,
    required this.keyPrefix,
    required this.value,
    required this.options,
    required this.onChanged,
    this.gap = 18,
  });

  final String keyPrefix;
  final T? value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options)
          _Choice(
            key: ValueKey<String>('$keyPrefix-choice-${option.$1}'),
            label: option.$2,
            selected: option.$1 == value,
            gap: gap,
            onTap: () => onChanged(option.$1),
          ),
      ],
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

/// 그룹 한 줄: 선택 원 + 이름/인원 + 오른쪽 멤버 사진(최대 4, 겹침).
class _AudienceGroupRow extends StatelessWidget {
  const _AudienceGroupRow({
    super.key,
    required this.category,
    required this.members,
    required this.selected,
    required this.showDivider,
    required this.onTap,
  });

  final FriendCategory category;

  /// null이면 친구 목록 로딩 중.
  final List<ShareAudienceMember>? members;
  final bool selected;
  final bool showDivider;
  final VoidCallback onTap;

  static const double _avatar = 24;
  static const double _overlap = 7;

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final list = members;
    final count = list?.length;
    final countLabel = count == null ? '…' : strings.groupMemberCount(count);
    final shown = (list ?? const <ShareAudienceMember>[]).take(4).toList();
    final extra = count == null ? 0 : math.max(0, count - shown.length);
    final avatarsWidth = shown.isEmpty
        ? (count == null ? _avatar : 0.0)
        : _avatar + (shown.length - 1) * (_avatar - _overlap);
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: false,
      button: true,
      label: '${category.name}, $countLabel',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          decoration: BoxDecoration(
            border: showDivider
                ? Border(
                    top: BorderSide(
                      color: Colors.white.withValues(alpha: .08),
                    ),
                  )
                : null,
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration:
                    reduce ? Duration.zero : const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? Colors.white : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: .35),
                    width: 1.5,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check_rounded,
                        size: 12, color: Colors.black)
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      category.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: shareTextStyle(context, ShareTextSpec.groupName),
                    ),
                    Text(
                      countLabel,
                      key: ValueKey<String>('group-count-${category.id}'),
                      maxLines: 1,
                      style: shareTextStyle(context, ShareTextSpec.groupCount),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (count == null)
                Container(
                  width: _avatar,
                  height: _avatar,
                  decoration: const BoxDecoration(
                    color: Color(0xFF3A3A3C),
                    shape: BoxShape.circle,
                  ),
                )
              else if (shown.isNotEmpty)
                SizedBox(
                  width: avatarsWidth,
                  height: _avatar,
                  child: Stack(
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        Positioned(
                          left: i * (_avatar - _overlap),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.black, width: 2),
                            ),
                            child: UserAvatar(
                              uid: shown[i].uid,
                              photoUrl: shown[i].photoUrl,
                              photoVersion: 0,
                              isAnonymous: false,
                              size: _avatar - 4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              if (extra > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '+$extra',
                  maxLines: 1,
                  style: shareTextStyle(
                    context,
                    const ShareTextSpec(12, 17, FontWeight.w400, .55),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 선택한 그룹으로 볼 수 있는 사람(합집합)을 가로 스크롤로 보여 준다. 표시 전용.
class _AudiencePreviewStrip extends StatefulWidget {
  const _AudiencePreviewStrip({required this.audience});

  /// null이면 로딩 중(자리 표시).
  final List<ShareAudienceMember>? audience;

  @override
  State<_AudiencePreviewStrip> createState() => _AudiencePreviewStripState();
}

class _AudiencePreviewStripState extends State<_AudiencePreviewStrip> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<ShareAudienceMember> _items;

  @override
  void initState() {
    super.initState();
    _items = List<ShareAudienceMember>.of(
      widget.audience ?? const <ShareAudienceMember>[],
    );
  }

  @override
  void didUpdateWidget(covariant _AudiencePreviewStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.audience ?? const <ShareAudienceMember>[];
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = reduce ? Duration.zero : const Duration(milliseconds: 200);
    final list = _listKey.currentState;
    if (list == null) {
      _items = List<ShareAudienceMember>.of(next);
      return;
    }
    final nextIds = next.map((m) => m.uid).toSet();
    // 빠진 사람은 페이드로 지운다(뒤에서부터 인덱스가 어긋나지 않게).
    for (var i = _items.length - 1; i >= 0; i--) {
      if (nextIds.contains(_items[i].uid)) continue;
      final removed = _items.removeAt(i);
      list.removeItem(
        i,
        (context, animation) => FadeTransition(
          opacity: animation,
          child: _AudiencePerson(member: removed),
        ),
        duration: duration,
      );
    }
    // 새로 생긴 사람은 새 순서의 위치에 0.8 → 1로 나타낸다.
    for (var i = 0; i < next.length; i++) {
      if (i < _items.length && _items[i].uid == next[i].uid) continue;
      final existing = _items.indexWhere((m) => m.uid == next[i].uid);
      if (existing >= 0) {
        // 순서만 바뀐 경우: 위치를 옮긴다.
        _items.removeAt(existing);
        list.removeItem(existing, (c, a) => const SizedBox.shrink(),
            duration: Duration.zero);
      }
      _items.insert(i, next[i]);
      list.insertItem(i, duration: duration);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final audience = widget.audience;
    final count = audience?.length;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final title = count == null
        ? '…'
        : (count == 0 ? strings.audienceEmpty : strings.audienceCount(count));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            key: const ValueKey('audience_title'),
            style: shareTextStyle(context, ShareTextSpec.audienceTitle),
          ),
          if (count == null || count > 0) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 40 + 6 + 15 + 4,
              child: count == null
                  ? Row(
                      children: [
                        for (var i = 0; i < 4; i++)
                          Container(
                            width: 40,
                            height: 40,
                            margin: const EdgeInsets.only(right: 12),
                            decoration: const BoxDecoration(
                              color: Color(0xFF3A3A3C),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    )
                  : AnimatedList(
                      key: _listKey,
                      scrollDirection: Axis.horizontal,
                      initialItemCount: _items.length,
                      itemBuilder: (context, index, animation) {
                        if (index >= _items.length) {
                          return const SizedBox.shrink();
                        }
                        final person = _AudiencePerson(member: _items[index]);
                        return FadeTransition(
                          opacity: animation,
                          child: reduce
                              ? person
                              : ScaleTransition(
                                  scale: Tween<double>(begin: .8, end: 1)
                                      .animate(animation),
                                  child: person,
                                ),
                        );
                      },
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AudiencePerson extends StatelessWidget {
  const _AudiencePerson({required this.member});

  final ShareAudienceMember member;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey<String>('audience-${member.uid}'),
      width: 52,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          UserAvatar(
            uid: member.uid,
            photoUrl: member.photoUrl,
            photoVersion: 0,
            isAnonymous: false,
            size: 40,
          ),
          const SizedBox(height: 6),
          Text(
            member.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: shareTextStyle(context, ShareTextSpec.audienceName),
          ),
        ],
      ),
    );
  }
}
