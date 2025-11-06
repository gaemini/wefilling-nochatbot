// lib/screens/blocked_users_screen.dart
// 차단된 사용자 목록 관리 화면

import 'package:flutter/material.dart';
import '../models/report.dart';
import '../l10n/app_localizations.dart';
import '../services/report_service.dart';
import '../services/auth_service.dart';
import '../design/tokens.dart';
import '../ui/widgets/empty_state.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<BlockedUser> _blockedUsers = [];
  Map<String, Map<String, dynamic>> _userProfiles = {};
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final blockedUsers = await ReportService.getBlockedUsers();
      
      // 사용자 프로필 정보 가져오기
      Map<String, Map<String, dynamic>> profiles = {};
      for (final blockedUser in blockedUsers) {
        try {
          final profile = await _authService.getUserProfile();
          if (profile != null) {
            profiles[blockedUser.blockedUserId] = profile;
          }
        } catch (e) {
          print('프로필 로딩 실패: ${blockedUser.blockedUserId}');
        }
      }

      setState(() {
        _blockedUsers = blockedUsers;
        _userProfiles = profiles;
        _isLoading = false;
        _hasError = false;
      });
    } catch (e) {
      print('❌ 차단 목록 조회 실패: $e');
      
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      final errorMsg = isKo
          ? '차단 목록을 불러오는데 실패했습니다.\n잠시 후 다시 시도해주세요.'
          : 'Failed to load blocked users.\nPlease try again later.';
      
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = errorMsg;
      });
    }
  }

  Future<void> _unblockUser(BlockedUser blockedUser) async {
    final confirmed = await _showUnblockConfirmDialog(
      _getUserName(blockedUser.blockedUserId),
    );
    
    if (!confirmed) return;

    try {
      final success = await ReportService.unblockUser(blockedUser.blockedUserId);
      
      if (success) {
        setState(() {
          _blockedUsers.removeWhere((user) => user.id == blockedUser.id);
          _userProfiles.remove(blockedUser.blockedUserId);
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_getUserName(blockedUser.blockedUserId)} 사용자의 차단을 해제했습니다.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('차단 해제에 실패했습니다.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('차단 해제 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('차단 해제 중 오류가 발생했습니다.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showUnblockConfirmDialog(String userName) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('차단 해제'),
        content: Text('$userName 사용자의 차단을 해제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: BrandColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('해제'),
          ),
        ],
      ),
    ) ?? false;
  }

  String _getUserName(String userId) {
    final profile = _userProfiles[userId];
    return profile?['nickname'] ?? profile?['displayName'] ?? '알 수 없는 사용자';
  }

  String _getFormattedDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)?.blockList),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        titleTextStyle: theme.textTheme.titleLarge?.copyWith(
          color: theme.colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
              ? _buildErrorState()
              : _blockedUsers.isEmpty
                  ? _buildEmptyState()
                  : _buildBlockedUsersList(),
    );
  }

  Widget _buildErrorState() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: Colors.red.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              isKo ? '오류가 발생했습니다' : 'An error occurred',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadBlockedUsers,
              icon: const Icon(Icons.refresh),
              label: Text(isKo ? '다시 시도' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: BrandColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return AppEmptyState(
      icon: Icons.block,
      title: isKo ? '차단한 사용자가 없습니다' : 'No blocked users',
      description: isKo ? '차단한 사용자가 있으면 여기에 표시됩니다.' : 'Blocked users will appear here.',
    );
  }

  Widget _buildBlockedUsersList() {
    return RefreshIndicator(
      onRefresh: _loadBlockedUsers,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _blockedUsers.length,
        separatorBuilder: (context, index) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final blockedUser = _blockedUsers[index];
          return _buildBlockedUserCard(blockedUser);
        },
      ),
    );
  }

  Widget _buildBlockedUserCard(BlockedUser blockedUser) {
    final theme = Theme.of(context);
    final userName = _getUserName(blockedUser.blockedUserId);
    final profile = _userProfiles[blockedUser.blockedUserId];
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 사용자 아바타
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant,
                shape: BoxShape.circle,
              ),
              child: profile?['photoURL'] != null
                  ? ClipOval(
                      child: Image.network(
                        profile!['photoURL'],
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.person,
                            size: 24,
                            color: theme.colorScheme.onSurfaceVariant,
                          );
                        },
                      ),
                    )
                  : Icon(
                      Icons.person,
                      size: 24,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
            ),
            
            const SizedBox(width: 12),
            
            // 사용자 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_getFormattedDate(blockedUser.createdAt)}에 차단',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            
            // 차단 해제 버튼
            TextButton(
              onPressed: () => _unblockUser(blockedUser),
              style: TextButton.styleFrom(
                foregroundColor: BrandColors.primary,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
              child: const Text(
                '차단 해제',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
