import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/social_profile_data.dart';
import '../../providers/auth_provider.dart';
import '../../screens/tag_explore_screen.dart';
import '../../services/interest_tag_service.dart';
import '../../services/tag_seen_store.dart';
import 'content_tag_row.dart' show openTagPage;
import 'motion_press.dart';
import 'tag_chips.dart';

/// 게시판 '오늘의 포스트' 위: 내 #태그 알약(마지막으로 본 뒤 새 글 수) + '태그 둘러보기 ›'.
class MyTagsNewRow extends StatefulWidget {
  const MyTagsNewRow({super.key, this.horizontalPadding = 16});

  final double horizontalPadding;

  @override
  State<MyTagsNewRow> createState() => _MyTagsNewRowState();
}

class _MyTagsNewRowState extends State<MyTagsNewRow> {
  // 목록을 스크롤하면 이 줄이 다시 만들어진다. 같은 태그면 2분 동안 다시 묻지 않는다.
  static Map<String, int> _cachedCounts = const {};
  static List<String> _cachedTags = const [];
  static DateTime? _cachedAt;

  @visibleForTesting
  static void debugClearCache() {
    _cachedCounts = const {};
    _cachedTags = const [];
    _cachedAt = null;
  }

  Map<String, int> _counts = _cachedCounts;
  List<String> _loadedFor = const [];

  Future<void> _loadCounts(List<String> tags) async {
    _loadedFor = tags;
    if (tags.isEmpty) return;
    final cachedAt = _cachedAt;
    if (cachedAt != null &&
        _sameList(tags, _cachedTags) &&
        DateTime.now().difference(cachedAt) < const Duration(minutes: 2)) {
      setState(() => _counts = _cachedCounts);
      return;
    }
    try {
      final since = await TagSeenStore.seenTimes(tags);
      final counts = await InterestTagService.instance.myNewCounts(since);
      _cachedCounts = counts;
      _cachedTags = tags;
      _cachedAt = DateTime.now();
      if (mounted) setState(() => _counts = counts);
    } catch (_) {
      // 개수 없이도 알약은 누를 수 있다.
    }
  }

  Future<void> _open(String tagId) async {
    openTagPage(context, tagId);
    _cachedCounts = {..._cachedCounts, tagId: 0};
    setState(() => _counts = {..._counts, tagId: 0});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tags = SocialProfileData.fromMap(
      context
          .select<AuthProvider, Map<String, dynamic>?>((auth) => auth.userData),
    ).interestTagIds;
    if (!_sameList(tags, _loadedFor)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadCounts(tags);
      });
    }
    final service = InterestTagService.instance;
    service.ensureLoaded(tags);
    final language = Localizations.localeOf(context).languageCode;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            widget.horizontalPadding, 8, widget.horizontalPadding, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(l10n.myTagsNewPosts,
                      style: tagTextStyle(
                          context, 15, FontWeight.w700, TagColors.ink)),
                ),
                TextButton(
                  key: const ValueKey('board_tag_explore'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const TagExploreScreen()),
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: TagColors.muted,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: const Size(0, 36),
                  ),
                  child: Text(l10n.tagExploreLink,
                      style: tagTextStyle(
                          context, 13, FontWeight.w600, TagColors.muted)),
                ),
              ],
            ),
            if (tags.isNotEmpty)
              SizedBox(
                height: 40,
                child: ListenableBuilder(
                  listenable: service,
                  builder: (context, _) => ListView.separated(
                    key: const PageStorageKey('board_my_tags'),
                    scrollDirection: Axis.horizontal,
                    itemCount: tags.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (context, index) {
                      final id = tags[index];
                      return Center(
                        child: _NewCountPill(
                          key: ValueKey('board_my_tag_$id'),
                          label: '#${service.labelFor(id, language)}',
                          count: _counts[id] ?? 0,
                          onTap: () => _open(id),
                        ),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static bool _sameList(List<String> a, List<String> b) =>
      a.length == b.length &&
      Iterable.generate(a.length).every((i) => a[i] == b[i]);
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
  static void clear() => _MyTagsNewRowState.debugClearCache();
}
