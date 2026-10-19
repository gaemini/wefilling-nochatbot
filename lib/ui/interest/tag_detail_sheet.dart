import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../models/interest_tag.dart';
import '../../providers/auth_provider.dart';
import '../../screens/tag_page_screen.dart';
import '../../services/interest_tag_service.dart';
import '../../services/my_tags_store.dart';
import '../sheets/tag_preview_sheet.dart' show TagFaces;
import '../snackbar/app_snackbar.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'tag_palette.dart';
import 'wf_colors.dart';

/// 공통 태그 시트(마이페이지 블록·둘러보기 줄·프로필 태그).
/// 이모지 타일 + #이름 + 'n명이 달았어요 · 이번 주 +n명' / 설명 / 친구 얼굴
/// / [태그 페이지] [내 태그에 추가 | 내 태그에서 빼기].
Future<void> showTagDetailSheet(BuildContext context, {required String tagId}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    barrierColor: WfColors.dim,
    elevation: 0,
    showDragHandle: true,
    isScrollControlled: true,
    sheetAnimationStyle: AnimationStyle(
      duration: MotionTokens.of(context, const Duration(milliseconds: 300)),
      curve: Curves.easeOutCubic,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(WfRadius.sheet)),
    ),
    builder: (_) => TagDetailSheet(tagId: tagId),
  );
}

/// 태그를 뺐을 때 4초간 '되돌리기'. 시트·블록이 같이 쓴다.
Future<void> removeTagWithUndo(BuildContext context, String tagId) async {
  final l10n = AppLocalizations.of(context)!;
  final auth = context.read<AuthProvider>();
  final messenger = ScaffoldMessenger.maybeOf(context);
  final index = MyTagsStore.instance
      .resolve(MyTagsStore.serverTags(auth))
      .indexOf(tagId);
  try {
    await MyTagsStore.instance.remove(auth, tagId);
  } catch (_) {
    if (context.mounted) {
      AppSnackBar.show(context,
          message: l10n.tagRetryLater, type: AppSnackBarType.error);
    }
    return;
  }
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(l10n.tagRemovedFromMine),
    duration: const Duration(seconds: 4),
    behavior: SnackBarBehavior.floating,
    action: SnackBarAction(
      label: l10n.tagUndo,
      onPressed: () {
        MyTagsStore.instance.restore(auth, tagId, index).catchError((_) {});
      },
    ),
  ));
}

class TagDetailSheet extends StatefulWidget {
  const TagDetailSheet({super.key, required this.tagId});

  final String tagId;

  @override
  State<TagDetailSheet> createState() => _TagDetailSheetState();
}

class _TagDetailSheetState extends State<TagDetailSheet> {
  TagSummary? _summary;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    InterestTagService.instance.summary(widget.tagId).then((summary) {
      if (mounted) setState(() => _summary = summary);
    }, onError: (_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      final gain = await MyTagsStore.instance
          .add(context.read<AuthProvider>(), widget.tagId);
      if (mounted) {
        AppSnackBar.show(context,
            message: gain > 0 ? l10n.tagOverlapGain(gain) : l10n.tagAddedToMine,
            type: AppSnackBarType.success);
      }
    } on TagLimitException {
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagLimitReached, type: AppSnackBarType.warning);
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagRetryLater, type: AppSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPage() {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => TagPageScreen(tagId: widget.tagId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final language = Localizations.localeOf(context).languageCode;
    final summary = _summary;
    final InterestTag? tag =
        summary?.tag ?? InterestTagService.instance.cached(widget.tagId);
    final name = tag?.labelFor(language) ??
        InterestTagService.instance.labelFor(widget.tagId, language);
    final colors = TagChipColors.of(tag, widget.tagId);
    final emoji = TagChipColors.emojiOf(tag, widget.tagId);
    final description = tag?.descriptionFor(language) ?? '';
    final friendNames = (summary?.friends ?? const <TagPerson>[])
        .map((person) => person.nickname)
        .where((name) => name.isNotEmpty)
        .take(2)
        .join(', ');
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: MyTagsBuilder(builder: (context, mine) {
            final isMine = mine.contains(widget.tagId);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colors.light,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(emoji.isEmpty ? '#' : emoji,
                          style: TextStyle(
                              fontSize: emoji.isEmpty ? 24 : 28,
                              fontWeight: FontWeight.w800,
                              color: colors.dark,
                              height: 1)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('#$name',
                              key: const ValueKey('tag_detail_name'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tagTextStyle(
                                  context, 22, FontWeight.w800, WfColors.ink)),
                          const SizedBox(height: 4),
                          Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                  text: _failed
                                      ? l10n.tagLoadFailed
                                      : tag == null
                                          ? ' '
                                          : l10n.tagHolders(tag.holderCount)),
                              if ((summary?.weeklyGain ?? 0) > 0) ...[
                                const TextSpan(text: ' · '),
                                TextSpan(
                                  text: l10n.tagWeeklyGain(summary!.weeklyGain),
                                  style: const TextStyle(
                                      color: WfColors.success,
                                      fontWeight: FontWeight.w700),
                                ),
                              ],
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tagTextStyle(
                                context, 13, FontWeight.w500, WfColors.ink3),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text(description,
                      key: const ValueKey('tag_detail_description'),
                      style: tagTextStyle(
                          context, 15, FontWeight.w500, WfColors.ink2)),
                ],
                if (summary != null && summary.friends.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      TagFaces(people: summary.friends, size: 24, max: 3),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            friendNames.isEmpty
                                ? l10n.tagFriendsAlso(summary.friendCount)
                                : l10n.tagFriendsAlsoNamed(friendNames),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tagTextStyle(
                                context, 13, FontWeight.w600, WfColors.ink2)),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: WfFlatButton(
                        key: const ValueKey('tag_detail_page'),
                        label: l10n.tagPageLink,
                        background: WfColors.surface,
                        pressedBackground: WfColors.surface2,
                        foreground: WfColors.ink,
                        onPressed: _failed ? null : _openPage,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: isMine
                          ? WfFlatButton(
                              key: const ValueKey('tag_detail_remove'),
                              label: l10n.tagRemoveFromMine,
                              background: WfColors.removeBg,
                              pressedBackground: WfColors.surface2,
                              foreground: WfColors.removeText,
                              onPressed: () {
                                Navigator.of(context).pop();
                                removeTagWithUndo(context, widget.tagId);
                              },
                            )
                          : WfFlatButton(
                              key: const ValueKey('tag_detail_add'),
                              label: l10n.tagAddToMinePlain,
                              background: WfColors.brand,
                              pressedBackground: WfColors.brandPressed,
                              foreground: Colors.white,
                              onPressed: _busy ? null : _add,
                            ),
                    ),
                  ],
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}

/// v4 평면 버튼: 그림자·두께·그라데이션 없이 단색. 눌리면 한 단계 진해지고 0.98.
class WfFlatButton extends StatefulWidget {
  const WfFlatButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.background,
    required this.pressedBackground,
    required this.foreground,
    this.height = 44,
    this.radius = WfRadius.button,
    this.fontSize = 15,
    this.leading,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color background;
  final Color pressedBackground;
  final Color foreground;
  final double height;
  final double radius;
  final double fontSize;

  /// 글자 앞(아이콘·얼굴). 간격 7.
  final Widget? leading;

  @override
  State<WfFlatButton> createState() => _WfFlatButtonState();
}

class _WfFlatButtonState extends State<WfFlatButton> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final duration = MotionTokens.of(context, MotionTokens.pressShort);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _set(true) : null,
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? .98 : 1,
          duration: duration,
          curve: MotionTokens.pressSnappy,
          child: AnimatedContainer(
            duration: duration,
            curve: MotionTokens.pressSnappy,
            constraints: BoxConstraints(minHeight: widget.height),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: !enabled
                  ? widget.background.withValues(alpha: .5)
                  : _pressed
                      ? widget.pressedBackground
                      : widget.background,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 7),
                  ],
                  Text(widget.label,
                      maxLines: 1,
                      style: tagTextStyle(context, widget.fontSize,
                          FontWeight.w700, widget.foreground)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
