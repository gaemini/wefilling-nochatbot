import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/meetup.dart';
import '../models/post.dart';
import '../services/meetup_service.dart';
import '../services/post_service.dart';
import 'post_detail_screen.dart';
import '../ui/widgets/board_meetup_card.dart';
import '../ui/widgets/optimized_post_card.dart';
import '../ui/widgets/tag_chips.dart';
import 'meetup_detail_screen.dart';

/// 태그 페이지 포스트 한 페이지. cursor가 null이면 끝.
typedef TagPostPage = ({List<Post> posts, Object? cursor});

/// 태그 페이지의 글·모임을 불러오는 곳. 테스트에서 바꿔 끼운다.
class TagContentSource {
  const TagContentSource();

  static TagContentSource instance = const TagContentSource();

  Future<TagPostPage> posts(String tagId, {Object? cursor}) async {
    final page = await PostService().fetchPublicTagPosts(
      tagId,
      after: cursor as DocumentSnapshot<Map<String, dynamic>>?,
    );
    return (posts: page.posts, cursor: page.cursor);
  }

  Future<List<Meetup>> meetups(String tagId) =>
      MeetupService().fetchPublicTagMeetups(tagId);
}

class TagPostsTab extends StatefulWidget {
  const TagPostsTab({super.key, required this.tagId});

  final String tagId;

  @override
  State<TagPostsTab> createState() => _TagPostsTabState();
}

class _TagPostsTabState extends State<TagPostsTab>
    with AutomaticKeepAliveClientMixin {
  final _posts = <Post>[];
  Object? _cursor;
  bool _loading = false;
  bool _done = false;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _done) return;
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page =
          await TagContentSource.instance.posts(widget.tagId, cursor: _cursor);
      if (!mounted) return;
      setState(() {
        final seen = _posts.map((post) => post.id).toSet();
        _posts.addAll(page.posts.where((post) => seen.add(post.id)));
        _cursor = page.cursor;
        _done = page.cursor == null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _open(Post post, {PostDetailFocus focus = PostDetailFocus.post}) {
    Navigator.of(context)
        .push<bool>(PostDetailMotionRoute(post: post, initialFocus: focus))
        .then((deleted) {
      if (deleted == true && mounted) {
        setState(() => _posts.removeWhere((item) => item.id == post.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 600) _loadMore();
        return false;
      },
      child: CustomScrollView(
        key: const PageStorageKey('tag_posts'),
        slivers: [
          SliverList.builder(
            itemCount: _posts.length,
            itemBuilder: (_, index) => OptimizedPostCard(
              key: ValueKey('tag_post_${_posts[index].id}'),
              post: _posts[index],
              index: index,
              onTap: () => _open(_posts[index]),
              onCommentTap: () =>
                  _open(_posts[index], focus: PostDetailFocus.comments),
            ),
          ),
          SliverToBoxAdapter(
            child: _TabFooter(
              loading: _loading,
              failed: _failed,
              empty: _done && _posts.isEmpty,
              emptyText: l10n.tagPostsEmpty,
              onRetry: _loadMore,
            ),
          ),
        ],
      ),
    );
  }
}

class TagMeetupsTab extends StatefulWidget {
  const TagMeetupsTab({super.key, required this.tagId});

  final String tagId;

  @override
  State<TagMeetupsTab> createState() => _TagMeetupsTabState();
}

class _TagMeetupsTabState extends State<TagMeetupsTab>
    with AutomaticKeepAliveClientMixin {
  List<Meetup>? _meetups;
  bool _failed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _meetups = null;
    });
    try {
      final meetups = await TagContentSource.instance.meetups(widget.tagId);
      if (mounted) setState(() => _meetups = meetups);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _open(Meetup meetup) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => MeetupDetailScreen(
        meetup: meetup,
        meetupId: meetup.id,
        onMeetupDeleted: () {
          if (mounted) {
            setState(() => _meetups?.removeWhere((m) => m.id == meetup.id));
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final meetups = _meetups ?? const <Meetup>[];
    return CustomScrollView(
      key: const PageStorageKey('tag_meetups'),
      slivers: [
        SliverList.builder(
          itemCount: meetups.length,
          itemBuilder: (_, index) => BoardMeetupCard(
            key: ValueKey('tag_meetup_${meetups[index].id}'),
            meetup: meetups[index],
            onTap: () => _open(meetups[index]),
          ),
        ),
        SliverToBoxAdapter(
          child: _TabFooter(
            loading: _meetups == null && !_failed,
            failed: _failed,
            empty: _meetups != null && meetups.isEmpty,
            emptyText: l10n.tagMeetupsEmpty,
            onRetry: _load,
          ),
        ),
      ],
    );
  }
}

class _TabFooter extends StatelessWidget {
  const _TabFooter({
    required this.loading,
    required this.failed,
    required this.empty,
    required this.emptyText,
    required this.onRetry,
  });

  final bool loading;
  final bool failed;
  final bool empty;
  final String emptyText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox.square(
              dimension: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (failed) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(l10n.tagLoadFailed,
                style: tagTextStyle(
                    context, 13, FontWeight.w500, TagColors.muted)),
            TextButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      );
    }
    if (empty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(32, 32, 32, 96),
        child: Text(emptyText,
            textAlign: TextAlign.center,
            style: tagTextStyle(context, 13, FontWeight.w500, TagColors.muted)),
      );
    }
    return const SizedBox(height: 96);
  }
}
