// lib/screens/profile_grid_screen.dart
// 프로필 그리드 메인 화면
// 프로필 헤더, 하이라이트 릴, 포스트 그리드 통합
// Feature Flag로 제어되는 새로운 프로필 UI

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:firebase_performance/firebase_performance.dart';
import '../l10n/app_localizations.dart';
import '../models/post.dart';
import '../models/relationship_status.dart';
import '../models/user_profile.dart';
import '../providers/auth_provider.dart';
import '../services/dm_service.dart';
import '../services/feature_flag_service.dart';
import '../services/post_service.dart';
import '../services/profile_grid_adapter_service.dart';
import '../services/relationship_service.dart';
import '../widgets/highlight_reels.dart';
import '../widgets/post_grid.dart';
import '../widgets/profile_action_buttons.dart';
import '../widgets/profile_header.dart';
import 'account_settings_screen.dart';
import 'dm_chat_screen.dart';
import 'post_detail_screen.dart';
import 'profile_edit_screen.dart';
import 'requests_page.dart';
import '../utils/logger.dart';

class ProfileGridScreen extends StatefulWidget {
  final String? userId; // null이면 현재 사용자 프로필

  const ProfileGridScreen({
    Key? key,
    this.userId,
  }) : super(key: key);

  @override
  State<ProfileGridScreen> createState() => _ProfileGridScreenState();
}

class _ProfileGridScreenState extends State<ProfileGridScreen>
    with TickerProviderStateMixin {
  final ProfileDataAdapter _profileAdapter = ProfileDataAdapter();
  final RelationshipService _relationshipService = RelationshipService();
  final DMService _dmService = DMService();
  final PostService _postService = PostService();

  UserProfile? _userProfile;
  Map<String, int> _stats = {};
  List<HighlightItem> _highlights = [];
  PostDisplayMode _displayMode = PostDisplayMode.grid;

  bool _isLoading = true;
  bool _isOwnProfile = false;
  RelationshipStatus _relationshipStatus = RelationshipStatus.none;
  bool _isFollowActionInProgress = false;
  bool _isMessageOpening = false;
  bool _isShareProcessing = false;
  bool _isPostLoading = false;

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
    if (!FeatureFlagService()
        .isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      // Feature가 비활성화된 경우 기존 프로필 화면으로 이동
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacementNamed(context, '/mypage');
      });
    }
  }

  /// 프로필 데이터 로드
  Future<void> _loadProfileData() async {
    Trace? profileTrace;
    try {
      profileTrace = FirebasePerformance.instance.newTrace('profile_grid_load');
      await profileTrace.start();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ profile_grid_load trace start 실패: $e');
      }
    }

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
      RelationshipStatus relationshipStatus = RelationshipStatus.none;
      bool hasPendingOut = false;
      bool hasIncoming = false;
      if (!_isOwnProfile && currentUserId != null) {
        relationshipStatus =
            await _relationshipService.getRelationshipStatus(targetUserId);
        hasPendingOut = relationshipStatus == RelationshipStatus.pendingOut;
        hasIncoming = relationshipStatus == RelationshipStatus.pendingIn;
      }

      // 하이라이트 데이터 로드 (임시 데이터)
      final highlights = _loadHighlights();

      setState(() {
        _userProfile = profile;
        _stats = stats;
        _relationshipStatus = relationshipStatus;
        _highlights = highlights;
        _isLoading = false;
      });
    } catch (e) {
      Logger.error('프로필 데이터 로드 오류: $e');
      setState(() {
        _isLoading = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  '${AppLocalizations.of(context)!.cannotLoadProfile}: $e')),
        );
      }
    } finally {
      if (profileTrace != null) {
        try {
          await profileTrace.stop();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ profile_grid_load trace stop 실패: $e');
          }
        }
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

  Future<void> _refreshRelationshipStatus(String targetUserId) async {
    if (_isOwnProfile) return;
    try {
      final status =
          await _relationshipService.getRelationshipStatus(targetUserId);
      if (!mounted) return;
      setState(() {
        _relationshipStatus = status;
      });
    } catch (e) {
      Logger.error('관계 상태 갱신 오류: $e');
    }
  }

  ({String label, IconData icon, bool isPrimary, bool enabled})
      _relationshipButtonConfig(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    switch (_relationshipStatus) {
      case RelationshipStatus.none:
        return (
          label: loc.friendRequest,
          icon: Icons.person_add_outlined,
          isPrimary: true,
          enabled: true,
        );
      case RelationshipStatus.pendingOut:
        return (
          label: loc.cancelFriendRequest,
          icon: Icons.cancel_outlined,
          isPrimary: false,
          enabled: true,
        );
      case RelationshipStatus.pendingIn:
        return (
          label: isKo ? '요청 확인' : 'Review Requests',
          icon: Icons.inbox_outlined,
          isPrimary: true,
          enabled: true,
        );
      case RelationshipStatus.friends:
        return (
          label: loc.removeFriendAction,
          icon: Icons.person_remove_outlined,
          isPrimary: false,
          enabled: true,
        );
      case RelationshipStatus.blocked:
        return (
          label: loc.unblock,
          icon: Icons.lock_open_outlined,
          isPrimary: false,
          enabled: true,
        );
      case RelationshipStatus.blockedBy:
        return (
          label: isKo ? '차단됨' : 'Blocked',
          icon: Icons.block,
          isPrimary: false,
          enabled: false,
        );
    }
  }

  bool _canMessage() {
    if (_isOwnProfile) return false;
    return _relationshipStatus != RelationshipStatus.blocked &&
        _relationshipStatus != RelationshipStatus.blockedBy;
  }

  void _showSnackBar(String message, {Color? backgroundColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Feature Flag 재확인
    if (!FeatureFlagService()
        .isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.profile)),
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
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.profile)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_userProfile == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.profile)),
        body: const Center(
          child: Text(AppLocalizations.of(context)!.cannotLoadProfile),
        ),
      );
    }

    final relationshipButton = _relationshipButtonConfig(context);
    final canMessage = _canMessage();

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
                    onRelationshipAction: _handleRelationshipAction,
                    onMessage: _handleMessage,
                    relationshipActionLabel: relationshipButton.label,
                    relationshipActionIcon: relationshipButton.icon,
                    isRelationshipActionPrimary: relationshipButton.isPrimary,
                    isRelationshipActionEnabled: relationshipButton.enabled,
                    isRelationshipActionLoading: _isFollowActionInProgress,
                    canMessage: canMessage,
                    isMessageLoading: _isMessageOpening,
                  ),

                  // 액션 버튼
                  ProfileActionButtons(
                    isOwnProfile: _isOwnProfile,
                    onEditProfile: _handleEditProfile,
                    onRelationshipAction: _handleRelationshipAction,
                    onMessage: _handleMessage,
                    onShare: _handleShare,
                    onMoreActions: _handleMoreActions,
                    relationshipActionLabel: relationshipButton.label,
                    relationshipActionIcon: relationshipButton.icon,
                    isRelationshipActionPrimary: relationshipButton.isPrimary,
                    isRelationshipActionEnabled: relationshipButton.enabled,
                    isRelationshipActionLoading: _isFollowActionInProgress,
                    canMessage: canMessage,
                    isMessageLoading: _isMessageOpening,
                    isShareLoading: _isShareProcessing,
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
          userId: widget.userId ??
              Provider.of<AuthProvider>(context, listen: false).user!.uid,
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

  /// 관계 액션 처리 (친구요청, 취소, 수락, 삭제 등)
  Future<void> _handleRelationshipAction() async {
    if (_isOwnProfile || _userProfile == null || _isFollowActionInProgress)
      return;

    final targetUserId = _userProfile!.uid;
    final loc = AppLocalizations.of(context)!;

    if (_relationshipStatus == RelationshipStatus.pendingIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const RequestsPage()),
      );
      await _refreshRelationshipStatus(targetUserId);
      return;
    }

    if (_relationshipStatus == RelationshipStatus.blockedBy) {
      _showSnackBar(
        loc.blockedUser,
        backgroundColor: Theme.of(context).colorScheme.error,
      );
      return;
    }

    bool proceed = true;
    if (_relationshipStatus == RelationshipStatus.friends) {
      proceed = await _confirmAction(
        title: loc.removeFriend,
        message: loc.unfriendConfirm(_userProfile!.displayNameOrNickname),
        confirmLabel: loc.removeFriend,
      );
    } else if (_relationshipStatus == RelationshipStatus.pendingOut) {
      proceed = await _confirmAction(
        title: loc.cancelFriendRequest,
        message: loc.confirmCancelFriendRequest,
        confirmLabel: loc.cancelFriendRequest,
      );
    } else if (_relationshipStatus == RelationshipStatus.blocked) {
      proceed = await _confirmAction(
        title: loc.unblock,
        message: loc.confirmUnblock,
        confirmLabel: loc.unblock,
      );
    }

    if (!proceed) return;

    setState(() {
      _isFollowActionInProgress = true;
    });

    try {
      bool success = false;
      String successMessage = '';
      String? errorMessage;

      switch (_relationshipStatus) {
        case RelationshipStatus.none:
          success = await _relationshipService.sendFriendRequest(targetUserId);
          successMessage = loc.friendRequestSent;
          if (!success) errorMessage = loc.friendRequestFailed;
          break;
        case RelationshipStatus.pendingOut:
          success =
              await _relationshipService.cancelFriendRequest(targetUserId);
          successMessage = loc.friendRequestCancelled;
          if (!success) errorMessage = loc.friendRequestCancelFailed;
          break;
        case RelationshipStatus.friends:
          success = await _relationshipService.unfriend(targetUserId);
          successMessage = loc.unfriendSuccess;
          if (!success) errorMessage = loc.unfriendFailed;
          break;
        case RelationshipStatus.blocked:
          success = await _relationshipService.unblockUser(targetUserId);
          successMessage = loc.userUnblocked;
          if (!success) errorMessage = loc.unblockFailed;
          break;
        case RelationshipStatus.pendingIn:
        case RelationshipStatus.blockedBy:
          success = false;
          errorMessage = loc.blockedUser;
          break;
      }

      if (!mounted) return;

      if (success) {
        _showSnackBar(
          successMessage,
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
        await _refreshRelationshipStatus(targetUserId);
      } else if (errorMessage != null) {
        _showSnackBar(
          errorMessage,
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        e.toString(),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFollowActionInProgress = false;
        });
      }
    }
  }

  /// 메시지 처리
  Future<void> _handleMessage() async {
    if (_isOwnProfile ||
        _userProfile == null ||
        !_canMessage() ||
        _isMessageOpening) return;

    final targetUserId = _userProfile!.uid;
    final loc = AppLocalizations.of(context)!;

    setState(() {
      _isMessageOpening = true;
    });

    try {
      final conversationId = await _dmService.getOrCreateConversation(
        targetUserId,
        isFriend: _relationshipStatus == RelationshipStatus.friends,
      );

      if (!mounted) return;

      if (conversationId == null) {
        _showSnackBar(
          loc.cannotSendDM,
          backgroundColor: Theme.of(context).colorScheme.error,
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => DMChatScreen(
            conversationId: conversationId,
            otherUserId: targetUserId,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        isKo ? '게시글을 열 수 없습니다.' : 'Failed to open the post.',
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isMessageOpening = false;
        });
      }
    }
  }

  /// 공유 처리
  Future<void> _handleShare() async {
    if (_userProfile == null || _isShareProcessing) return;

    setState(() {
      _isShareProcessing = true;
    });

    try {
      final profileUrl = 'https://wefilling.app/profile/${_userProfile!.uid}';
      await Clipboard.setData(ClipboardData(text: profileUrl));
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      _showSnackBar(
        isKo ? '프로필 링크를 복사했습니다.' : 'Profile link copied to clipboard.',
        backgroundColor: Theme.of(context).colorScheme.primary,
      );
    } catch (e) {
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      _showSnackBar(
        isKo ? '링크를 복사할 수 없습니다.' : 'Unable to copy link.',
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isShareProcessing = false;
        });
      }
    }
  }

  Future<bool> _confirmAction({
    required String title,
    required String message,
    String? confirmLabel,
    String? cancelLabel,
  }) async {
    final loc = AppLocalizations.of(context)!;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(cancelLabel ?? loc.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel ?? loc.confirm),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  /// 더보기 액션 처리
  void _handleMoreActions() {
    final targetUid = _userProfile?.uid;

    ProfileMoreActionsSheet.show(
      context,
      isOwnProfile: _isOwnProfile,
      onBlock: (!_isOwnProfile && targetUid != null)
          ? () => _handleBlockAction(targetUid)
          : null,
      onReport: (!_isOwnProfile && targetUid != null)
          ? () => _handleReport(targetUid)
          : null,
      onCopyLink: () => _handleShare(),
      onSettings: _isOwnProfile ? _openAccountSettings : null,
    );
  }

  Future<void> _handleBlockAction(String targetUserId) async {
    final loc = AppLocalizations.of(context)!;
    final isBlocked = _relationshipStatus == RelationshipStatus.blocked;

    final confirmed = await _confirmAction(
      title: isBlocked ? loc.unblock : loc.blockUser,
      message: isBlocked
          ? loc.confirmUnblock
          : loc.blockUserConfirm(_userProfile?.displayNameOrNickname ?? ''),
      confirmLabel: isBlocked ? loc.unblock : loc.block,
    );

    if (!confirmed) return;

    setState(() {
      _isFollowActionInProgress = true;
    });

    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final blockFailed = isKo ? '사용자를 차단하지 못했습니다.' : 'Failed to block user.';

    try {
      bool success;
      String successMessage;
      String failureMessage;

      if (isBlocked) {
        success = await _relationshipService.unblockUser(targetUserId);
        successMessage = loc.userUnblocked;
        failureMessage = loc.unblockFailed;
      } else {
        success = await _relationshipService.blockUser(targetUserId);
        successMessage = loc.userBlockedSuccess;
        failureMessage = blockFailed;
      }

      if (!mounted) return;

      if (success) {
        _showSnackBar(
          successMessage,
          backgroundColor: Theme.of(context).colorScheme.primary,
        );
        await _refreshRelationshipStatus(targetUserId);
      } else {
        _showSnackBar(
          failureMessage,
          backgroundColor: Theme.of(context).colorScheme.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        e.toString(),
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFollowActionInProgress = false;
        });
      }
    }
  }

  Future<void> _handleReport(String targetUserId) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await _confirmAction(
      title: loc.report,
      message: Localizations.localeOf(context).languageCode == 'ko'
          ? '해당 사용자에 대한 신고 내용을 운영팀에 전달하시겠습니까?'
          : 'Do you want to submit a report about this user to the support team?',
      confirmLabel: loc.reportAction,
    );

    if (!confirmed) return;

    // 실제 신고 로직은 서버 연동 시 구현 (현재는 사용자 피드백 제공)
    _showSnackBar(
      loc.reportSubmitted,
      backgroundColor: Colors.orange,
    );
  }

  void _openAccountSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AccountSettingsScreen(),
      ),
    );
  }

  /// 하이라이트 탭 처리
  void _handleHighlightTap(HighlightItem highlight) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              highlight.title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Text(
              Localizations.localeOf(context).languageCode == 'ko'
                  ? '곧 하이라이트 전용 뷰가 추가될 예정입니다. 현재는 임시로 기본 정보를 보여드리고 있습니다.'
                  : 'A dedicated highlight view is coming soon. For now, basic information is shown as a preview.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(AppLocalizations.of(context)!.confirm),
                ),
              ],
            ),
          ],
        ),
      ),
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
              backgroundColor: Colors
                  .primaries[_highlights.length % Colors.primaries.length],
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
  Future<void> _handlePostTap(ProfilePost post) async {
    if (_isPostLoading) return;

    setState(() {
      _isPostLoading = true;
    });

    final loc = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    try {
      final fullPost = await _postService.getPostById(post.postId);

      if (!mounted) return;

      if (fullPost == null) {
        _showSnackBar(
          isKo ? '게시글을 불러올 수 없습니다.' : 'Unable to load the post.',
          backgroundColor: Theme.of(context).colorScheme.error,
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PostDetailScreen(post: fullPost),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackBar(
        loc.dmNotAvailable,
        backgroundColor: Theme.of(context).colorScheme.error,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPostLoading = false;
        });
      }
    }
  }
}
