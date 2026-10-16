import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/social_profile_data.dart';
import '../../providers/auth_provider.dart';
import '../../screens/tag_explore_screen.dart';
import '../../screens/tag_picker_screen.dart';
import '../../services/interest_tag_service.dart';
import '../../services/tag_seen_store.dart';
import '../../screens/tag_page_screen.dart';
import 'motion_press.dart';
import 'tag_chips.dart';

/// 내 #태그별 '마지막으로 본 뒤 새 글 수'. 상단 버튼(빨간 점)과 시트가 같이 쓴다.
/// 같은 태그면 2분 동안 서버에 다시 묻지 않는다.
class MyTagsNewCounts extends ChangeNotifier {
  MyTagsNewCounts._();
  static final instance = MyTagsNewCounts._();

  Map<String, int> _counts = const {};
  List<String> _tags = const [];
  DateTime? _at;
  bool _loading = false;

  Map<String, int> get counts => _counts;

  int get total => _tags.fold(0, (sum, id) => sum + (_counts[id] ?? 0));

  @visibleForTesting
  void debugClear() {
    _counts = const {};
    _tags = const [];
    _at = null;
  }

  Future<void> load(List<String> tags) async {
    if (tags.isEmpty) {
      if (_tags.isNotEmpty) {
        _tags = const [];
        _counts = const {};
        notifyListeners();
      }
      return;
    }
    final at = _at;
    if (_loading ||
        (at != null &&
            _same(tags, _tags) &&
            DateTime.now().difference(at) < const Duration(minutes: 2))) {
      return;
    }
    _loading = true;
    try {
      final since = await TagSeenStore.seenTimes(tags);
      _counts = await InterestTagService.instance.myNewCounts(since);
      _tags = tags;
      _at = DateTime.now();
      notifyListeners();
    } catch (_) {
      // 개수 없이도 태그는 열 수 있다.
    } finally {
      _loading = false;
    }
  }

  void markSeen(String tagId) {
    if ((_counts[tagId] ?? 0) == 0) return;
    _counts = {..._counts, tagId: 0};
    notifyListeners();
  }

  static bool _same(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);
}

List<String> _myTags(BuildContext context) => SocialProfileData.fromMap(
      context
          .select<AuthProvider, Map<String, dynamic>?>((auth) => auth.userData),
    ).interestTagIds;

/// 상단 바 '#' 버튼(포스트 탭): 누르면 태그 둘러보기.
class MyTagsHeaderButton extends StatelessWidget {
  const MyTagsHeaderButton({super.key, this.iconSize = 23});

  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return IconButton(
      key: const ValueKey('header_my_tags'),
      tooltip: l10n.tagExploreTitle,
      visualDensity: VisualDensity.compact,
      onPressed: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const TagExploreScreen()),
      ),
      icon: Icon(Icons.tag_rounded, size: iconSize, color: TagColors.ink),
    );
  }
}

/// 내 #태그 알약(새 글 수) + '태그 둘러보기 ›'. 태그가 없으면 안내 + [태그 달기].
/// 태그 둘러보기 화면 맨 위에도 쓴다([showExploreLink] false).
class MyTagsNewRow extends StatefulWidget {
  const MyTagsNewRow({
    super.key,
    this.horizontalPadding = 20,
    this.onNavigate,
    this.showExploreLink = true,
  });

  final double horizontalPadding;

  /// 둘러보기 화면 안에서는 '태그 둘러보기 ›'와 빈 안내를 숨긴다.
  final bool showExploreLink;

  /// 다른 화면으로 가기 직전에 부른다(시트 닫기).
  final VoidCallback? onNavigate;

  @override
  State<MyTagsNewRow> createState() => _MyTagsNewRowState();
}

class _MyTagsNewRowState extends State<MyTagsNewRow> {
  List<String> _loadedFor = const [];

  void _open(String tagId) {
    MyTagsNewCounts.instance.markSeen(tagId);
    _push(TagPageScreen(tagId: tagId));
  }

  void _push(Widget screen) {
    final navigator = Navigator.of(context);
    widget.onNavigate?.call();
    navigator.push<void>(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tags = _myTags(context);
    if (!MyTagsNewCounts._same(tags, _loadedFor)) {
      _loadedFor = tags;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => MyTagsNewCounts.instance.load(tags));
    }
    final service = InterestTagService.instance;
    service.ensureLoaded(tags);
    final language = Localizations.localeOf(context).languageCode;
    if (!widget.showExploreLink && tags.isEmpty) return const SizedBox.shrink();
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            widget.horizontalPadding, 0, widget.horizontalPadding, 4),
        child: ListenableBuilder(
          listenable: Listenable.merge([service, MyTagsNewCounts.instance]),
          builder: (context, _) {
            final counts = MyTagsNewCounts.instance.counts;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(l10n.myTagsNewPosts,
                          style: tagTextStyle(
                              context,
                              widget.showExploreLink ? 17 : 15,
                              FontWeight.w700,
                              TagColors.ink)),
                    ),
                    if (widget.showExploreLink)
                      TextButton(
                        key: const ValueKey('board_tag_explore'),
                        onPressed: () => _push(const TagExploreScreen()),
                        style: TextButton.styleFrom(
                          foregroundColor: TagColors.muted,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          minimumSize: const Size(0, 36),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(l10n.tagExploreLink,
                            style: tagTextStyle(
                                context, 13, FontWeight.w600, TagColors.muted)),
                      ),
                  ],
                ),
                SizedBox(height: widget.showExploreLink ? 10 : 8),
                if (tags.isEmpty) ...[
                  Text(l10n.myTagsEmptyHint,
                      style: tagTextStyle(
                          context, 13, FontWeight.w500, TagColors.muted)),
                  const SizedBox(height: 12),
                  TagPrimaryButton(
                    key: const ValueKey('my_tags_add'),
                    label: l10n.myTagsAddAction,
                    icon: Icons.add_rounded,
                    height: 36,
                    onPressed: () => _push(const TagPickerScreen()),
                  ),
                ] else
                  Wrap(
                    spacing: 6,
                    runSpacing: 8,
                    children: [
                      for (final id in tags)
                        _NewCountPill(
                          key: ValueKey('board_my_tag_$id'),
                          label: '#${service.labelFor(id, language)}',
                          count: counts[id] ?? 0,
                          onTap: () => _open(id),
                        ),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NewCountPill extends StatelessWidget {
  const _NewCountPill({
    super.key,
    required this.label,
    required this.count,
    required this.onTap,
  });

  final String label;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MotionPress(
      child: Material(
        color: TagColors.blueSoft,
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 150),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 13.5, FontWeight.w600, TagColors.blue)),
                ),
                if (count > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    height: 18,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(count > 99 ? '99+' : '$count',
                        style: tagTextStyle(
                            context, 11, FontWeight.w700, Colors.white)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 테스트에서 개수 캐시를 비운다.
@visibleForTesting
abstract final class MyTagsNewRowDebug {
  static void clear() => MyTagsNewCounts.instance.debugClear();
}
