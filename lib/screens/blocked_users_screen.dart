// lib/screens/blocked_users_screen.dart
// 차단된 사용자 목록 관리 화면

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/report.dart';
import '../l10n/app_localizations.dart';
import '../services/report_service.dart';
import '../services/auth_service.dart';
import '../design/tokens.dart';
import '../ui/widgets/empty_state.dart';
import '../utils/logger.dart';
import '../l10n/ui_locale.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<BlockedUser> _blockedUsers = [];
  List<AnonymousBlockedPost> _blockedAnonymousPosts = [];
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
    final chineseUiAtStart = isChineseUi(context);
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final results = await Future.wait([
        ReportService.getBlockedUsers(),
        ReportService.getBlockedAnonymousPosts(),
      ]);
      final blockedUsers = results[0] as List<BlockedUser>;
      final blockedAnonymousPosts = results[1] as List<AnonymousBlockedPost>;
      
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
        _blockedAnonymousPosts = blockedAnonymousPosts;
        _userProfiles = profiles;
        _isLoading = false;
        _hasError = false;
      });
    } catch (e) {
      Logger.error('❌ 차단 목록 조회 실패: $e');
      
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      final errorMsg = (chineseUiAtStart ? '屏蔽列表加载失败。\n请稍后重试。' : isKo
          ? '차단 목록을 불러오는데 실패했습니다.\n잠시 후 다시 시도해주세요.'
          : 'Failed to load blocked users.\nPlease try again later.');
      
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = errorMsg;
        _blockedAnonymousPosts = [];
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
          final isKo = Localizations.localeOf(context).languageCode == 'ko';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (isChineseUi(context) ? '已取消拉黑${_getUserName(blockedUser.blockedUserId)}。' : isKo
                    ? '${_getUserName(blockedUser.blockedUserId)} 사용자의 차단을 해제했습니다.'
                    : 'Unblocked ${_getUserName(blockedUser.blockedUserId)}.'),
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
              content: Text((isChineseUi(context) ? '取消拉黑失败。' : isKo ? '차단 해제에 실패했습니다.' : 'Failed to unblock user.')),
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
            content: Text((isChineseUi(context) ? '取消拉黑时出错。' : isKo ? '차단 해제 중 오류가 발생했습니다.' : 'An error occurred while unblocking.')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _unblockAnonymousPost(AnonymousBlockedPost blockedPost) async {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text((isChineseUi(context) ? '取消屏蔽匿名动态' : isKo ? '익명 게시글 차단 해제' : 'Unblock anonymous post')),
            content: Text(
              (isChineseUi(context) ? '要取消屏蔽这条匿名动态吗？' : isKo
                  ? '이 익명 게시글 차단을 해제하시겠습니까?'
                  : 'Do you want to unblock this anonymous post?'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text((isChineseUi(context) ? '取消' : isKo ? '취소' : 'Cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text((isChineseUi(context) ? '取消屏蔽' : isKo ? '해제' : 'Unblock')),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final success = await ReportService.unblockAnonymousPost(blockedPost.postId);
    if (!mounted) return;

    if (success) {
      setState(() {
        _blockedAnonymousPosts.removeWhere((e) => e.id == blockedPost.id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (isChineseUi(context) ? '已取消屏蔽匿名动态。' : isKo
                ? '익명 게시글 차단을 해제했습니다.'
                : 'Anonymous post unblocked.'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (isChineseUi(context) ? '取消屏蔽匿名动态失败。' : isKo
                ? '익명 게시글 차단 해제에 실패했습니다.'
                : 'Failed to unblock anonymous post.'),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<bool> _showUnblockConfirmDialog(String userName) async {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          (isChineseUi(context) ? '取消拉黑' : isKo ? '차단 해제' : 'Unblock User'),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
            fontWeight: FontWeight.w600,
          ),
        ),
        content: Text(
          (isChineseUi(context) ? '要取消拉黑${userName}吗？' : isKo
              ? '$userName 사용자의 차단을 해제하시겠습니까?' 
              : 'Do you want to unblock $userName?'),
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              (isChineseUi(context) ? '取消' : isKo ? '취소' : 'Cancel'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
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
              (isChineseUi(context) ? '取消屏蔽' : isKo ? '해제' : 'Unblock'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
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
    final nick = (profile?['nickname'] ?? '').toString().trim();
    if (nick.isNotEmpty) return nick;
    return (isChineseUi(context) ? '未知用户' : isKo ? '알 수 없는 사용자' : 'Unknown User');
  }

  String _getFormattedDate(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    
    if (difference.inDays > 0) {
      return (isChineseUi(context) ? '${difference.inDays}天前' : isKo ? '${difference.inDays}일 전' : '${difference.inDays}d ago');
    } else if (difference.inHours > 0) {
      return (isChineseUi(context) ? '${difference.inHours}小时前' : isKo ? '${difference.inHours}시간 전' : '${difference.inHours}h ago');
    } else if (difference.inMinutes > 0) {
      return (isChineseUi(context) ? '${difference.inMinutes}分钟前' : isKo ? '${difference.inMinutes}분 전' : '${difference.inMinutes}m ago');
    } else {
      return (isChineseUi(context) ? '刚刚' : isKo ? '방금 전' : 'Just now');
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
          style: TextStyle(
            fontFamily: uiFontFamily(context, 'Inter'),
            fontFamilyFallback: const ['NotoSansKR'],
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
              : (_blockedUsers.isEmpty && _blockedAnonymousPosts.isEmpty)
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
              (isChineseUi(context) ? '发生错误' : isKo ? '오류가 발생했습니다' : 'An error occurred'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadBlockedUsers,
              icon: const Icon(Icons.refresh),
              label: Text((isChineseUi(context) ? '重试' : isKo ? '다시 시도' : 'Retry')),
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
        title: (isChineseUi(context) ? '暂无屏蔽内容' : isKo ? '차단한 항목이 없습니다' : 'No blocked items'),
        description: (isChineseUi(context) ? '被拉黑的用户和被屏蔽的匿名动态会显示在这里。' : isKo
            ? '차단한 사용자 또는 익명 게시글이 있으면 여기에 표시됩니다.'
            : 'Blocked users or anonymous posts will appear here.'),
      ),
    );
  }

  Widget _buildBlockedUsersList() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final hasUsers = _blockedUsers.isNotEmpty;
    final hasAnonymousPosts = _blockedAnonymousPosts.isNotEmpty;

    return RefreshIndicator(
      onRefresh: _loadBlockedUsers,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          if (hasUsers) ...[
            _buildSectionTitle((isChineseUi(context) ? '已拉黑的用户' : isKo ? '사용자 차단' : 'Blocked users')),
            ..._blockedUsers.map(_buildBlockedUserCard),
            const SizedBox(height: 8),
          ],
          if (hasAnonymousPosts) ...[
            _buildSectionTitle((isChineseUi(context) ? '已屏蔽的匿名动态' : isKo ? '익명 게시글 차단' : 'Blocked anonymous posts')),
            ..._blockedAnonymousPosts.map(_buildBlockedAnonymousPostCard),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: uiFontFamily(context, 'Inter'),
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }

  Widget _buildBlockedUserCard(BlockedUser blockedUser) {
    final userName = _getUserName(blockedUser.blockedUserId);
    final profile = _userProfiles[blockedUser.blockedUserId];
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
        ),
      ),
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
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
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
                    return (isChineseUi(context) ? '已屏蔽 ${timeAgo}' : isKo ? '$timeAgo에 차단' : 'Blocked $timeAgo');
                  }(),
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
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
                return (isChineseUi(context) ? '取消屏蔽' : isKo ? '차단 해제' : 'Unblock');
              }(),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBlockedAnonymousPostCard(AnonymousBlockedPost blockedPost) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final title = (blockedPost.titleSnapshot ?? '').trim();
    final preview = (blockedPost.previewSnapshot ?? '').trim();
    final subtitle = title.isNotEmpty
        ? title
        : (preview.isNotEmpty
            ? preview
            : ((isChineseUi(context) ? '匿名动态' : isKo ? '익명 게시글' : 'Anonymous post')));

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF3F4F6), width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFF3F4F6),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.visibility_off_outlined,
              color: Color(0xFF6B7280),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (isChineseUi(context) ? '匿名动态' : isKo ? '익명 게시글' : 'Anonymous post'),
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  (isChineseUi(context) ? '已屏蔽 ${_getFormattedDate(blockedPost.createdAt)}' : isKo
                      ? '${_getFormattedDate(blockedPost.createdAt)}에 차단'
                      : 'Blocked ${_getFormattedDate(blockedPost.createdAt)}'),
                  style: TextStyle(
                    fontFamily: uiFontFamily(context, 'Inter'),
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 12,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _unblockAnonymousPost(blockedPost),
            child: Text(
              (isChineseUi(context) ? '取消屏蔽' : isKo ? '차단 해제' : 'Unblock'),
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
