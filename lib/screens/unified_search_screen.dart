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
import '../services/meetup_service.dart';
import '../services/post_service.dart';
import '../ui/widgets/app_icon_button.dart';
import '../widgets/post_search_card.dart';
import '../widgets/user_tile.dart';

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

  @override
  void initState() {
    super.initState();

    final initialIndex = widget.initialTabIndex.clamp(0, _tabCount - 1);
    _tabController = TabController(length: _tabCount, vsync: this, initialIndex: initialIndex);
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
      if (mounted) setState(() => _relationshipInitialized = true);
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
    if (q.isEmpty) {
      _clearAllResults();
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _performSearchForActiveTab(immediate: true);
    });
  }

  void _clearAllResults() {
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
    setState(() {
      _isLoadingPosts = true;
      _postsError = null;
    });
    try {
      final posts = await _postService.searchPosts(query);
      if (!mounted) return;
      setState(() {
        _postResults = posts;
        _isLoadingPosts = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _postResults = const [];
        _isLoadingPosts = false;
        _postsError = e.toString();
      });
    }
  }

  Future<void> _searchMeetups(String query) async {
    setState(() {
      _isLoadingMeetups = true;
      _meetupsError = null;
    });
    try {
      final meetups = await _meetupService.searchMeetupsAsync(query);
      if (!mounted) return;
      setState(() {
        _meetupResults = meetups;
        _isLoadingMeetups = false;
      });
    } catch (e) {
      if (!mounted) return;
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
          success ? (l10n?.friendRequestCancelled ?? '') : (l10n?.friendRequestCancelFailed ?? ''),
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
        content: Text(success ? (l10n?.unfriendedUser ?? '') : (l10n?.unfriendFailed ?? '')),
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
        content: Text(success ? (l10n?.userUnblocked ?? '') : (l10n?.unblockFailed ?? '')),
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

  // ---- UI ----
  String _tabLabel(BuildContext context, int index) {
    final locale = Localizations.localeOf(context).languageCode;
    final isKo = locale == 'ko';
    switch (index) {
      case 0:
        return isKo ? '이름' : 'Name';
      case 1:
        return isKo ? '게시글' : 'Posts';
      case 2:
        return isKo ? '모임' : 'Meetups';
      default:
        return '';
    }
  }

  Widget _buildSearchField(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final showCenteredPlaceholder =
        _searchController.text.trim().isEmpty && !_searchFocusNode.hasFocus;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF5F6F8),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 44,
                  child: Center(
                    child: Icon(Icons.search, color: Colors.black54, size: 20),
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
                    style: const TextStyle(fontSize: 14),
                    textInputAction: TextInputAction.search,
                    onChanged: _onQueryChanged,
                  ),
                ),
                SizedBox(
                  width: 44,
                  child: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchController.clear();
                            _clearAllResults();
                            FocusScope.of(context).unfocus();
                          },
                          child: const Icon(
                            Icons.clear,
                            color: Colors.black54,
                            size: 18,
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
                  padding: const EdgeInsets.symmetric(horizontal: 44),
                  child: Text(
                    l10n.enterSearchQuery,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, fontSize: 14),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPrompt({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        shadowColor: Colors.black12,
        leading: AppIconButton(
          icon: Icons.arrow_back,
          onPressed: () => Navigator.pop(context),
          semanticLabel: AppLocalizations.of(context)!.back,
        ),
        title: Text(
          Localizations.localeOf(context).languageCode == 'ko' ? '검색창' : 'Search',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
      ),
      body: Column(
        children: [
          _buildSearchField(context),
          TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: Colors.black,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: AppColors.pointColor,
            indicatorWeight: 2.5,
            tabs: List.generate(
              _tabCount,
              (i) => Tab(text: _tabLabel(context, i)),
            ),
          ),
          const Divider(height: 1),
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
        subtitle: isKo ? '닉네임이나 이름으로 검색하여\n새로운 친구를 찾아보세요' : 'Search by nickname or name\nto find new friends',
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
            subtitle: provider.errorMessage!,
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
              onTilePressed: () {},
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
        title: isKo ? '게시글을 검색해보세요' : 'Search posts',
        subtitle: isKo ? '제목/내용/작성자 기준으로\n게시글을 찾아볼 수 있어요' : 'Search by title/content/author',
      );
    }

    if (_isLoadingPosts) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_postsError != null) {
      return _buildEmptyPrompt(
        icon: Icons.error_outline,
        title: AppLocalizations.of(context)!.error,
        subtitle: _postsError!,
      );
    }

    if (_postResults.isEmpty) {
      return _buildEmptyPrompt(
        icon: Icons.search_off,
        title: AppLocalizations.of(context)!.noSearchResults,
        subtitle: '"$q"${isKo ? '에 대한 검색 결과가 없습니다' : ' - No results found'}',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
        subtitle: isKo ? '제목/설명/위치/호스트 기준으로\n모임을 찾아볼 수 있어요' : 'Search by title/description/location/host',
      );
    }

    if (_isLoadingMeetups) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_meetupsError != null) {
      return _buildEmptyPrompt(
        icon: Icons.error_outline,
        title: AppLocalizations.of(context)!.error,
        subtitle: _meetupsError!,
      );
    }

    if (_meetupResults.isEmpty) {
      return _buildEmptyPrompt(
        icon: Icons.search_off,
        title: AppLocalizations.of(context)!.noSearchResults,
        subtitle: '"$q"${isKo ? '에 대한 검색 결과가 없습니다' : ' - No results found'}',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _meetupResults.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final meetup = _meetupResults[index];
        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => MeetupDetailScreen(
                  meetup: meetup,
                  meetupId: meetup.id,
                  onMeetupDeleted: () {
                    final q = _searchController.text.trim();
                    if (q.isNotEmpty) {
                      _searchMeetups(q);
                    }
                  },
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFE9F1FF),
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        meetup.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        meetup.getFormattedDate(context),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${AppLocalizations.of(context)!.host}: ${meetup.host}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black.withOpacity(0.7),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  meetup.description,
                  style: TextStyle(fontSize: 14, color: Colors.black.withOpacity(0.6)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.location_on, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        meetup.location,
                        style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.6)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(Icons.people, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 4),
                    Text(
                      '${meetup.currentParticipants}/${meetup.maxParticipants}',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

