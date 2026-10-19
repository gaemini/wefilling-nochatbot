import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/interest_overview.dart';
import '../../providers/auth_provider.dart';
import '../../providers/relationship_provider.dart';
import '../../screens/friend_profile_screen.dart';
import '../../screens/profile_edit_screen.dart';
import '../../screens/tag_explore_screen.dart';
import '../../services/cache/my_page_cache_service.dart';
import '../../services/interest_tag_service.dart';
import '../../services/my_tags_store.dart';
import '../snackbar/app_snackbar.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'interest_bento.dart';
import 'first_run_interest.dart';
import 'interest_block_tile.dart';
import 'friend_request_button.dart';
import 'overlap_people_screen.dart';
import 'overlap_people_section.dart';
import 'stat_lens_tiles.dart';
import 'tag_detail_sheet.dart';
import 'tag_palette.dart';
import 'wf_colors.dart';

/// 마이페이지 관심 탭(기존 사용자): 숫자 카드 3개(보기 전환) → 관심 지도 → 나와 겹치는 사람.
/// 요약은 캐시를 먼저 보여 주고 10분이 지났을 때만 다시 묻는다.
class InterestTab extends StatefulWidget {
  const InterestTab({
    super.key,
    required this.uid,
    this.onOverview,
    this.cache,
  });

  /// 테스트에서 디스크 캐시 대신.
  final MyPageCacheService? cache;

  /// 내 uid(캐시 키). 바뀌면 다시 읽는다.
  final String? uid;

  /// 요약을 받으면(캐시 포함) 부른다. 마이페이지 친구 버튼 얼굴에 쓴다.
  final ValueChanged<InterestOverview>? onOverview;

  @override
  State<InterestTab> createState() => InterestTabState();
}

class InterestTabState extends State<InterestTab> {
  final _service = InterestTagService.instance;
  late final MyPageCacheService _cache = widget.cache ?? MyPageCacheService();
  InterestLens _lens = InterestLens.me;
  InterestOverview? _overview;
  bool _failed = false;
  String? _uid;
  final _people = <String, List<OverlapPerson>>{};
  final _peopleTotal = <String, int>{};
  final _peopleCursor = <String, String?>{};
  final _loadingMore = <String>{};
  bool _interacted = false;
  Timer? _peopleRefresh;

  @override
  void dispose() {
    _peopleRefresh?.cancel();
    super.dispose();
  }

  /// 처음 사용자 화면에서 '완료'를 누른 뒤에는 태그가 3개 미만이어도 이 화면.
  bool _firstRunDone = false;

  /// 처음 사용자 화면이 저장하는 동안(낙관적으로 3개가 되어도 화면을 유지).
  bool _firstRunSaving = false;

  static String scopeOf(InterestLens lens) => switch (lens) {
        InterestLens.me => 'all',
        InterestLens.friends => 'friends',
        InterestLens.community => 'others',
      };

  @override
  void initState() {
    super.initState();
    _syncUid();
  }

  @override
  void didUpdateWidget(InterestTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) _syncUid();
  }

  void _syncUid() {
    final uid = widget.uid;
    if (uid == null || uid == _uid) return;
    _uid = uid;
    _overview = null;
    _people.clear();
    unawaited(_load());
  }

  Future<void> _load({bool force = false}) async {
    final uid = _uid;
    if (uid == null) return;
    if (!force) {
      final cached = await _cache.readInterest(uid, 'overview');
      if (!mounted || uid != _uid) return;
      if (cached != null) {
        _setOverview(_service.restoreOverview(cached.data));
      }
      unawaited(_loadPeople(_lens));
      if (cached?.isFresh == true) return;
    }
    try {
      final overview = await _service.myInterestOverview();
      if (!mounted || uid != _uid) return;
      _setOverview(overview);
      unawaited(_cache.saveInterest(uid, 'overview', overview.raw));
    } catch (_) {
      if (mounted && _overview == null) setState(() => _failed = true);
    }
  }

  void _setOverview(InterestOverview overview) {
    setState(() {
      _overview = overview;
      _failed = false;
    });
    widget.onOverview?.call(overview);
  }

  Future<void> _loadPeople(InterestLens lens, {bool force = false}) async {
    final uid = _uid;
    if (uid == null) return;
    final scope = scopeOf(lens);
    if (!force) {
      final cached = await _cache.readInterest(uid, 'people_$scope');
      if (!mounted || uid != _uid) return;
      if (cached != null) {
        setState(() {
          _people[scope] = [
            for (final item in cached.data['people'] as List? ?? const [])
              if (item is Map) OverlapPerson.fromMap(item),
          ];
          _peopleTotal[scope] = (cached.data['total'] as num?)?.toInt() ?? 0;
        });
        if (cached.isFresh) return;
      }
    }
    try {
      final result = await _service.overlapPeople(scope);
      if (!mounted || uid != _uid) return;
      setState(() {
        _people[scope] = result.people;
        _peopleTotal[scope] = result.total;
        _peopleCursor[scope] = result.cursor;
      });
      unawaited(_cache.saveInterest(uid, 'people_$scope', {
        'people': [for (final person in result.people) person.toMap()],
        'total': result.total,
      }));
    } catch (_) {
      if (mounted) setState(() => _people.putIfAbsent(scope, () => const []));
    }
  }

  /// 레일 끝에서 3장 전: 다음 20명.
  Future<void> _loadMorePeople() async {
    final scope = scopeOf(_lens);
    final cursor = _peopleCursor[scope];
    if (cursor == null || !_loadingMore.add(scope)) return;
    try {
      final result = await _service.overlapPeople(scope, cursor: cursor);
      if (!mounted) return;
      setState(() {
        final seen = {
          for (final p in _people[scope] ?? const <OverlapPerson>[]) p.uid
        };
        _people[scope] = [
          ...?_people[scope],
          for (final person in result.people)
            if (!seen.contains(person.uid)) person,
        ];
        _peopleCursor[scope] = result.cursor;
      });
    } catch (_) {
      // 다음에 다시 끝에 오면 묻는다.
    } finally {
      _loadingMore.remove(scope);
    }
  }

  void _selectLens(InterestLens lens) {
    setState(() => _lens = lens);
    if (!_people.containsKey(scopeOf(lens))) unawaited(_loadPeople(lens));
  }

  /// ＋: 바로 내 태그로(낙관적). 새로 겹치게 된 사람 수, 실패·제한이면 null.
  Future<int?> _add(String tagId) async {
    final l10n = AppLocalizations.of(context)!;
    final auth = context.read<AuthProvider>();
    try {
      final gain = await MyTagsStore.instance.add(auth, tagId);
      HapticFeedback.lightImpact();
      // 사람 카드의 원형 그래프와 숫자가 새 값으로 차오른다. 여러 번 연달아
      // 눌러도 마지막에 한 번만 묻는다(요약은 다시 묻지 않는다: 내 태그는 바로 반영됨).
      _peopleRefresh?.cancel();
      _peopleRefresh = Timer(const Duration(milliseconds: 1500),
          () => unawaited(_loadPeople(_lens, force: true)));
      return gain;
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
    }
    return null;
  }

  void _openProfile(OverlapPerson person) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => FriendProfileScreen(
        userId: person.uid,
        nickname: person.name,
        photoURL: person.photoURL,
        university: person.school,
        allowNonFriendsPreview: !person.isFriend,
      ),
    ));
  }

  void _openExplore() => Navigator.of(context)
      .push<void>(MaterialPageRoute(builder: (_) => const TagExploreScreen()));

  List<InterestBlockData> _blocks(
      AppLocalizations l10n, InterestOverview o, List<String> mine) {
    final language = Localizations.localeOf(context).languageCode;
    final friendHolders = {for (final (id, n) in o.friendTags) id: n};
    InterestBlockData block(String id, String metric, {int gain = 0}) {
      final tag = _service.cached(id) ?? o.tags[id];
      final faces = o.tagFaces[id] ?? const <String>[];
      return InterestBlockData(
        tagId: id,
        label: tag?.labelFor(language) ?? _service.labelFor(id, language),
        emoji: TagChipColors.emojiOf(tag, id),
        category: TagChipColors.categoryOf(tag, id),
        metric: metric,
        gain: gain,
        faces: faces,
        moreFaces: ((friendHolders[id] ?? 0) - faces.length).clamp(0, 999),
      );
    }

    switch (_lens) {
      case InterestLens.me:
        final posts = {for (final (id, n) in o.myTags) id: n};
        final ordered = [...mine]
          ..sort((a, b) => (posts[b] ?? 0).compareTo(posts[a] ?? 0));
        return [
          for (final id in ordered) block(id, l10n.blockPosts(posts[id] ?? 0)),
          for (final (id, _) in o.suggestions
              .where((s) => !mine.contains(s.$1))
              .take((8 - ordered.length).clamp(0, 2)))
            block(id, l10n.blockSuggest),
        ];
      case InterestLens.friends:
        return [
          for (final (id, n) in o.friendTags.take(8))
            block(id, l10n.blockFriends(n)),
        ];
      case InterestLens.community:
        return [
          for (final (id, holders, gain) in o.communityTags.take(8))
            block(id, l10n.tagCountPeople(holders), gain: gain),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // select는 build에서만(빌더 콜백 안에서 부르면 오류).
    final outgoing = context.select<RelationshipProvider, Set<String>>(
        (r) => r.outgoingRequests.map((request) => request.toUid).toSet());
    final incoming = context.select<RelationshipProvider, Set<String>>(
        (r) => r.incomingRequests.map((request) => request.fromUid).toSet());
    final hasPhoto = context.select<AuthProvider, bool>((auth) =>
        (auth.userData?['photoURL'] ?? '').toString().startsWith('https://'));
    final hasBio = context.select<AuthProvider, bool>(
        (auth) => (auth.userData?['bio'] ?? '').toString().trim().isNotEmpty);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: MyTagsBuilder(builder: (context, mine) {
        final overview = _overview;
        if (overview == null) {
          return Center(
            child: _failed
                ? TextButton(
                    onPressed: () {
                      setState(() => _failed = false);
                      unawaited(_load(force: true));
                    },
                    child: Text(l10n.interestLoadFailed),
                  )
                : const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        // 처음 사용자(내 태그 3개 미만): 완성도 카드 + 키캡으로 3개 고르기.
        if ((mine.length < 3 || _firstRunSaving) && !_firstRunDone) {
          return ListenableBuilder(
            listenable: _service,
            builder: (context, _) => FirstRunInterest(
              overview: overview,
              mine: mine,
              hasPhoto: hasPhoto,
              hasBio: hasBio,
              onEditProfile: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const ProfileEditScreen())),
              onSaving: (saving) {
                if (mounted) setState(() => _firstRunSaving = saving);
              },
              onDone: () {
                setState(() {
                  _firstRunDone = true;
                  _firstRunSaving = false;
                });
                unawaited(_loadPeople(_lens, force: true));
              },
            ),
          );
        }
        return ListenableBuilder(
          listenable: _service,
          builder: (context, _) =>
              _content(l10n, overview, mine, outgoing, incoming),
        );
      }),
    );
  }

  Widget _content(AppLocalizations l10n, InterestOverview overview,
      List<String> mine, Set<String> outgoing, Set<String> incoming) {
    final blocks = _blocks(l10n, overview, mine);
    final mineSet = mine.toSet();
    final breathe = _interacted
        ? null
        : blocks
            .where((b) => !mineSet.contains(b.tagId))
            .map((b) => b.tagId)
            .firstOrNull;
    final scope = scopeOf(_lens);
    final people = _people[scope];
    final caption = switch (_lens) {
      InterestLens.me => l10n.interestMapCaptionMe(mine.length),
      InterestLens.friends =>
        l10n.interestMapCaptionFriends(overview.friendCount),
      InterestLens.community => l10n.interestMapCaptionCommunity,
    };
    final peopleTitle = switch (_lens) {
      InterestLens.me => l10n.overlapTitleAll,
      InterestLens.friends => l10n.overlapTitleFriends,
      InterestLens.community => l10n.overlapTitleOthers,
    };
    return ListView(
      key: const PageStorageKey('mypage_interest_list'),
      padding: EdgeInsets.only(
          top: 16, bottom: 28 + MediaQuery.viewPaddingOf(context).bottom),
      children: [
        StatLensTiles(
          selected: _lens,
          onSelected: _selectLens,
          items: [
            StatLensItem(InterestLens.me, l10n.lensMe, '${mine.length}',
                l10n.lensMeUnit),
            StatLensItem(InterestLens.friends, l10n.lensFriends,
                '${overview.friendCount}', l10n.lensFriendsUnit),
            StatLensItem(InterestLens.community, l10n.lensCommunity,
                '+${overview.newTagsThisWeek}', l10n.lensCommunityUnit),
          ],
        ),
        const SizedBox(height: 26),
        _SectionTitle(
          title: l10n.interestMapTitle,
          trailing: Semantics(
            button: true,
            label: l10n.tagExploreTitle,
            child: InkResponse(
              key: const ValueKey('interest_map_search'),
              onTap: _openExplore,
              radius: 24,
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: WfColors.surface, shape: BoxShape.circle),
                child: const Icon(Icons.search_rounded,
                    size: 19, color: WfColors.ink),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(caption,
              key: const ValueKey('interest_map_caption'),
              style: tagTextStyle(context, 13, FontWeight.w500, WfColors.ink3)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: KeyedSubtree(
            key: ValueKey('interest_bento_${_lens.name}'),
            child: InterestBento(
              items: blocks,
              mine: mineSet,
              breatheTagId: breathe,
              onInteract: () {
                if (!_interacted) setState(() => _interacted = true);
              },
              onOpen: (id) => showTagDetailSheet(context, tagId: id),
              onAdd: _add,
            ),
          ),
        ),
        OverlapPeopleHeader(
          title: peopleTitle,
          count: _peopleTotal[scope],
          onSeeAll: () => Navigator.of(context).push<void>(
            MaterialPageRoute(
              builder: (_) =>
                  OverlapPeopleScreen(scope: scope, title: peopleTitle),
            ),
          ),
        ),
        if (people == null)
          const SizedBox(
            height: 120,
            child: Center(
              child: SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          )
        else if (people.isEmpty)
          OverlapPeopleEmpty(onPickMore: _openExplore)
        else
          OverlapPeopleRail(
            key: ValueKey('overlap_row_$scope'),
            people: people,
            relationOf: (person) => peopleRelationOf(
              person.uid,
              isFriend: person.isFriend,
              outgoing: outgoing,
              incoming: incoming,
            ),
            onOpenProfile: _openProfile,
            onLoadMore: () => unawaited(_loadMorePeople()),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tagTextStyle(context, 19, FontWeight.w800, WfColors.ink)
                  .copyWith(letterSpacing: -.5),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
