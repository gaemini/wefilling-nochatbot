// lib/screens/search_users_page.dart
// 사용자 검색 화면
// 친구 추가, 요청 취소, 친구 삭제, 차단 등의 액션 제공

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../models/user_profile.dart';
import '../models/relationship_status.dart';
import '../widgets/user_tile.dart';
import '../ui/widgets/app_icon_button.dart';

class SearchUsersPage extends StatefulWidget {
  const SearchUsersPage({super.key});

  @override
  State<SearchUsersPage> createState() => _SearchUsersPageState();
}

class _SearchUsersPageState extends State<SearchUsersPage> {
  final TextEditingController _searchController = TextEditingController();
  final Debouncer _debouncer = Debouncer(milliseconds: 500);
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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

  /// 사용자 검색
  void _searchUsers(String query) {
    if (query.trim().isEmpty) {
      context.read<RelationshipProvider>().clearSearchResults();
      return;
    }

    _debouncer.run(() {
      context.read<RelationshipProvider>().searchUsers(query);
    });
  }

  /// 친구요청 보내기
  Future<void> _sendFriendRequest(String toUid) async {
    final provider = context.read<RelationshipProvider>();
    final success = await provider.sendFriendRequest(toUid);

    if (success) {
      _showSnackBar('친구요청을 보냈습니다.', Colors.green);
    } else {
      _showSnackBar('친구요청 전송에 실패했습니다.', Colors.red);
    }
  }

  /// 친구요청 취소
  Future<void> _cancelFriendRequest(String toUid) async {
    final provider = context.read<RelationshipProvider>();
    final success = await provider.cancelFriendRequest(toUid);

    if (success) {
      _showSnackBar('친구요청을 취소했습니다.', Colors.orange);
    } else {
      _showSnackBar('친구요청 취소에 실패했습니다.', Colors.red);
    }
  }

  /// 친구 삭제
  Future<void> _unfriend(String otherUid) async {
    final confirmed = await _showConfirmDialog(
      '친구 삭제',
      '정말로 이 사용자를 친구에서 삭제하시겠습니까?',
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.unfriend(otherUid);

      if (success) {
        _showSnackBar('친구를 삭제했습니다.', Colors.red);
      } else {
        _showSnackBar('친구 삭제에 실패했습니다.', Colors.red);
      }
    }
  }

  /// 사용자 차단
  Future<void> _blockUser(String targetUid) async {
    final confirmed = await _showConfirmDialog(
      '사용자 차단',
      '정말로 이 사용자를 차단하시겠습니까?\n차단된 사용자는 더 이상 친구요청을 보낼 수 없습니다.',
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.blockUser(targetUid);

      if (success) {
        _showSnackBar('사용자를 차단했습니다.', Colors.red);
      } else {
        _showSnackBar('사용자 차단에 실패했습니다.', Colors.red);
      }
    }
  }

  /// 사용자 차단 해제
  Future<void> _unblockUser(String targetUid) async {
    final confirmed = await _showConfirmDialog(
      '차단 해제',
      '정말로 이 사용자의 차단을 해제하시겠습니까?',
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.unblockUser(targetUid);

      if (success) {
        _showSnackBar('사용자 차단을 해제했습니다.', Colors.green);
      } else {
        _showSnackBar('차단 해제에 실패했습니다.', Colors.red);
      }
    }
  }

  /// 액션 버튼 처리
  void _handleAction(UserProfile user, RelationshipStatus status) {
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
        // 이 상태에서는 액션 불가
        break;
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
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: const Text('확인'),
              ),
            ],
          ),
    );

    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 검색바
        _buildSearchBar(),

        // 검색 결과 또는 안내 메시지
        Expanded(
          child: Consumer<RelationshipProvider>(
            builder: (context, provider, child) {
              if (!_isInitialized) {
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.errorMessage != null) {
                return _buildErrorState(provider.errorMessage!);
              }

              if (_searchController.text.trim().isEmpty) {
                return _buildEmptyState();
              }

              if (provider.searchResults.isEmpty) {
                return _buildNoResultsState();
              }

              return _buildSearchResults(provider);
            },
          ),
        ),
      ],
    );
  }

  /// 검색바 위젯
  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '닉네임 또는 이름으로 검색',
          prefixIcon: const Icon(Icons.search),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? AppIconButton(
                    icon: Icons.clear,
                    onPressed: () {
                      _searchController.clear();
                      context.read<RelationshipProvider>().clearSearchResults();
                    },
                    semanticLabel: '검색어 지우기',
                    tooltip: '지우기',
                  )
                  : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
        onChanged: _searchUsers,
        textInputAction: TextInputAction.search,
      ),
    );
  }

  /// 검색 결과 목록
  Widget _buildSearchResults(RelationshipProvider provider) {
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8),
      itemCount: provider.searchResults.length,
      itemBuilder: (context, index) {
        final user = provider.searchResults[index];
        final status = provider.getRelationshipStatus(user.uid);

        return UserTile(
          user: user,
          relationshipStatus: status,
          onActionPressed: () => _handleAction(user, status),
          onTilePressed: () {
            // 사용자 프로필 화면으로 이동 (나중에 구현)
            // Navigator.push(context, MaterialPageRoute(
            //   builder: (context) => UserProfilePage(user: user),
            // ));
          },
        );
      },
    );
  }

  /// 빈 상태 위젯
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '사용자를 검색해보세요',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '닉네임이나 이름으로 검색하여\n새로운 친구를 찾아보세요',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 검색 결과 없음 상태 위젯
  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '검색 결과가 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '다른 검색어를 시도해보세요',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 에러 상태 위젯
  Widget _buildErrorState(String errorMessage) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            '오류가 발생했습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.red[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.red[500]),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              context.read<RelationshipProvider>().clearError();
            },
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

/// 디바운서 클래스 (검색 입력 지연 처리)
class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }
}
