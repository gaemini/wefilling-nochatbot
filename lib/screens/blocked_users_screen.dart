// lib/screens/blocked_users_screen.dart
// 차단된 사용자 목록 관리 화면

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/report.dart';
import '../l10n/app_localizations.dart';
import '../services/report_service.dart';
import '../services/auth_service.dart';
import '../services/content_filter_service.dart';
import '../design/tokens.dart';
import '../ui/widgets/empty_state.dart';
import '../utils/logger.dart';

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
          // 차단된 사용자의 프로필 정보를 Firestore에서 직접 가져오기
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(blockedUser.blockedUserId)
              .get();
          
          if (userDoc.exists) {
            profiles[blockedUser.blockedUserId] = userDoc.data() ?? {};
          }
        } catch (e) {
          Logger.error('프로필 로딩 실패: ${blockedUser.blockedUserId}');
        }
      }

      setState(() {
        _blockedUsers = blockedUsers;
        _userProfiles = profiles;
        _isLoading = false;
        _hasError = false;
      });
    } catch (e) {
      Logger.error('❌ 차단 목록 조회 실패: $e');
      
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
        // 캐시 즉시 갱신
        ContentFilterService.refreshCache();
        
        setState(() {
          _blockedUsers.removeWhere((user) => user.id == blockedUser.id);
          _userProfiles.remove(blockedUser.blockedUserId);
        });
        
        if (mounted) {
          final isKo = Localizations.localeOf(context).languageCode == 'ko';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                isKo 
                    ? '${_getUserName(blockedUser.blockedUserId)} 사용자의 차단을 해제했습니다.'
                    : 'Unblocked ${_getUserName(blockedUser.blockedUserId)}.',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          final isKo = Localizations.localeOf(context).languageCode == 'ko';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isKo ? '차단 해제에 실패했습니다.' : 'Failed to unblock user.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('차단 해제 실패: $e');
      if (mounted) {
        final isKo = Localizations.localeOf(context).languageCode == 'ko';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isKo ? '차단 해제 중 오류가 발생했습니다.' : 'An error occurred while unblocking.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<bool> _showUnblockConfirmDialog(String userName) async {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isKo ? '차단 해제' : 'Unblock User',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          isKo 
              ? '$userName 사용자의 차단을 해제하시겠습니까?' 
              : 'Do you want to unblock $userName?',
          style: const TextStyle(
            fontFamily: 'Pretendard',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              isKo ? '취소' : 'Cancel',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                color: Color(0xFF6B7280),
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isKo ? '해제' : 'Unblock',
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  String _getUserName(String userId) {
    final profile = _userProfiles[userId];
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return profile?['nickname'] ?? profile?['displayName'] ?? (isKo ? '알 수 없는 사용자' : 'Unknown User');
  }

  String _getFormattedDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    
    if (difference.inDays > 0) {
      return isKo ? '${difference.inDays}일 전' : '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return isKo ? '${difference.inHours}시간 전' : '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return isKo ? '${difference.inMinutes}분 전' : '${difference.inMinutes}m ago';
    } else {
      return isKo ? '방금 전' : 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          AppLocalizations.of(context)!.blockList ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: false,
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
                fontFamily: 'Pretendard',
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadBlockedUsers,
              icon: const Icon(Icons.refresh),
              label: Text(isKo ? '다시 시도' : 'Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6366F1),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Center(
      child: AppEmptyState(
        icon: Icons.block,
        title: isKo ? '차단한 사용자가 없습니다' : 'No blocked users',
        description: isKo ? '차단한 사용자가 있으면 여기에 표시됩니다.' : 'Blocked users will appear here.',
      ),
    );
  }

  Widget _buildBlockedUsersList() {
    return RefreshIndicator(
      onRefresh: _loadBlockedUsers,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _blockedUsers.length,
        separatorBuilder: (context, index) => const Divider(
          height: 1,
          thickness: 1,
          color: Color(0xFFF3F4F6),
          indent: 56,
        ),
        itemBuilder: (context, index) {
          final blockedUser = _blockedUsers[index];
          return _buildBlockedUserCard(blockedUser);
        },
      ),
    );
  }

  Widget _buildBlockedUserCard(BlockedUser blockedUser) {
    final userName = _getUserName(blockedUser.blockedUserId);
    final profile = _userProfiles[blockedUser.blockedUserId];
    
    return InkWell(
      onTap: null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
        child: Row(
          children: [
            // 사용자 아바타
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
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
                          return const Icon(
                            Icons.person,
                            size: 24,
                            color: Color(0xFF6B7280),
                          );
                        },
                      ),
                    )
                  : const Icon(
                      Icons.person,
                      size: 24,
                      color: Color(0xFF6B7280),
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
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF111827),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    () {
                      final isKo = Localizations.localeOf(context).languageCode == 'ko';
                      final timeAgo = _getFormattedDate(blockedUser.createdAt);
                      return isKo ? '$timeAgo에 차단' : 'Blocked $timeAgo';
                    }(),
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            
            // 차단 해제 버튼
            TextButton(
              onPressed: () => _unblockUser(blockedUser),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF6366F1),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                () {
                  final isKo = Localizations.localeOf(context).languageCode == 'ko';
                  return isKo ? '차단 해제' : 'Unblock';
                }(),
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
