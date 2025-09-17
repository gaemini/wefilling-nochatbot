// lib/screens/requests_page.dart
// 친구요청 관리 화면
// 받은 요청과 보낸 요청을 탭으로 구분하여 표시

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../models/friend_request.dart';
import '../models/user_profile.dart';
import '../widgets/user_tile.dart';

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
    final provider = context.read<RelationshipProvider>();
    final success = await provider.acceptFriendRequest(fromUid);

    if (success) {
      _showSnackBar('친구요청을 수락했습니다.', Colors.green);
    } else {
      _showSnackBar('친구요청 수락에 실패했습니다.', Colors.red);
    }
  }

  /// 친구요청 거절
  Future<void> _rejectRequest(String fromUid) async {
    final confirmed = await _showConfirmDialog(
      '친구요청 거절',
      '정말로 이 친구요청을 거절하시겠습니까?',
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.rejectFriendRequest(fromUid);

      if (success) {
        _showSnackBar('친구요청을 거절했습니다.', Colors.orange);
      } else {
        _showSnackBar('친구요청 거절에 실패했습니다.', Colors.red);
      }
    }
  }

  /// 친구요청 취소
  Future<void> _cancelRequest(String toUid) async {
    final confirmed = await _showConfirmDialog(
      '친구요청 취소',
      '정말로 이 친구요청을 취소하시겠습니까?',
    );

    if (confirmed) {
      final provider = context.read<RelationshipProvider>();
      final success = await provider.cancelFriendRequest(toUid);

      if (success) {
        _showSnackBar('친구요청을 취소했습니다.', Colors.orange);
      } else {
        _showSnackBar('친구요청 취소에 실패했습니다.', Colors.red);
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
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
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
    return !_isInitialized
        ? const Center(child: CircularProgressIndicator())
        : Column(
          children: [
            // 탭바
            Container(
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.blue,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.blue,
                tabs: const [Tab(text: '받은 요청'), Tab(text: '보낸 요청')],
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
            '받은 친구요청이 없습니다',
            '새로운 친구요청이 오면 여기에 표시됩니다',
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
                  return const Card(
                    child: ListTile(
                      leading: CircleAvatar(child: CircularProgressIndicator()),
                      title: Text('로딩 중...'),
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
            '보낸 친구요청이 없습니다',
            '사용자를 검색하여 친구요청을 보내보세요',
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
                  return const Card(
                    child: ListTile(
                      leading: CircleAvatar(child: CircularProgressIndicator()),
                      title: Text('로딩 중...'),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 프로필 이미지
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[300],
              backgroundImage:
                  user.hasProfileImage ? NetworkImage(user.photoURL!) : null,
              child:
                  !user.hasProfileImage
                      ? Text(
                        user.displayNameOrNickname.isNotEmpty
                            ? user.displayNameOrNickname[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                      : null,
            ),

            const SizedBox(width: 16),

            // 사용자 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayNameOrNickname,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (user.nickname != null &&
                      user.nickname != user.displayName &&
                      user.nickname!.isNotEmpty)
                    Text(
                      user.displayName,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _getTimeAgo(request.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),

            // 액션 버튼들
            Column(
              children: [
                ElevatedButton(
                  onPressed: () => _acceptRequest(request.fromUid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(60, 32),
                  ),
                  child: const Text('수락', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _rejectRequest(request.fromUid),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    minimumSize: const Size(60, 32),
                  ),
                  child: const Text('거절', style: TextStyle(fontSize: 12)),
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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // 프로필 이미지
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.grey[300],
              backgroundImage:
                  user.hasProfileImage ? NetworkImage(user.photoURL!) : null,
              child:
                  !user.hasProfileImage
                      ? Text(
                        user.displayNameOrNickname.isNotEmpty
                            ? user.displayNameOrNickname[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                      : null,
            ),

            const SizedBox(width: 16),

            // 사용자 정보
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.displayNameOrNickname,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (user.nickname != null &&
                      user.nickname != user.displayName &&
                      user.nickname!.isNotEmpty)
                    Text(
                      user.displayName,
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _getTimeAgo(request.createdAt),
                    style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),

            // 취소 버튼
            OutlinedButton(
              onPressed: () => _cancelRequest(request.toUid),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange,
                side: const BorderSide(color: Colors.orange),
                minimumSize: const Size(60, 32),
              ),
              child: const Text('취소', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  /// 빈 상태 위젯
  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
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

  /// 시간 경과 표시
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${dateTime.month}/${dateTime.day}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}일 전';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 전';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 전';
    } else {
      return '방금 전';
    }
  }
}
