import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/social_profile_data.dart';
import '../providers/auth_provider.dart';
import '../services/interest_tag_service.dart';
import '../ui/sheets/tag_preview_sheet.dart' show TagFaces;
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/tag_chips.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/country_flag_helper.dart';
import '../utils/motion_haptics.dart';
import '../widgets/country_flag_circle.dart';
import 'friend_profile_screen.dart';
import 'create_meetup_screen.dart';
import 'create_post_screen.dart';
import 'tag_content_tabs.dart';

/// 내 프로필 태그를 하나 더하거나 뺀다. 저장 뒤 프로필을 다시 읽는다.
Future<List<String>> updateMyTags(
  BuildContext context, {
  String? add,
  String? remove,
}) async {
  final auth = context.read<AuthProvider>();
  final current = SocialProfileData.fromMap(auth.userData).interestTagIds;
  final next = [
    for (final id in current)
      if (id != remove) id,
    if (add != null && !current.contains(add)) add,
  ];
  if (next.length > InterestTagService.maxProfileTags) {
    throw const TagLimitException();
  }
  final saved = await InterestTagService.instance.setProfileTags(next);
  await auth.refreshUser();
  return saved;
}

class TagLimitException implements Exception {
  const TagLimitException();
}

/// 태그 페이지: 태그 정보, 내 태그 추가·알림, 태그를 단 사람(친구 먼저).
class TagPageScreen extends StatefulWidget {
  const TagPageScreen({super.key, required this.tagId});

  final String tagId;

  @override
  State<TagPageScreen> createState() => _TagPageScreenState();
}

class _TagPageScreenState extends State<TagPageScreen> {
  final _service = InterestTagService.instance;

  TagSummary? _summary;
  Object? _error;
  bool _busyMine = false;

  final _people = <TagPerson>[];
  String? _cursor;
  bool _loadingPeople = false;
  bool _peopleDone = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final summary = await _service.summary(widget.tagId);
      if (!mounted) return;
      setState(() => _summary = summary);
      _loadPeople();
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _loadPeople() async {
    if (_loadingPeople || _peopleDone) return;
    setState(() => _loadingPeople = true);
    try {
      final page = await _service.holders(widget.tagId, cursor: _cursor);
      if (!mounted) return;
      final friendIds = {
        for (final f in _summary?.friends ?? const <TagPerson>[]) f.uid
      };
      setState(() {
        _people.addAll(page.people.where((p) => !friendIds.contains(p.uid)));
        _cursor = page.cursor;
        _peopleDone = page.cursor == null;
        _loadingPeople = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPeople = false);
    }
  }

  Future<void> _toggleMine() async {
    final summary = _summary;
    if (summary == null || _busyMine) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busyMine = true);
    try {
      await updateMyTags(context,
          add: summary.mine ? null : widget.tagId,
          remove: summary.mine ? widget.tagId : null);
      if (!mounted) return;
      final mine = !summary.mine;
      final count = summary.tag.holderCount + (mine ? 1 : -1);
      setState(() => _summary = summary.copyWith(
            mine: mine,
            tag: summary.tag.copyWith(holderCount: count < 0 ? 0 : count),
          ));
      MotionHaptics.fire(context, MotionHapticEvent.success);
      AppSnackBar.show(context,
          message: mine ? l10n.tagAddedToMine : l10n.tagRemovedFromMine,
          type: AppSnackBarType.success);
    } on TagLimitException {
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagLimitReached, type: AppSnackBarType.warning);
      }
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(context,
            message: l10n.tagSaveFailed, type: AppSnackBarType.error);
      }
    } finally {
      if (mounted) setState(() => _busyMine = false);
    }
  }

  Future<void> _toggleNotify() async {
    final summary = _summary;
    if (summary == null) return;
    final l10n = AppLocalizations.of(context)!;
    final next = !summary.notify;
    setState(() => _summary = summary.copyWith(notify: next));
    try {
      await _service.setPrefs(widget.tagId, notify: next);
      if (!mounted) return;
      MotionHaptics.fire(context, MotionHapticEvent.selection);
      AppSnackBar.show(context,
          message: next ? l10n.tagNotifyOn : l10n.tagNotifyOff);
    } catch (_) {
      if (!mounted) return;
      setState(() => _summary = summary);
      AppSnackBar.show(context,
          message: l10n.tagSaveFailed, type: AppSnackBarType.error);
    }
  }

  void _openPerson(TagPerson person) {
    Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => FriendProfileScreen(
        userId: person.uid,
        nickname: person.nickname,
        photoURL: person.photoURL,
        university: person.university,
        allowNonFriendsPreview: true,
      ),
    ));
  }

  void _openShareSheet(String label) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShareRow(
                key: const ValueKey('tag_share_post'),
                icon: Icons.edit_rounded,
                label: l10n.tagShareWritePost,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push<void>(MaterialPageRoute(
                    builder: (_) => CreatePostScreen(
                      onPostCreated: () {},
                      initialTagIds: [widget.tagId],
                    ),
                  ));
                },
              ),
              _ShareRow(
                key: const ValueKey('tag_share_meetup'),
                icon: Icons.groups_rounded,
                label: l10n.tagShareCreateMeetup,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  Navigator.of(context).push<void>(MaterialPageRoute(
                    builder: (_) => CreateMeetupScreen(
                      initialDayIndex: 0,
                      onCreateMeetup: (_, __) {},
                      initialTagIds: [widget.tagId],
                    ),
                  ));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final summary = _summary;
    return MediaQuery(
      data: media.copyWith(
          textScaler: media.textScaler.clamp(maxScaleFactor: 1.3)),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          leading: const BackButton(color: TagColors.ink),
        ),
        floatingActionButton: summary == null
            ? null
            : FloatingActionButton.extended(
                key: const ValueKey('tag_page_share'),
                backgroundColor: TagColors.blue,
                foregroundColor: Colors.white,
                onPressed: () => _openShareSheet(summary.tag
                    .labelFor(Localizations.localeOf(context).languageCode)),
                label: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: media.size.width - 120),
                  child: Text(
                    l10n.tagShareTo(summary.tag.labelFor(
                        Localizations.localeOf(context).languageCode)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tagTextStyle(
                        context, 15, FontWeight.w700, Colors.white),
                  ),
                ),
              ),
        body: _error != null
            ? _ErrorState(onRetry: _load)
            : summary == null
                ? const Center(
                    child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : DefaultTabController(
                    length: 3,
                    child: NestedScrollView(
                      headerSliverBuilder: (context, _) => [
                        SliverToBoxAdapter(child: _header(l10n, summary)),
                        SliverPersistentHeader(
                          pinned: true,
                          delegate: _TabBarDelegate(TabBar(
                            key: const ValueKey('tag_page_tabs'),
                            labelColor: TagColors.ink,
                            unselectedLabelColor: TagColors.muted,
                            indicatorColor: TagColors.ink,
                            indicatorWeight: 2,
                            indicatorSize: TabBarIndicatorSize.label,
                            dividerColor: const Color(0xFFF0F1F3),
                            labelStyle: tagTextStyle(
                                context, 15, FontWeight.w700, TagColors.ink),
                            unselectedLabelStyle: tagTextStyle(
                                context, 15, FontWeight.w600, TagColors.muted),
                            tabs: [
                              Tab(
                                  text: l10n
                                      .tagPeopleTab(summary.tag.holderCount)),
                              Tab(
                                  text:
                                      l10n.tagPostsTab(summary.tag.postCount)),
                              Tab(
                                  text: l10n
                                      .tagMeetupsTab(summary.tag.meetupCount)),
                            ],
                          )),
                        ),
                      ],
                      body: TabBarView(
                        children: [
                          _peopleTab(l10n, summary),
                          TagPostsTab(tagId: widget.tagId),
                          TagMeetupsTab(tagId: widget.tagId),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _peopleTab(AppLocalizations l10n, TagSummary summary) {
    final friends = summary.friends;
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 400) _loadPeople();
        return false;
      },
      child: CustomScrollView(
        key: const PageStorageKey('tag_people'),
        slivers: [
          if (friends.isNotEmpty) ...[
            _sectionLabel(l10n.tagFriendsSection),
            SliverList.builder(
              itemCount: friends.length,
              itemBuilder: (_, i) => _PersonRow(
                  person: friends[i], onTap: () => _openPerson(friends[i])),
            ),
            if (_people.isNotEmpty) _sectionLabel(l10n.tagOthersSection),
          ],
          SliverList.builder(
            itemCount: _people.length,
            itemBuilder: (_, i) => _PersonRow(
                person: _people[i], onTap: () => _openPerson(_people[i])),
          ),
          SliverToBoxAdapter(
            child: _loadingPeople
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))))
                : (friends.isEmpty && _people.isEmpty && _peopleDone)
                    ? _EmptyText(l10n.tagPeopleEmpty)
                    : const SizedBox(height: 96),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 2),
          child: Text(text,
              style:
                  tagTextStyle(context, 13, FontWeight.w600, TagColors.muted)),
        ),
      );

  Widget _header(AppLocalizations l10n, TagSummary summary) {
    final tag = summary.tag;
    final language = Localizations.localeOf(context).languageCode;
    final subtitle = [
      if (tag.official) l10n.tagOfficial,
      ...summary.aliases.where((a) => a != tag.labelFor(language)).take(3),
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TagHashTile(size: 72, radius: 24),
          const SizedBox(height: 14),
          Text(tag.labelFor(language),
              key: const ValueKey('tag_page_name'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: tagTextStyle(context, 24, FontWeight.w800, TagColors.ink)),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tagTextStyle(
                    context, 13, FontWeight.w500, TagColors.muted)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (summary.friends.isNotEmpty) ...[
                TagFaces(people: summary.friends, size: 26, max: 3),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  summary.friendCount > 0
                      ? l10n.tagHoldersWithFriends(
                          tag.holderCount, summary.friendCount)
                      : l10n.tagHolders(tag.holderCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      tagTextStyle(context, 13, FontWeight.w600, TagColors.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: summary.mine
                    ? TagSecondaryButton(
                        key: const ValueKey('tag_page_mine'),
                        label: l10n.tagInMine,
                        background: TagColors.blueSoft,
                        foreground: TagColors.blue,
                        onPressed: _busyMine ? null : _toggleMine,
                      )
                    : TagPrimaryButton(
                        key: const ValueKey('tag_page_add'),
                        label: l10n.tagAddToMine,
                        busy: _busyMine,
                        onPressed: _toggleMine,
                      ),
              ),
              const SizedBox(width: 8),
              Semantics(
                button: true,
                toggled: summary.notify,
                label: l10n.tagNotifyLabel,
                child: SizedBox.square(
                  dimension: 48,
                  child: IconButton(
                    key: const ValueKey('tag_page_bell'),
                    onPressed: _toggleNotify,
                    style: IconButton.styleFrom(
                      backgroundColor: summary.notify
                          ? TagColors.blueSoft
                          : TagColors.secondary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(
                      summary.notify
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: summary.notify ? TagColors.blue : TagColors.ink,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, required this.onTap});

  final TagPerson person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final language = Localizations.localeOf(context).languageCode;
    final country = person.nationality.isEmpty
        ? ''
        : CountryFlagHelper.getCountryInfo(person.nationality)
                ?.getLocalizedName(language) ??
            person.nationality;
    final supporting = [
      if (country.isNotEmpty) country,
      if (person.university.isNotEmpty) person.university,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          children: [
            UserAvatar(
              uid: person.uid,
              photoUrl: person.photoURL,
              photoVersion: 0,
              isAnonymous: false,
              size: 44,
              placeholderColor: const Color(0xFFF2F4F7),
              placeholderIcon: Icons.person_outline_rounded,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(person.nickname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tagTextStyle(
                          context, 15, FontWeight.w700, TagColors.ink)),
                  if (supporting.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (person.nationality.isNotEmpty) ...[
                          CountryFlagCircle(
                              nationality: person.nationality, size: 15),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(supporting,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tagTextStyle(context, 13, FontWeight.w500,
                                  TagColors.muted)),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: TagColors.disabledText),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.tagLoadFailed,
              style:
                  tagTextStyle(context, 15, FontWeight.w600, TagColors.muted)),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.tabBar);

  final TabBar tabBar;

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      ColoredBox(color: Colors.white, child: tabBar);

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      oldDelegate.tabBar != tabBar;
}

class _ShareRow extends StatelessWidget {
  const _ShareRow(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                  color: Color(0xFFF1F3F5), shape: BoxShape.circle),
              child: Icon(icon, size: 20, color: TagColors.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label,
                  style: tagTextStyle(
                      context, 15, FontWeight.w700, TagColors.ink)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Text(text,
            textAlign: TextAlign.center,
            style: tagTextStyle(context, 13, FontWeight.w500, TagColors.muted)),
      );
}
