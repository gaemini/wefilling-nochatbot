// lib/screens/requests_page.dart
// 친구요청 관리 화면
// 받은 요청과 보낸 요청을 탭으로 구분하여 표시

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../providers/auth_provider.dart';
import '../models/friend_request.dart';
import '../models/user_profile.dart';
import '../design/tokens.dart';
import '../l10n/app_localizations.dart';
import '../utils/responsive_helper.dart';

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // AuthProvider 연결
      final authProvider = context.read<AuthProvider>();
      final relationshipProvider = context.read<RelationshipProvider>();
      relationshipProvider.setAuthProvider(authProvider);

      _initializeData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 데이터 초기화
  Future<void> _initializeData() async {
    if (_isInitialized) return;

    final provider = context.read<RelationshipProvider>();
    await provider.initialize();

    setState(() {
      _isInitialized = true;
    });
  }

  /// 친구요청 수락
  Future<void> _acceptRequest(String fromUid) async {
    if (!mounted) return;

    final provider = context.read<RelationshipProvider>();
    final success = await provider.acceptFriendRequest(fromUid);

    if (mounted) {
      if (success) {
        _showSnackBar(AppLocalizations.of(context)!.friendRequestAccepted);
      } else {
        _showSnackBar(
          AppLocalizations.of(context)!.friendRequestAcceptFailed,
        );
      }
    }
  }

  /// 친구요청 거절
  Future<void> _rejectRequest(String fromUid) async {
    if (!mounted) return;

    final confirmed = await _showConfirmDialog(
      AppLocalizations.of(context)!.rejectFriendRequest,
      AppLocalizations.of(context)!.confirmRejectFriendRequest,
    );

    if (confirmed && mounted) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.rejectFriendRequest(fromUid);

      if (mounted) {
        if (success) {
          _showSnackBar(AppLocalizations.of(context)!.friendRequestRejected);
        } else {
          _showSnackBar(
            AppLocalizations.of(context)!.friendRequestRejectFailed,
          );
        }
      }
    }
  }

  /// 친구요청 취소
  Future<void> _cancelRequest(String toUid) async {
    if (!mounted) return;

    final confirmed = await _showConfirmDialog(
      AppLocalizations.of(context)!.cancelFriendRequest,
      AppLocalizations.of(context)!.confirmCancelFriendRequest,
    );

    if (confirmed && mounted) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.cancelFriendRequest(toUid);

      if (mounted) {
        if (success) {
          _showSnackBar(
            AppLocalizations.of(context)!.friendRequestCancelledSuccess,
          );
        } else {
          _showSnackBar(
            AppLocalizations.of(context)!.friendRequestCancelFailed,
          );
        }
      }
    }
  }

  /// 스낵바 표시
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 확인 다이얼로그 표시
  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF667085),
            ),
            child: Text(AppLocalizations.of(dialogContext)!.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF111827),
            ),
            child: Text(AppLocalizations.of(dialogContext)!.confirm),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: width < 360 ? 52 : 56,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          AppLocalizations.of(context)!.requests,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(18).clamp(17, 19).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Color(0xFF111827),
          ),
          iconSize: 22,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: !_isInitialized
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF667085)),
              )
            : Column(
                children: [
                  SizedBox(
                    height: width < 360 ? 46 : 48,
                    child: TabBar(
                      controller: _tabController,
                      labelColor: const Color(0xFF111827),
                      unselectedLabelColor: const Color(0xFF98A2B3),
                      indicatorColor: const Color(0xFF344054),
                      indicatorWeight: 2.0,
                      dividerColor: const Color(0xFFEAECF0),
                      indicatorSize: TabBarIndicatorSize.label,
                      labelStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                      tabs: [
                        Tab(
                            text:
                                AppLocalizations.of(context)!.receivedRequests),
                        Tab(text: AppLocalizations.of(context)!.sentRequests),
                      ],
                    ),
                  ),
                  // 탭 내용
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildIncomingRequestsTab(),
                        _buildOutgoingRequestsTab(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 받은 요청 탭
  Widget _buildIncomingRequestsTab() {
    return Consumer<RelationshipProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF667085)),
          );
        }

        if (provider.errorMessage != null) {
          return _buildErrorState(provider.errorMessage!);
        }

        if (provider.incomingRequests.isEmpty) {
          return _buildEmptyState(
            AppLocalizations.of(context)!.noReceivedRequests,
            AppLocalizations.of(context)!.newRequestsWillAppearHere,
            Icons.inbox,
          );
        }

        // 안드로이드 하단 네비게이션 바 높이 감지
        final bottomPadding = MediaQuery.of(context).padding.bottom;

        return ListView.builder(
          padding: EdgeInsets.only(
            top: 0,
            bottom: bottomPadding > 0 ? bottomPadding + 12 : 12,
          ),
          itemCount: provider.incomingRequests.length,
          itemBuilder: (context, index) {
            final request = provider.incomingRequests[index];
            return FutureBuilder<UserProfile?>(
              future: provider.getUserProfile(request.fromUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingRequestTile();
                }

                final user = snapshot.data;
                if (user == null) {
                  return const SizedBox.shrink();
                }

                return _buildIncomingRequestTile(request, user);
              },
            );
          },
        );
      },
    );
  }

  /// 보낸 요청 탭
  Widget _buildOutgoingRequestsTab() {
    return Consumer<RelationshipProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF667085)),
          );
        }

        if (provider.errorMessage != null) {
          return _buildErrorState(provider.errorMessage!);
        }

        if (provider.outgoingRequests.isEmpty) {
          return _buildEmptyState(
            AppLocalizations.of(context)!.noSentRequests,
            AppLocalizations.of(context)!.searchToSendRequest,
            Icons.send,
          );
        }

        // 안드로이드 하단 네비게이션 바 높이 감지
        final bottomPadding = MediaQuery.of(context).padding.bottom;

        return ListView.builder(
          padding: EdgeInsets.only(
            top: 0,
            bottom: bottomPadding > 0 ? bottomPadding + 12 : 12,
          ),
          itemCount: provider.outgoingRequests.length,
          itemBuilder: (context, index) {
            final request = provider.outgoingRequests[index];
            return FutureBuilder<UserProfile?>(
              future: provider.getUserProfile(request.toUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _buildLoadingRequestTile();
                }

                final user = snapshot.data;
                if (user == null) {
                  return const SizedBox.shrink();
                }

                return _buildOutgoingRequestTile(request, user);
              },
            );
          },
        );
      },
    );
  }

  /// 받은 요청 타일
  Widget _buildIncomingRequestTile(FriendRequest request, UserProfile user) {
    return _buildRequestTile(
      user: user,
      timestamp: _getTimeAgo(request.createdAt),
      actions: [
        _requestAction(
          label: AppLocalizations.of(context)!.reject,
          onPressed: () => _rejectRequest(request.fromUid),
          secondary: true,
        ),
        _requestAction(
          label: AppLocalizations.of(context)!.accept,
          onPressed: () => _acceptRequest(request.fromUid),
        ),
      ],
    );
  }

  /// 보낸 요청 타일
  Widget _buildOutgoingRequestTile(FriendRequest request, UserProfile user) {
    return _buildRequestTile(
      user: user,
      timestamp: _getTimeAgo(request.createdAt),
      actions: [
        _requestAction(
          label: AppLocalizations.of(context)!.cancelAction,
          onPressed: () => _cancelRequest(request.toUid),
          secondary: true,
        ),
      ],
    );
  }

  Widget _buildRequestTile({
    required UserProfile user,
    required String timestamp,
    required List<Widget> actions,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 360;
    final horizontalPadding = isCompact ? 12.0 : (width < 600 ? 16.0 : 24.0);
    final avatarSize = isCompact ? 40.0 : 44.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                10,
                horizontalPadding - 4,
                10,
              ),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Row(
                  children: [
                    _requestAvatar(user, avatarSize),
                    SizedBox(width: isCompact ? 10 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            user.displayNameOrNickname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: context.rf(14).clamp(13, 15).toDouble(),
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF111827),
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            timestamp,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF8B93A1),
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    Row(mainAxisSize: MainAxisSize.min, children: actions),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              indent: horizontalPadding + avatarSize + (isCompact ? 10 : 12),
              endIndent: horizontalPadding,
              color: const Color(0xFFEAECF0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _requestAvatar(UserProfile user, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: BrandColors.neutral200,
      ),
      child: user.hasProfileImage
          ? ClipOval(
              child: Image.network(
                user.photoURL!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_outline_rounded,
                  size: size * 0.5,
                  color: BrandColors.textTertiary,
                ),
              ),
            )
          : Icon(
              Icons.person_outline_rounded,
              size: size * 0.5,
              color: BrandColors.textTertiary,
            ),
    );
  }

  Widget _requestAction({
    required String label,
    required VoidCallback onPressed,
    bool secondary = false,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor:
            secondary ? const Color(0xFF667085) : const Color(0xFF111827),
        minimumSize: const Size(44, 40),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: 12,
          fontWeight: secondary ? FontWeight.w600 : FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildLoadingRequestTile() {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 12.0 : (width < 600 ? 16.0 : 24.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: 12,
          ),
          child: const Row(
            children: [
              SizedBox.square(
                dimension: 40,
                child: Center(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF667085),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 2,
                  child: LinearProgressIndicator(
                    color: Color(0xFF98A2B3),
                    backgroundColor: Color(0xFFF2F4F7),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 빈 상태 위젯
  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: const Color(0xFF98A2B3)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF98A2B3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 에러 상태 위젯
  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 34,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.error,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF344054),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                context.read<RelationshipProvider>().clearError();
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF344054),
              ),
              child: Text(AppLocalizations.of(context)!.retryAction),
            ),
          ],
        ),
      ),
    );
  }

  /// 시간 경과 표시
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final l10n = AppLocalizations.of(context);

    if (difference.inDays > 7) {
      return '${dateTime.month}/${dateTime.day}';
    } else if (difference.inDays > 0) {
      return l10n!.daysAgoCount(difference.inDays);
    } else if (difference.inHours > 0) {
      return l10n!.hoursAgoCount(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return l10n!.minutesAgoCount(difference.inMinutes);
    } else {
      return l10n?.justNowTime ?? "";
    }
  }
}
