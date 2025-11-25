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
        _showSnackBar(AppLocalizations.of(context)!.friendRequestAccepted, Colors.green);
      } else {
        _showSnackBar(AppLocalizations.of(context)!.friendRequestAcceptFailed, Colors.red);
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
          _showSnackBar(AppLocalizations.of(context)!.friendRequestRejected, Colors.orange);
        } else {
          _showSnackBar(AppLocalizations.of(context)!.friendRequestRejectFailed, Colors.red);
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
          _showSnackBar(AppLocalizations.of(context)!.friendRequestCancelledSuccess, Colors.orange);
        } else {
          _showSnackBar(AppLocalizations.of(context)!.friendRequestCancelFailed, Colors.red);
        }
      }
    }
  }

  /// 스낵바 표시
  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 확인 다이얼로그 표시
  Future<bool> _showConfirmDialog(String title, String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(AppLocalizations.of(context)!.cancel ?? ""),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: Text(AppLocalizations.of(context)!.confirm ?? ""),
              ),
            ],
          ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEBEBEB), // 게시판과 동일한 회색 배경
      child: !_isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
              // 헤더 영역 (높이 통일 - 검색창과 동일)
              Container(
                height: 60, // 검색 탭과 동일한 높이
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12), // TabBar 높이 48에 맞춤
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.blue,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.blue,
                  indicatorWeight: 2.0,
                  dividerColor: Colors.transparent, // TabBar 하단 구분선 제거
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                  tabs: [
                    Tab(text: AppLocalizations.of(context)!.receivedRequests),
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
    );
  }

  /// 받은 요청 탭
  Widget _buildIncomingRequestsTab() {
    return Consumer<RelationshipProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
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

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: provider.incomingRequests.length,
          itemBuilder: (context, index) {
            final request = provider.incomingRequests[index];
            return FutureBuilder<UserProfile?>(
              future: provider.getUserProfile(request.fromUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: CircularProgressIndicator()),
                      title: Text(AppLocalizations.of(context)!.loading ?? ""),
                    ),
                  );
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
          return const Center(child: CircularProgressIndicator());
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

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: provider.outgoingRequests.length,
          itemBuilder: (context, index) {
            final request = provider.outgoingRequests[index];
            return FutureBuilder<UserProfile?>(
              future: provider.getUserProfile(request.toUid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: CircularProgressIndicator()),
                      title: Text(AppLocalizations.of(context)!.loading ?? ""),
                    ),
                  );
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: DesignTokens.radiusM,
        border: Border.all(color: BrandColors.neutral200, width: 1),
        boxShadow: DesignTokens.shadowLight,
      ),
      child: Padding(
        padding: DesignTokens.paddingS,
        child: Row(
          children: [
            // 프로필 이미지
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BrandColors.neutral200,
              ),
              child: user.hasProfileImage
                  ? ClipOval(
                      child: Image.network(
                        user.photoURL!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.person_outline,
                          size: 24,
                          color: BrandColors.textTertiary,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.person_outline,
                      size: 24,
                      color: BrandColors.textTertiary,
                    ),
            ),

            const SizedBox(width: 16),

            // 사용자 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayNameOrNickname,
                    style: TypographyStyles.titleMedium.copyWith(
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getTimeAgo(request.createdAt),
                    style: TypographyStyles.bodySmall.copyWith(
                      color: BrandColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // 액션 버튼들 (가로 배치)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 수락 버튼
                ElevatedButton(
                  onPressed: () => _acceptRequest(request.fromUid),
                  style: ComponentStyles.primaryButton.copyWith(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    minimumSize: WidgetStateProperty.all(const Size(60, 36)),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.accept,
                    style: TypographyStyles.labelMedium.copyWith(
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 거절 버튼
                OutlinedButton(
                  onPressed: () => _rejectRequest(request.fromUid),
                  style: ComponentStyles.secondaryButton.copyWith(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    minimumSize: WidgetStateProperty.all(const Size(60, 36)),
                  ),
                  child: Text(
                    AppLocalizations.of(context)!.reject,
                    style: TypographyStyles.labelMedium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 보낸 요청 타일
  Widget _buildOutgoingRequestTile(FriendRequest request, UserProfile user) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: DesignTokens.radiusM,
        border: Border.all(color: BrandColors.neutral200, width: 1),
        boxShadow: DesignTokens.shadowLight,
      ),
      child: Padding(
        padding: DesignTokens.paddingS,
        child: Row(
          children: [
            // 프로필 이미지
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: BrandColors.neutral200,
              ),
              child: user.hasProfileImage
                  ? ClipOval(
                      child: Image.network(
                        user.photoURL!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.person_outline,
                          size: 24,
                          color: BrandColors.textTertiary,
                        ),
                      ),
                    )
                  : Icon(
                      Icons.person_outline,
                      size: 24,
                      color: BrandColors.textTertiary,
                    ),
            ),

            const SizedBox(width: 16),

            // 사용자 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayNameOrNickname,
                    style: TypographyStyles.titleMedium.copyWith(
                      fontSize: 15,
                    ),
                  ),
                  if (user.nickname != null &&
                      user.nickname != user.displayName &&
                      user.nickname!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      user.displayName,
                      style: TypographyStyles.bodySmall.copyWith(
                        color: BrandColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    _getTimeAgo(request.createdAt),
                    style: TypographyStyles.bodySmall.copyWith(
                      color: BrandColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),

            // 취소 버튼
            OutlinedButton(
              onPressed: () => _cancelRequest(request.toUid),
              style: OutlinedButton.styleFrom(
                foregroundColor: BrandColors.warning,
                side: BorderSide(color: BrandColors.warning),
                minimumSize: const Size(60, 36),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: DesignTokens.radiusM,
                ),
              ),
              child: Text(
                AppLocalizations.of(context)!.cancelAction,
                style: TypographyStyles.labelMedium.copyWith(
                  color: BrandColors.warning,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 빈 상태 위젯
  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Padding(
        padding: DesignTokens.paddingL,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: BrandColors.neutral100,
                borderRadius: DesignTokens.radiusL,
              ),
              child: Icon(
                icon,
                size: 40,
                color: BrandColors.textTertiary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: TypographyStyles.headlineMedium.copyWith(
                color: BrandColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TypographyStyles.bodyMedium.copyWith(
                color: BrandColors.textTertiary,
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
        padding: DesignTokens.paddingL,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: BrandColors.error.withOpacity(0.1),
                borderRadius: DesignTokens.radiusL,
              ),
              child: Icon(
                Icons.error_outline,
                size: 40,
                color: BrandColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.error,
              style: TypographyStyles.headlineMedium.copyWith(
                color: BrandColors.error,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TypographyStyles.bodyMedium.copyWith(
                color: BrandColors.error,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                context.read<RelationshipProvider>().clearError();
              },
              style: ComponentStyles.primaryButton,
              child: Text(AppLocalizations.of(context)!.retryAction ?? ""),
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
