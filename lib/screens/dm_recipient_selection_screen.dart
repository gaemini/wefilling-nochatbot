import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../l10n/app_localizations.dart';
import '../l10n/ui_locale.dart';
import '../models/user_profile.dart';
import '../services/cache/app_image_cache_manager.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/responsive_helper.dart';

typedef DmRecipientSearch = Future<List<UserProfile>> Function(String query);

/// DM 대상 선택에서 친구 아이디를 빠르게 필터링한다.
///
/// 검색 결과의 순서는 최근 친구 순서인 원본 목록을 그대로 유지한다.
@visibleForTesting
List<UserProfile> filterDmRecipientFriends(
  Iterable<UserProfile> friends,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return friends.toList(growable: false);
  return friends
      .where(
        (friend) =>
            friend.displayNameOrNickname.toLowerCase().contains(normalized),
      )
      .toList(growable: false);
}

/// 새 DM을 시작할 사용자를 고르는 전체 화면.
///
/// 친구 목록은 로컬에서 즉시 필터링하고, 전체 사용자 탭은 서버의 기존
/// 사용자 검색 정책(활성 계정·양방향 차단 제외)을 그대로 사용한다.
class DmRecipientSelectionScreen extends StatefulWidget {
  const DmRecipientSelectionScreen({
    super.key,
    required this.friendsStream,
    required this.searchUsers,
    required this.cacheOwnerId,
    this.initialFriends = const <UserProfile>[],
  });

  final Stream<List<UserProfile>> friendsStream;
  final DmRecipientSearch searchUsers;
  final String cacheOwnerId;
  final List<UserProfile> initialFriends;

  @override
  State<DmRecipientSelectionScreen> createState() =>
      _DmRecipientSelectionScreenState();
}

class _DmRecipientSelectionScreenState extends State<DmRecipientSelectionScreen>
    with SingleTickerProviderStateMixin {
  static final Map<String, List<UserProfile>> _sessionFriendCache =
      <String, List<UserProfile>>{};

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  StreamSubscription<List<UserProfile>>? _friendsSubscription;
  Timer? _searchDebounce;

  List<UserProfile> _friends = const <UserProfile>[];
  List<UserProfile> _directoryResults = const <UserProfile>[];
  final Map<String, List<UserProfile>> _directoryCache =
      <String, List<UserProfile>>{};
  String _query = '';
  bool _friendsLoading = true;
  bool _friendsFailed = false;
  bool _directorySearching = false;
  bool _directoryFailed = false;
  bool _directorySearched = false;
  int _searchGeneration = 0;

  bool get _isDirectoryTab => _tabController.index == 1;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this)
      ..addListener(_handleTabChanged);
    _searchController.addListener(_handleQueryChanged);

    final cached = _sessionFriendCache[widget.cacheOwnerId];
    final initial = widget.initialFriends.isNotEmpty
        ? widget.initialFriends
        : (cached ?? const <UserProfile>[]);
    if (initial.isNotEmpty) {
      _friends = List<UserProfile>.unmodifiable(initial);
      _friendsLoading = false;
      _prefetchAvatars(_friends);
    }
    _subscribeToFriends();
  }

  void _subscribeToFriends() {
    _friendsSubscription = widget.friendsStream.listen(
      (friends) {
        if (!mounted) return;
        final safeFriends = List<UserProfile>.unmodifiable(friends);
        _sessionFriendCache[widget.cacheOwnerId] = safeFriends;
        setState(() {
          _friends = safeFriends;
          _friendsLoading = false;
          _friendsFailed = false;
        });
        _prefetchAvatars(safeFriends);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!mounted) return;
        setState(() {
          _friendsLoading = false;
          _friendsFailed = _friends.isEmpty;
        });
      },
    );
  }

  void _prefetchAvatars(Iterable<UserProfile> profiles) {
    unawaited(
      AppImageCacheManager.prefetchUrls(
        profiles
            .where((profile) => profile.hasProfileImage)
            .map((profile) => profile.photoURL!),
        maxItems: 16,
        concurrency: 3,
      ),
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _friendsSubscription?.cancel();
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _searchController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) return;
    _searchDebounce?.cancel();
    _searchGeneration++;
    _searchController.clear();
    if (!mounted) return;
    setState(() {
      _query = '';
      _directoryResults = const <UserProfile>[];
      _directorySearching = false;
      _directoryFailed = false;
      _directorySearched = false;
    });
  }

  void _handleQueryChanged() {
    final nextQuery = _searchController.text.trim();
    if (_query == nextQuery) return;
    _searchDebounce?.cancel();
    _searchGeneration++;
    setState(() {
      _query = nextQuery;
      _directoryResults = const <UserProfile>[];
      _directorySearching = false;
      _directoryFailed = false;
      _directorySearched = false;
    });
    if (_isDirectoryTab && nextQuery.isNotEmpty) {
      _searchDebounce = Timer(
        const Duration(milliseconds: 280),
        () => _searchDirectory(nextQuery),
      );
    }
  }

  Future<void> _searchDirectory(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return;
    _searchDebounce?.cancel();
    final generation = ++_searchGeneration;
    final cached = _directoryCache[normalized];
    if (cached != null) {
      if (!mounted || _query.trim().toLowerCase() != normalized) return;
      setState(() {
        _directoryResults = cached;
        _directorySearching = false;
        _directoryFailed = false;
        _directorySearched = true;
      });
      _prefetchAvatars(cached);
      return;
    }

    setState(() {
      _directorySearching = true;
      _directoryFailed = false;
      _directorySearched = false;
    });
    try {
      final results = await widget.searchUsers(query);
      if (!mounted ||
          generation != _searchGeneration ||
          _query.trim().toLowerCase() != normalized) {
        return;
      }
      final uniqueResults = <String, UserProfile>{
        for (final profile in results) profile.uid: profile,
      }.values.toList(growable: false);
      _directoryCache[normalized] = uniqueResults;
      setState(() {
        _directoryResults = uniqueResults;
        _directorySearching = false;
        _directoryFailed = false;
        _directorySearched = true;
      });
      _prefetchAvatars(uniqueResults);
    } catch (_) {
      if (!mounted ||
          generation != _searchGeneration ||
          _query.trim().toLowerCase() != normalized) {
        return;
      }
      setState(() {
        _directoryResults = const <UserProfile>[];
        _directorySearching = false;
        _directoryFailed = true;
        _directorySearched = true;
      });
    }
  }

  void _submitSearch() {
    if (!_isDirectoryTab) return;
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    _searchDirectory(query);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360
        ? 12.0
        : width < 600
            ? 16.0
            : 24.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: IconButton(
          key: const Key('dm_recipient_back_button'),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 20,
            color: Color(0xFF111827),
          ),
        ),
        titleSpacing: 0,
        title: Text(
          l10n.dmRecipientSelectionTitle,
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const <String>['NotoSansKR'],
            fontSize: context.rf(20).clamp(19, 22).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFEAECF0)),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontalPadding,
                      10,
                      horizontalPadding,
                      0,
                    ),
                    child: SizedBox(
                      height: context.rh(44, min: 42, max: 48),
                      child: TabBar(
                        controller: _tabController,
                        dividerColor: Colors.transparent,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicator: const UnderlineTabIndicator(
                          borderSide: BorderSide(
                            color: Color(0xFF111827),
                            width: 2.2,
                          ),
                          insets: EdgeInsets.symmetric(horizontal: 20),
                        ),
                        labelColor: const Color(0xFF111827),
                        unselectedLabelColor: const Color(0xFF667085),
                        labelStyle: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const <String>['NotoSansKR'],
                          fontSize: context.rf(14).clamp(13, 15).toDouble(),
                          fontWeight: FontWeight.w700,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const <String>['NotoSansKR'],
                          fontSize: context.rf(14).clamp(13, 15).toDouble(),
                          fontWeight: FontWeight.w600,
                        ),
                        tabs: <Widget>[
                          Tab(text: l10n.dmRecipientFriendsTab),
                          Tab(text: l10n.dmRecipientIdSearchTab),
                        ],
                      ),
                    ),
                  ),
                  _buildSearchField(horizontalPadding),
                  const Divider(height: 1, color: Color(0xFFEAECF0)),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: <Widget>[
                        _buildFriendsTab(horizontalPadding),
                        _buildDirectoryTab(horizontalPadding),
                      ],
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

  Widget _buildSearchField(double horizontalPadding) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        12,
        horizontalPadding,
        12,
      ),
      child: TextField(
        key: const Key('dm_recipient_search_field'),
        controller: _searchController,
        focusNode: _searchFocusNode,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        enableSuggestions: !_isDirectoryTab,
        onSubmitted: (_) => _submitSearch(),
        style: TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const <String>['NotoSansKR'],
          fontSize: context.rf(14).clamp(13, 15).toDouble(),
          fontWeight: FontWeight.w500,
          color: const Color(0xFF111827),
        ),
        decoration: InputDecoration(
          hintText: _isDirectoryTab
              ? l10n.dmRecipientIdSearchHint
              : l10n.dmRecipientFriendSearchHint,
          hintStyle: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const <String>['NotoSansKR'],
            fontSize: context.rf(14).clamp(13, 15).toDouble(),
            fontWeight: FontWeight.w400,
            color: const Color(0xFF98A2B3),
          ),
          prefixIcon: IconButton(
            key: const Key('dm_recipient_search_button'),
            tooltip: l10n.search,
            onPressed: _isDirectoryTab ? _submitSearch : null,
            icon: const Icon(Icons.search_rounded, size: 21),
            color: const Color(0xFF667085),
            disabledColor: const Color(0xFF667085),
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: l10n.clearSearchQuery,
                  onPressed: _searchController.clear,
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
          filled: true,
          fillColor: const Color(0xFFF2F4F7),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(
              color: Color(0xFF667085),
              width: 1.2,
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildFriendsTab(double horizontalPadding) {
    final l10n = AppLocalizations.of(context)!;
    if (_friendsLoading && _friends.isEmpty) {
      return _RecipientListSkeleton(horizontalPadding: horizontalPadding);
    }
    if (_friendsFailed && _friends.isEmpty) {
      return _RecipientMessage(
        icon: Icons.wifi_off_rounded,
        title: l10n.dmRecipientFriendsLoadFailedTitle,
        description: l10n.dmRecipientFriendsLoadFailedDescription,
      );
    }

    final visible = filterDmRecipientFriends(_friends, _query);
    if (visible.isEmpty) {
      return _RecipientMessage(
        icon: _query.isEmpty
            ? Icons.people_outline_rounded
            : Icons.person_search_outlined,
        title: _query.isEmpty
            ? l10n.dmRecipientNoFriendsTitle
            : l10n.noResultsFound,
        description: _query.isEmpty
            ? l10n.dmRecipientNoFriendsDescription
            : l10n.dmRecipientNoResultsDescription,
      );
    }
    return _buildRecipientList(
      visible,
      horizontalPadding: horizontalPadding,
      showIdPrefix: false,
    );
  }

  Widget _buildDirectoryTab(double horizontalPadding) {
    final l10n = AppLocalizations.of(context)!;
    if (_query.isEmpty) {
      return _RecipientMessage(
        icon: Icons.alternate_email_rounded,
        title: l10n.dmRecipientSearchPromptTitle,
        description: l10n.dmRecipientSearchPromptDescription,
      );
    }
    if (_directorySearching) {
      return _RecipientListSkeleton(horizontalPadding: horizontalPadding);
    }
    if (_directoryFailed) {
      return _RecipientMessage(
        icon: Icons.wifi_off_rounded,
        title: l10n.dmRecipientSearchFailedTitle,
        description: l10n.dmRecipientSearchFailedDescription,
        actionLabel: l10n.retryAction,
        onAction: () => _searchDirectory(_query),
      );
    }
    if (_directorySearched && _directoryResults.isEmpty) {
      return _RecipientMessage(
        icon: Icons.person_search_outlined,
        title: l10n.noResultsFound,
        description: l10n.dmRecipientNoResultsDescription,
      );
    }
    if (_directoryResults.isEmpty) return const SizedBox.shrink();
    return _buildRecipientList(
      _directoryResults,
      horizontalPadding: horizontalPadding,
      showIdPrefix: true,
    );
  }

  Widget _buildRecipientList(
    List<UserProfile> users, {
    required double horizontalPadding,
    required bool showIdPrefix,
  }) {
    final friendIds = _friends.map((friend) => friend.uid).toSet();
    return ListView.builder(
      key: PageStorageKey<String>(
        showIdPrefix ? 'dm_recipient_directory' : 'dm_recipient_friends',
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        4,
        horizontalPadding,
        MediaQuery.paddingOf(context).bottom + 16,
      ),
      itemExtent: 68,
      scrollCacheExtent: const ScrollCacheExtent.pixels(544),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final user = users[index];
        return _RecipientTile(
          key: ValueKey<String>('dm_recipient_${user.uid}'),
          profile: user,
          showIdPrefix: showIdPrefix,
          isFriend: showIdPrefix && friendIds.contains(user.uid),
          onTap: () {
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.of(context).pop(user);
          },
        );
      },
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    super.key,
    required this.profile,
    required this.showIdPrefix,
    required this.isFriend,
    required this.onTap,
  });

  final UserProfile profile;
  final bool showIdPrefix;
  final bool isFriend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      label: profile.displayNameOrNickname,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Color(0xFFF2F4F7)),
              ),
            ),
            child: Row(
              children: [
                UserAvatar(
                  uid: profile.uid,
                  photoUrl: profile.photoURL ?? '',
                  photoVersion: 0,
                  isAnonymous: false,
                  size: 44,
                  placeholderColor: const Color(0xFFF2F4F7),
                  placeholderIcon: Icons.person_outline_rounded,
                  placeholderIconSize: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    showIdPrefix
                        ? '@${profile.displayNameOrNickname}'
                        : profile.displayNameOrNickname,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const <String>['NotoSansKR'],
                      fontSize: context.rf(15).clamp(14, 16).toDouble(),
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                if (isFriend) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F4F7),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      l10n.friends,
                      style: TextStyle(
                        fontFamily: uiFontFamily(context, 'Inter'),
                        fontFamilyFallback: const <String>['NotoSansKR'],
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF475467),
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 21,
                  color: Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecipientListSkeleton extends StatelessWidget {
  const _RecipientListSkeleton({required this.horizontalPadding});

  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(horizontalPadding, 4, horizontalPadding, 16),
      itemExtent: 68,
      itemCount: 7,
      itemBuilder: (_, index) {
        return Row(
          children: [
            const _SkeletonBox(width: 44, height: 44, circular: true),
            const SizedBox(width: 12),
            _SkeletonBox(
              width: 104 + (index % 3) * 24,
              height: 14,
            ),
          ],
        );
      },
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.circular = false,
  });

  final double width;
  final double height;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        shape: circular ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circular ? null : BorderRadius.circular(6),
      ),
    );
  }
}

class _RecipientMessage extends StatelessWidget {
  const _RecipientMessage({
    required this.icon,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 48)
                  .clamp(0.0, double.infinity)
                  .toDouble(),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF2F4F7),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(icon, size: 29, color: const Color(0xFF667085)),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const <String>['NotoSansKR'],
                      fontSize: context.rf(16).clamp(15, 18).toDouble(),
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF344054),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const <String>['NotoSansKR'],
                      fontSize: context.rf(13).clamp(12, 14).toDouble(),
                      fontWeight: FontWeight.w400,
                      height: isChineseUi(context) ? 1.55 : 1.45,
                      color: const Color(0xFF667085),
                    ),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 14),
                    TextButton.icon(
                      onPressed: onAction,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF344054),
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 19),
                      label: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
