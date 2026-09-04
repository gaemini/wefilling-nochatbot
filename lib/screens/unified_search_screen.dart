// lib/screens/unified_search_screen.dart
// 통합 검색 화면 - 탭별(이름/게시글/모임)로 검색 결과 분리

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/meetup.dart';
import '../models/post.dart';
import '../models/user_profile.dart';
import '../models/relationship_status.dart';
import '../providers/relationship_provider.dart';
import '../screens/meetup_detail_screen.dart';
import '../screens/friend_profile_screen.dart';
import '../services/meetup_service.dart';
import '../services/post_service.dart';
import '../ui/widgets/app_icon_button.dart';
import '../ui/widgets/hanyang_verification_gate.dart';
import '../widgets/post_search_card.dart';
import '../widgets/user_tile.dart';
import '../utils/responsive_helper.dart';
import '../utils/latest_request_guard.dart';

class UnifiedSearchScreen extends StatefulWidget {
  /// 0: 이름(유저), 1: 게시글, 2: 모임
  final int initialTabIndex;
  final String? initialQuery;

  const UnifiedSearchScreen({
    super.key,
    this.initialTabIndex = 0,
    this.initialQuery,
  });

  @override
  State<UnifiedSearchScreen> createState() => _UnifiedSearchScreenState();
}

class _UnifiedSearchScreenState extends State<UnifiedSearchScreen>
    with SingleTickerProviderStateMixin {
  static const _tabCount = 3;

  late final TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;

  final PostService _postService = PostService();
  final MeetupService _meetupService = MeetupService();

  bool _relationshipInitialized = false;

  bool _isLoadingPosts = false;
  bool _isLoadingMeetups = false;

  String? _postsError;
  String? _meetupsError;

  List<Post> _postResults = const [];
  List<Meetup> _meetupResults = const [];
  final LatestRequestGuard _postSearchGuard = LatestRequestGuard();
  final LatestRequestGuard _meetupSearchGuard = LatestRequestGuard();

  @override
  void initState() {
    super.initState();

    final initialIndex = widget.initialTabIndex.clamp(0, _tabCount - 1);
    _tabController = TabController(
        length: _tabCount, vsync: this, initialIndex: initialIndex);
    _tabController.addListener(_onTabChanged);

    _searchController.addListener(() {
      // clear 아이콘 노출용
      if (mounted) setState(() {});
    });

    _searchFocusNode.addListener(() {
      // placeholder(중앙 정렬) 노출/숨김용
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeRelationshipProvider();

      final initialQuery = widget.initialQuery?.trim() ?? '';
      if (initialQuery.isNotEmpty) {
        _searchController.text = initialQuery;
        _performSearchForActiveTab(immediate: true);
      }
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _postSearchGuard.invalidate();
    _meetupSearchGuard.invalidate();
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initializeRelationshipProvider() async {
    try {
      final provider = context.read<RelationshipProvider>();
      await provider.initialize();
    } catch (_) {
      // 유저 검색 탭에서 에러 상태로 표기됨 (provider.errorMessage)
    } finally {
      if (mounted) {
        setState(() => _relationshipInitialized = true);

        // The user can start typing while the relationship subscriptions are
        // initializing. Run the latest text once initialization finishes so
        // the first search is not silently dropped.
        final query = _searchController.text.trim();
        if (_tabController.index == 0 && query.isNotEmpty) {
          _debounceTimer?.cancel();
          _searchUsers(query);
        }
      }
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final q = _searchController.text.trim();
    if (q.isEmpty) return;
    _performSearchForActiveTab(immediate: true);
  }

  void _onQueryChanged(String query) {
    final q = query.trim();
    _debounceTimer?.cancel();
    // 입력 순간 진행 중인 이전 검색을 무효화한다. 새 요청이 300ms 뒤에
    // 시작되기 전 오래된 응답이 도착해도 현재 검색어 결과를 덮지 않는다.
    _postSearchGuard.invalidate();
    _meetupSearchGuard.invalidate();
    // User search has its own async request guard in RelationshipProvider.
    // Clearing here invalidates it during the debounce window, preventing an
    // old response from being rendered under newly typed text.
    if (q.isEmpty) {
      _clearAllResults();
      return;
    }
    context.read<RelationshipProvider>().clearSearchResults();
    // 새 검색어를 입력한 직후에는 이전 검색어의 포스트/모임을 화면에서
    // 제거한다. 네트워크 요청이 시작되는 300ms 동안 오래된 결과가 새
    // 검색어의 결과처럼 보이는 것을 방지한다.
    setState(() {
      _postResults = const [];
      _meetupResults = const [];
      _postsError = null;
      _meetupsError = null;
      _isLoadingPosts = false;
      _isLoadingMeetups = false;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _performSearchForActiveTab(immediate: true);
    });
  }

  void _clearAllResults() {
    _postSearchGuard.invalidate();
    _meetupSearchGuard.invalidate();
    // 유저 검색 결과는 provider에 있음
    context.read<RelationshipProvider>().clearSearchResults();
    setState(() {
      _postsError = null;
      _meetupsError = null;
      _postResults = const [];
      _meetupResults = const [];
      _isLoadingPosts = false;
      _isLoadingMeetups = false;
    });
  }

  Future<void> _performSearchForActiveTab({required bool immediate}) async {
    final q = _searchController.text.trim();
    if (q.isEmpty) return;

    switch (_tabController.index) {
      case 0:
        _searchUsers(q);
        return;
      case 1:
        await _searchPosts(q);
        return;
      case 2:
        await _searchMeetups(q);
        return;
    }
  }

  void _searchUsers(String query) {
    if (!_relationshipInitialized) return;
    final provider = context.read<RelationshipProvider>();
    provider.searchUsers(query);
  }

  Future<void> _searchPosts(String query) async {
    final requestToken = _postSearchGuard.begin();
    setState(() {
      _isLoadingPosts = true;
      _postsError = null;
    });
    try {
      final posts = await _postService.searchPosts(query);
      if (!mounted || !_postSearchGuard.isCurrent(requestToken)) return;
      setState(() {
        _postResults = posts;
        _isLoadingPosts = false;
      });
    } catch (e) {
      if (!mounted || !_postSearchGuard.isCurrent(requestToken)) return;
      setState(() {
        _postResults = const [];
        _isLoadingPosts = false;
        _postsError = e.toString();
      });
    }
  }

  Future<void> _searchMeetups(String query) async {
    final requestToken = _meetupSearchGuard.begin();
    setState(() {
      _isLoadingMeetups = true;
      _meetupsError = null;
    });
    try {
      final meetups = await _meetupService.searchMeetupsAsync(query);
      if (!mounted || !_meetupSearchGuard.isCurrent(requestToken)) return;
      setState(() {
        _meetupResults = meetups;
        _isLoadingMeetups = false;
      });
    } catch (e) {
      if (!mounted || !_meetupSearchGuard.isCurrent(requestToken)) return;
      setState(() {
        _meetupResults = const [];
        _isLoadingMeetups = false;
        _meetupsError = e.toString();
      });
    }
  }

  // ---- 유저 액션 (SearchUsersPage 로직 재사용) ----
  Future<void> _sendFriendRequest(String toUid) async {
    final provider = context.read<RelationshipProvider>();
    final success = await provider.sendFriendRequest(toUid);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (l10n?.friendRequestSent ?? '')
              : (provider.errorMessage ?? l10n?.friendRequestFailed ?? ''),
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _cancelFriendRequest(String toUid) async {
    final provider = context.read<RelationshipProvider>();
    final success = await provider.cancelFriendRequest(toUid);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? (l10n?.friendRequestCancelled ?? '')
              : (l10n?.friendRequestCancelFailed ?? ''),
        ),
        backgroundColor: success ? Colors.orange : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _unfriend(String otherUid) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n?.removeFriend ?? ''),
        content: Text(l10n?.confirmUnfriend ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.cancel ?? ''),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n?.confirm ?? ''),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final provider = context.read<RelationshipProvider>();
    final success = await provider.unfriend(otherUid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? (l10n?.unfriendedUser ?? '')
            : (l10n?.unfriendFailed ?? '')),
        backgroundColor: success ? Colors.orange : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _unblockUser(String targetUid) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n?.unblockUser ?? ''),
        content: Text(l10n?.confirmUnblock ?? ''),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n?.cancel ?? ''),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n?.confirm ?? ''),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    final provider = context.read<RelationshipProvider>();
    final success = await provider.unblockUser(targetUid);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success
            ? (l10n?.userUnblocked ?? '')
            : (l10n?.unblockFailed ?? '')),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _handleUserAction(UserProfile user, RelationshipStatus status) {
    switch (status) {
      case RelationshipStatus.none:
        _sendFriendRequest(user.uid);
        break;
      case RelationshipStatus.pendingOut:
        _cancelFriendRequest(user.uid);
        break;
      case RelationshipStatus.friends:
        _unfriend(user.uid);
        break;
      case RelationshipStatus.blocked:
        _unblockUser(user.uid);
        break;
      case RelationshipStatus.pendingIn:
      case RelationshipStatus.blockedBy:
        break;
    }
  }

  void _openUserProfile(UserProfile user) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FriendProfileScreen(
          userId: user.uid,
          nickname: user.displayNameOrNickname,
          photoURL: user.photoURL,
          email: user.email,
          university: user.university,
          allowNonFriendsPreview: true,
        ),
      ),
    );
  }

  // ---- UI ----
  String _tabLabel(BuildContext context, int index) {
    final locale = Localizations.localeOf(context).languageCode;
    final isKo = locale == 'ko';
    switch (index) {
      case 0:
        return isKo ? '이름' : 'Name';
      case 1:
        return isKo ? '포스트' : 'Posts';
      case 2:
        return isKo ? '모임' : 'Meetups';
      default:
        return '';
    }
  }

  Widget _buildSearchField(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 360;
    final horizontal = (width * 0.045).clamp(14.0, 24.0).toDouble();
    final showCenteredPlaceholder =
        _searchController.text.trim().isEmpty && !_searchFocusNode.hasFocus;
    return Padding(
      padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 8),
      child: SizedBox(
        height: compact ? 44 : 46,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF4F5F7),
            borderRadius: BorderRadius.circular(compact ? 14 : 16),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: compact ? 40 : 44,
                    child: const Center(
                      child: Icon(
                        Icons.search_rounded,
                        color: Color(0xFF667085),
                        size: 20,
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      textAlign: TextAlign.start, // 입력은 항상 왼쪽부터
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 0, vertical: 12),
                      ),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(14).clamp(13.5, 15).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF111827),
                      ),
                      textInputAction: TextInputAction.search,
                      onChanged: _onQueryChanged,
                    ),
                  ),
                  SizedBox(
                    width: compact ? 40 : 44,
                    child: _searchController.text.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              _clearAllResults();
                              FocusScope.of(context).unfocus();
                            },
                            child: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF667085),
                              size: 19,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
              if (showCenteredPlaceholder)
                IgnorePointer(
                  child: Padding(
                    // 좌/우 아이콘 영역을 제외하고 가운데 배치
                    padding: EdgeInsets.symmetric(
                      horizontal: compact ? 40 : 44,
                    ),
                    child: Text(
                      l10n.enterSearchQuery,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        color: const Color(0xFF98A2B3),
                        fontSize: context.rf(14).clamp(13, 15).toDouble(),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPrompt({
    required IconData icon,
    required String title,
    required String subtitle,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 72),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 96).clamp(0.0, double.infinity),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.25,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 36, color: const Color(0xFF98A2B3)),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: ['NotoSansKR'],
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: ['NotoSansKR'],
                        fontSize: 13.5,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF667085),
                        height: 1.5,
                      ),
                    ),
                    if (actionLabel != null && onAction != null) ...[
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onAction,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(actionLabel),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        toolbarHeight: 56,
        centerTitle: true,
        leading: AppIconButton(
          icon: Icons.arrow_back_rounded,
          onPressed: () => Navigator.pop(context),
          semanticLabel: AppLocalizations.of(context)!.back,
        ),
        title: Text(
          Localizations.localeOf(context).languageCode == 'ko'
              ? '검색'
              : 'Search',
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Color(0xFF111827),
            letterSpacing: -0.2,
          ),
        ),
        actions: const [SizedBox(width: 48)],
      ),
      body: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.25,
        child: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                children: [
                  _buildSearchField(context),
                  TabBar(
                    controller: _tabController,
                    isScrollable: false,
                    labelColor: const Color(0xFF111827),
                    unselectedLabelColor: const Color(0xFF6B7280),
                    labelStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: ['NotoSansKR'],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -0.1,
                    ),
                    indicatorColor: AppColors.pointColor,
                    indicatorWeight: 2.5,
                    indicatorSize: TabBarIndicatorSize.label,
                    tabs: List.generate(
                      _tabCount,
                      (i) => Tab(text: _tabLabel(context, i)),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFEAECF0)),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildUsersTab(),
                        _buildPostsTab(),
                        _buildMeetupsTab(),
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

  Widget _buildUsersTab() {
    final q = _searchController.text.trim();
    final locale = Localizations.localeOf(context).languageCode;
    final isKo = locale == 'ko';

    if (!_relationshipInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    if (q.isEmpty) {
      return _buildEmptyPrompt(
        icon: Icons.search,
        title: isKo ? '사용자를 검색해보세요' : 'Search for users',
        subtitle: isKo
            ? '닉네임이나 이름으로 검색하여\n새로운 친구를 찾아보세요'
            : 'Search by nickname or name\nto find new friends',
      );
    }

    return Consumer<RelationshipProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (provider.errorMessage != null) {
          return _buildEmptyPrompt(
            icon: Icons.error_outline,
            title: AppLocalizations.of(context)!.error,
            // Repository/provider errors may contain implementation details
            // such as an App Check exception name. Keep those in diagnostics,
            // but present a localized recovery path to the user.
            subtitle: AppLocalizations.of(context)!.errorOccurred,
            actionLabel: AppLocalizations.of(context)!.retryAction,
            onAction: () => _searchUsers(q),
          );
        }

        if (provider.searchResults.isEmpty) {
          return _buildEmptyPrompt(
            icon: Icons.person_off,
            title: AppLocalizations.of(context)!.noResultsFound,
            subtitle: AppLocalizations.of(context)!.tryDifferentSearch,
          );
        }

        final bottomPadding = MediaQuery.of(context).padding.bottom;
        return ListView.builder(
          padding: EdgeInsets.only(
            top: 8,
            bottom: bottomPadding > 0 ? bottomPadding + 8 : 8,
          ),
          itemCount: provider.searchResults.length,
          itemBuilder: (context, index) {
            final user = provider.searchResults[index];
            final status = provider.getRelationshipStatus(user.uid);
            return UserTile(
              user: user,
              relationshipStatus: status,
              onActionPressed: () => _handleUserAction(user, status),
              onTilePressed: () => _openUserProfile(user),
              minimal: true,
            );
          },
        );
      },
    );
  }

  Widget _buildPostsTab() {
    final q = _searchController.text.trim();
    final locale = Localizations.localeOf(context).languageCode;
    final isKo = locale == 'ko';

    if (q.isEmpty) {
      return _buildEmptyPrompt(
        icon: Icons.search,
        title: isKo ? '포스트를 검색해보세요' : 'Search posts',
        subtitle:
            isKo ? '제목/내용 기준으로\n포스트를 찾아볼 수 있어요' : 'Search by title/content',
      );
    }

    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_postsError != null) {
      return _buildEmptyPrompt(
        icon: Icons.error_outline,
        title: AppLocalizations.of(context)!.error,
        subtitle: AppLocalizations.of(context)!.errorOccurred,
        actionLabel: AppLocalizations.of(context)!.retryAction,
        onAction: () => _searchPosts(q),
      );
    }

    if (_postResults.isEmpty) {
      return _buildEmptyPrompt(
        icon: Icons.search_off,
        title: AppLocalizations.of(context)!.noSearchResults,
        subtitle: '"$q"${isKo ? '에 대한 검색 결과가 없습니다' : ' - No results found'}',
      );
    }

    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return ListView.builder(
      padding: EdgeInsets.only(top: 6, bottom: bottomPadding + 12),
      itemCount: _postResults.length,
      itemBuilder: (context, index) {
        return PostSearchCard(post: _postResults[index]);
      },
    );
  }

  Widget _buildMeetupsTab() {
    final q = _searchController.text.trim();
    final locale = Localizations.localeOf(context).languageCode;
    final isKo = locale == 'ko';

    if (q.isEmpty) {
      return _buildEmptyPrompt(
        icon: Icons.search,
        title: isKo ? '모임을 검색해보세요' : 'Search meetups',
        subtitle: isKo
            ? '제목/설명/위치/호스트 기준으로\n모임을 찾아볼 수 있어요'
            : 'Search by title/description/location/host',
      );
    }

    if (_isLoadingMeetups) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_meetupsError != null) {
      return _buildEmptyPrompt(
        icon: Icons.error_outline,
        title: AppLocalizations.of(context)!.error,
        subtitle: AppLocalizations.of(context)!.errorOccurred,
        actionLabel: AppLocalizations.of(context)!.retryAction,
        onAction: () => _searchMeetups(q),
      );
    }

    if (_meetupResults.isEmpty) {
      return _buildEmptyPrompt(
        icon: Icons.search_off,
        title: AppLocalizations.of(context)!.noSearchResults,
        subtitle: '"$q"${isKo ? '에 대한 검색 결과가 없습니다' : ' - No results found'}',
      );
    }

    final width = MediaQuery.sizeOf(context).width;
    final horizontal = (width * 0.045).clamp(14.0, 24.0).toDouble();
    final compact = width < 360;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    return ListView.separated(
      padding: EdgeInsets.only(top: 4, bottom: bottomPadding + 12),
      itemCount: _meetupResults.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        thickness: 1,
        indent: horizontal,
        endIndent: horizontal,
        color: const Color(0xFFEAECF0),
      ),
      itemBuilder: (context, index) {
        final meetup = _meetupResults[index];
        final hostName = (meetup.hostNickname ?? '').trim().isNotEmpty
            ? meetup.hostNickname!.trim()
            : meetup.host;
        final isHanyangLocked = HanyangVerificationGate.isLockedForCurrentUser(
          context,
          meetup.requiresHanyangVerification,
        );
        return HanyangVerificationGate(
          locked: isHanyangLocked,
          compact: true,
          child: Material(
            color: Colors.white,
            child: InkWell(
              onTap: isHanyangLocked
                  ? null
                  : () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MeetupDetailScreen(
                            meetup: meetup,
                            meetupId: meetup.id,
                            onMeetupDeleted: () {
                              final q = _searchController.text.trim();
                              if (q.isNotEmpty) _searchMeetups(q);
                            },
                          ),
                        ),
                      );
                    },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal,
                  vertical: compact ? 12 : 14,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            meetup.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: compact ? 14.5 : 15.5,
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                              height: 1.35,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          meetup.getFormattedDate(context),
                          maxLines: 1,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: ['NotoSansKR'],
                            fontSize: 12,
                            color: Color(0xFF667085),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${AppLocalizations.of(context)!.host}: $hostName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: ['NotoSansKR'],
                        fontSize: 12.5,
                        color: Color(0xFF667085),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      meetup.description,
                      style: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: ['NotoSansKR'],
                        fontSize: 13.5,
                        color: Color(0xFF475467),
                        height: 1.45,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 15,
                          color: Color(0xFF667085),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            meetup.location,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: ['NotoSansKR'],
                              fontSize: 12,
                              color: Color(0xFF667085),
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Icon(
                          Icons.people_outline_rounded,
                          size: 16,
                          color: Color(0xFF667085),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${meetup.currentParticipants}/${meetup.maxParticipants}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: ['NotoSansKR'],
                            fontSize: 12,
                            color: Color(0xFF475467),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
