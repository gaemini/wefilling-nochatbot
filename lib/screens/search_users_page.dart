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
import '../l10n/app_localizations.dart';

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
    if (_isInitialized || !mounted) return;

    final provider = context.read<RelationshipProvider>();
    await provider.initialize();

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  /// 사용자 검색
  void _searchUsers(String query) {
    if (!mounted) return;
    
    if (query.trim().isEmpty) {
      context.read<RelationshipProvider>().clearSearchResults();
      return;
    }

    _debouncer.run(() {
      if (mounted) {
        context.read<RelationshipProvider>().searchUsers(query);
      }
    });
  }

  /// 친구요청 보내기
  Future<void> _sendFriendRequest(String toUid) async {
    if (!mounted) return;
    
    final provider = context.read<RelationshipProvider>();
    final success = await provider.sendFriendRequest(toUid);
    
    if (!mounted) return;
    
    final l10n = AppLocalizations.of(context);

    if (success) {
      _showSnackBar(l10n?.friendRequestSent ?? "", Colors.green);
    } else {
      // Provider의 구체적인 오류 메시지 표시
      final errorMessage = provider.errorMessage ?? l10n?.friendRequestFailed ?? "";
      _showSnackBar(errorMessage, Colors.red);
    }
  }

  /// 친구요청 취소
  Future<void> _cancelFriendRequest(String toUid) async {
    if (!mounted) return;
    
    final provider = context.read<RelationshipProvider>();
    final success = await provider.cancelFriendRequest(toUid);
    
    if (!mounted) return;
    
    final l10n = AppLocalizations.of(context);

    if (success) {
      _showSnackBar(l10n?.friendRequestCancelled ?? "", Colors.orange);
    } else {
      _showSnackBar(l10n?.friendRequestCancelFailed ?? "", Colors.red);
    }
  }

  /// 친구 삭제
  Future<void> _unfriend(String otherUid) async {
    if (!mounted) return;
    
    final l10n = AppLocalizations.of(context);
    final confirmed = await _showConfirmDialog(
      l10n?.removeFriend ?? "",
      l10n?.confirmUnfriend ?? "",
    );

    if (confirmed && mounted) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.unfriend(otherUid);

      if (mounted) {
        if (success) {
          _showSnackBar(l10n?.unfriendedUser ?? "", Colors.orange);
        } else {
          _showSnackBar(l10n?.unfriendFailed ?? "", Colors.red);
        }
      }
    }
  }

  // 사용자 차단 기능 - 현재 미사용
  // Future<void> _blockUser(String targetUid) async {
  //   if (!mounted) return;
  //   
  //   final l10n = AppLocalizations.of(context);
  //   final confirmed = await _showConfirmDialog(
  //     l10n?.blockUser ?? "",
  //     l10n?.blockUserDescription ?? "",
  //   );

  //   if (confirmed && mounted) {
  //     final provider = context.read<RelationshipProvider>();
  //     final success = await provider.blockUser(targetUid);

  //     if (mounted) {
  //       if (success) {
  //         _showSnackBar(l10n?.userBlocked ?? "", Colors.red);
  //       } else {
  //         _showSnackBar(l10n?.userBlockFailed ?? "", Colors.red);
  //       }
  //     }
  //   }
  // }

  /// 사용자 차단 해제
  Future<void> _unblockUser(String targetUid) async {
    if (!mounted) return;
    
    final l10n = AppLocalizations.of(context);
    final confirmed = await _showConfirmDialog(
      l10n?.unblockUser ?? "",
      l10n?.confirmUnblock ?? "",
    );

    if (confirmed && mounted) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.unblockUser(targetUid);

      if (mounted) {
        if (success) {
          _showSnackBar(l10n?.userUnblocked ?? "", Colors.green);
        } else {
          _showSnackBar(l10n?.unblockFailed ?? "", Colors.red);
        }
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
    final l10n = AppLocalizations.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(l10n?.cancel ?? ""),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Text(l10n?.confirm ?? ""),
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
      child: GestureDetector(
        onTap: () {
          // 빈 공간 터치시 키보드 닫기
          FocusScope.of(context).unfocus();
        },
        child: Column(
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
                  return Center(
                    child: _buildEmptyState(),
                  );
                }

                if (provider.searchResults.isEmpty) {
                  return SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: _buildNoResultsState(),
                    ),
                  );
                }

                return _buildSearchResults(provider);
              },
            ),
          ),
          ],
        ),
      ),
    );
  }

  /// 검색바 위젯
  Widget _buildSearchBar() {
    return Container(
      height: 60, // Requests 페이지와 동일한 높이로 통일
      padding: const EdgeInsets.all(12), // 패딩 축소
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
          hintText: AppLocalizations.of(context)!.enterSearchQuery,
          prefixIcon: const Icon(Icons.search),
          suffixIcon:
              _searchController.text.isNotEmpty
                  ? AppIconButton(
                    icon: Icons.clear,
                    onPressed: () {
                      _searchController.clear();
                      context.read<RelationshipProvider>().clearSearchResults();
                    },
                    semanticLabel: AppLocalizations.of(context)!.clearSearchQuery,
                    tooltip: AppLocalizations.of(context)!.close,
                  )
                  : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.grey[100],
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, // 패딩 축소 (20 → 16)
            vertical: 8, // 패딩 축소 (16 → 8)
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
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.search, size: 64, color: Colors.grey[400]),
        const SizedBox(height: 16),
        Text(
          AppLocalizations.of(context)!.searchUsers,
          style: TextStyle(
            fontSize: 18,
            color: Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          AppLocalizations.of(context)!.searchByNicknameOrName,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[500]),
        ),
      ],
    );
  }

  /// 검색 결과 없음 상태 위젯
  Widget _buildNoResultsState() {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.person_off, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            l10n?.noResultsFound ?? "",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n?.tryDifferentSearch ?? "",
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 에러 상태 위젯
  Widget _buildErrorState(String errorMessage) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
          const SizedBox(height: 16),
          Text(
            l10n?.error ?? "",
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
            child: Text(l10n?.retryAction ?? ""),
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
