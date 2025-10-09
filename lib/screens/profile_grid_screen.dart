// lib/screens/profile_grid_screen.dart
// 프로필 그리드 메인 화면
// 프로필 헤더, 하이라이트 릴, 포스트 그리드 통합
// Feature Flag로 제어되는 새로운 프로필 UI

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user_profile.dart';
import '../widgets/profile_header.dart';
import '../widgets/highlight_reels.dart';
import '../widgets/post_grid.dart';
import '../widgets/profile_action_buttons.dart';
import '../services/profile_grid_adapter_service.dart';
import '../services/feature_flag_service.dart';
import '../providers/auth_provider.dart';
import 'profile_edit_screen.dart';

class ProfileGridScreen extends StatefulWidget {
  final String? userId; // null이면 현재 사용자 프로필
  
  const ProfileGridScreen({
    Key? key,
    this.userId,
  }) : super(key: key);

  @override
  State<ProfileGridScreen> createState() => _ProfileGridScreenState();
}

class _ProfileGridScreenState extends State<ProfileGridScreen> with TickerProviderStateMixin {
  final ProfileDataAdapter _profileAdapter = ProfileDataAdapter();
  
  UserProfile? _userProfile;
  Map<String, int> _stats = {};
  List<HighlightItem> _highlights = [];
  PostDisplayMode _displayMode = PostDisplayMode.grid;
  
  bool _isLoading = true;
  bool _isOwnProfile = false;
  bool _isFollowing = false;
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkFeatureFlag();
    _loadProfileData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Feature Flag 확인
  void _checkFeatureFlag() {
    // 다른 사용자의 프로필을 보는 경우 feature flag를 확인하지 않음
    if (widget.userId != null) {
      return;
    }
    
    // 자신의 프로필을 볼 때만 feature flag 확인
    if (!FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      // Feature가 비활성화된 경우 기존 프로필 화면으로 이동
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/mypage');
      });
    }
  }

  /// 프로필 데이터 로드
  Future<void> _loadProfileData() async {
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final currentUserId = authProvider.user?.uid;
      final targetUserId = widget.userId ?? currentUserId;
      
      if (targetUserId == null) {
        throw Exception('사용자 ID를 찾을 수 없습니다.');
      }

      setState(() {
        _isOwnProfile = targetUserId == currentUserId;
      });

      // 프로필 정보 로드
      final profile = await _profileAdapter.fetchUserProfile(targetUserId);
      if (profile == null) {
        throw Exception('프로필을 찾을 수 없습니다.');
      }

      // 통계 정보 로드
      final stats = await _profileAdapter.getUserPostStats(targetUserId);
      
      // 친구 관계 확인 (다른 사용자 프로필인 경우)
      bool isFollowing = false;
      if (!_isOwnProfile && currentUserId != null) {
        isFollowing = await _profileAdapter.isViewerFriend(currentUserId, targetUserId);
      }

      // 하이라이트 데이터 로드 (임시 데이터)
      final highlights = _loadHighlights();

      setState(() {
        _userProfile = profile;
        _stats = stats;
        _isFollowing = isFollowing;
        _highlights = highlights;
        _isLoading = false;
      });

    } catch (e) {
      print('프로필 데이터 로드 오류: $e');
      setState(() {
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('프로필을 불러올 수 없습니다: $e')),
        );
      }
    }
  }

  /// 하이라이트 데이터 로드 (임시 구현)
  List<HighlightItem> _loadHighlights() {
    return [
      const HighlightItem(
        id: '1',
        title: '여행',
        backgroundColor: Colors.blue,
      ),
      const HighlightItem(
        id: '2', 
        title: '음식',
        backgroundColor: Colors.orange,
      ),
      const HighlightItem(
        id: '3',
        title: '취미',
        backgroundColor: Colors.green,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    // Feature Flag 재확인
    if (!FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      return Scaffold(
        appBar: AppBar(title: const Text('프로필')),
        body: const Center(
          child: Text(
            '프로필 그리드 기능이 비활성화되어 있습니다.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('프로필')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_userProfile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('프로필')),
        body: const Center(
          child: Text('프로필을 불러올 수 없습니다.'),
        ),
      );
    }

    return Scaffold(
      appBar: _buildAppBar(),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  // 프로필 헤더
                  ProfileHeader(
                    profile: _userProfile!,
                    stats: _stats,
                    isOwnProfile: _isOwnProfile,
                    onEditProfile: _handleEditProfile,
                    onFollow: _handleFollow,
                    onMessage: _handleMessage,
                  ),
                  
                  // 액션 버튼
                  ProfileActionButtons(
                    isOwnProfile: _isOwnProfile,
                    isFollowing: _isFollowing,
                    onEditProfile: _handleEditProfile,
                    onFollow: _handleFollow,
                    onUnfollow: _handleUnfollow,
                    onMessage: _handleMessage,
                    onShare: _handleShare,
                    onMoreActions: _handleMoreActions,
                  ),
                  
                  // 하이라이트 릴
                  HighlightReels(
                    highlights: _highlights,
                    canEdit: _isOwnProfile,
                    onHighlightTap: _handleHighlightTap,
                    onAddHighlight: _handleAddHighlight,
                  ),
                  
                  // 포스트 디스플레이 모드 토글
                  PostDisplayModeToggle(
                    currentMode: _displayMode,
                    onModeChanged: _handleDisplayModeChanged,
                  ),
                ],
              ),
            ),
          ];
        },
        body: PostGrid(
          userId: widget.userId ?? Provider.of<AuthProvider>(context, listen: false).user!.uid,
          displayMode: _displayMode,
          isOwnProfile: _isOwnProfile,
          onPostTap: _handlePostTap,
        ),
      ),
    );
  }

  /// AppBar 구성
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(_userProfile?.displayNameOrNickname ?? '프로필'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        if (_isOwnProfile)
          IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _handleMoreActions(),
            tooltip: '메뉴',
          ),
      ],
    );
  }

  /// 프로필 편집 처리
  void _handleEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ProfileEditScreen(),
      ),
    ).then((_) {
      // 프로필 편집 후 데이터 새로고침
      _loadProfileData();
    });
  }

  /// 팔로우 처리
  void _handleFollow() {
    // TODO: 팔로우 로직 구현
    setState(() {
      _isFollowing = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('팔로우했습니다.')),
    );
  }

  /// 언팔로우 처리
  void _handleUnfollow() {
    // TODO: 언팔로우 로직 구현
    setState(() {
      _isFollowing = false;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('팔로우를 취소했습니다.')),
    );
  }

  /// 메시지 처리
  void _handleMessage() {
    // TODO: 메시지 화면으로 이동
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('메시지 기능은 준비 중입니다.')),
    );
  }

  /// 공유 처리
  void _handleShare() {
    // TODO: 프로필 공유 로직 구현
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('프로필 링크를 복사했습니다.')),
    );
  }

  /// 더보기 액션 처리
  void _handleMoreActions() {
    ProfileMoreActionsSheet.show(
      context,
      isOwnProfile: _isOwnProfile,
      onBlock: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('사용자를 차단했습니다.')),
        );
      },
      onReport: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('신고가 접수되었습니다.')),
        );
      },
      onCopyLink: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('프로필 링크를 복사했습니다.')),
        );
      },
      onSettings: () {
        // TODO: 설정 화면으로 이동
      },
    );
  }

  /// 하이라이트 탭 처리
  void _handleHighlightTap(HighlightItem highlight) {
    // TODO: 하이라이트 상세 화면으로 이동
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${highlight.title} 하이라이트를 선택했습니다.')),
    );
  }

  /// 하이라이트 추가 처리
  void _handleAddHighlight() {
    showDialog(
      context: context,
      builder: (context) => CreateHighlightDialog(
        onCreateHighlight: (title) {
          setState(() {
            _highlights.add(HighlightItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              title: title,
              backgroundColor: Colors.primaries[_highlights.length % Colors.primaries.length],
            ));
          });
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$title 하이라이트를 만들었습니다.')),
          );
        },
      ),
    );
  }

  /// 디스플레이 모드 변경 처리
  void _handleDisplayModeChanged(PostDisplayMode mode) {
    setState(() {
      _displayMode = mode;
    });
  }

  /// 포스트 탭 처리
  void _handlePostTap(ProfilePost post) {
    // TODO: 포스트 상세 화면으로 이동
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('포스트를 선택했습니다: ${post.text}')),
    );
  }
}
