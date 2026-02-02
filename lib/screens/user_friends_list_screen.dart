// lib/screens/user_friends_list_screen.dart
// 특정 사용자의 친구 목록 화면
// 프로필 접근 없이 목록만 표시

import 'package:flutter/material.dart';
import '../services/relationship_service.dart';
import '../models/relationship_status.dart';
import '../models/user_profile.dart';
import '../constants/app_constants.dart';
import '../widgets/country_flag_circle.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import 'friend_profile_screen.dart';

class UserFriendsListScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const UserFriendsListScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<UserFriendsListScreen> createState() => _UserFriendsListScreenState();
}

class _UserFriendsListScreenState extends State<UserFriendsListScreen> {
  final RelationshipService _relationshipService = RelationshipService();
  List<UserProfile>? _friends;
  Set<String>? _myFriendIds;
  final Set<String> _requestingIds = <String>{};
  final Set<String> _requestedIds = <String>{};
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFriends();
  }

  Future<void> _loadFriends() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final currentUserId = _relationshipService.currentUserId;

      final results = await Future.wait([
        _relationshipService.getUserFriends(widget.userId),
        currentUserId != null
            ? _relationshipService.getUserFriends(currentUserId)
            : Future.value(<UserProfile>[]),
      ]);

      final friends = (results[0] as List<UserProfile>)
          .where((u) => currentUserId == null || u.uid != currentUserId)
          .toList(growable: false);

      final myFriends = results[1] as List<UserProfile>;
      final myFriendIds = myFriends.map((u) => u.uid).toSet();

      // 비친구 목록 중 "내가 이미 요청 보낸 상태"는 버튼을 요청됨으로 고정
      final pendingOutIds = <String>{};
      if (currentUserId != null) {
        final nonFriends =
            friends.where((u) => !myFriendIds.contains(u.uid)).toList();
        if (nonFriends.isNotEmpty) {
          final statuses = await Future.wait(
            nonFriends.map(
              (u) async {
                try {
                  return await _relationshipService.getRelationshipStatus(u.uid);
                } catch (_) {
                  return RelationshipStatus.none;
                }
              },
            ),
          );
          for (var i = 0; i < nonFriends.length; i++) {
            if (statuses[i] == RelationshipStatus.pendingOut) {
              pendingOutIds.add(nonFriends[i].uid);
            }
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _friends = friends;
          _myFriendIds = myFriendIds;
          _requestedIds
            ..clear()
            ..addAll(pendingOutIds);
          _isLoading = false;
        });
        Logger.log('✅ ${widget.userName}의 친구 목록 로드: ${friends.length}명');
      }
    } catch (e) {
      Logger.error('친구 목록 로드 오류: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '친구 목록을 불러올 수 없습니다';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.userName}${AppLocalizations.of(context)!.friendsOfUser}',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: AppColors.pointColor,
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loadFriends,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.pointColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                '다시 시도',
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_friends == null || _friends!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.people_outline,
                size: 48,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.noFriendsYet,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    final myFriendIds = _myFriendIds ?? <String>{};
    final friendsGroup = _friends!
        .where((u) => myFriendIds.contains(u.uid))
        .toList(growable: false);
    final nonFriendsGroup = _friends!
        .where((u) => !myFriendIds.contains(u.uid))
        .toList(growable: false);

    final l10n = AppLocalizations.of(context)!;

    return RefreshIndicator(
      color: AppColors.pointColor,
      onRefresh: _loadFriends,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          if (friendsGroup.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: l10n.alreadyFriends,
                count: friendsGroup.length,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildFriendCard(
                  friendsGroup[index],
                  isFriend: true,
                ),
                childCount: friendsGroup.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          ],
          if (nonFriendsGroup.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: l10n.notFriends,
                count: nonFriendsGroup.length,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildFriendCard(
                  nonFriendsGroup[index],
                  isFriend: false,
                ),
                childCount: nonFriendsGroup.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _buildFriendCard(
    UserProfile friend, {
    required bool isFriend,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isRequesting = _requestingIds.contains(friend.uid);
    final isRequested = _requestedIds.contains(friend.uid);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isFriend ? () => _openProfile(friend) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE5E7EB),
                ),
                child: friend.hasProfileImage
                    ? ClipOval(
                        child: Image.network(
                          friend.photoURL!,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_outline,
                            size: 22,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      )
                    : const Icon(
                        Icons.person_outline,
                        size: 22,
                        color: Color(0xFF6B7280),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      friend.displayNameOrNickname,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (friend.nationality != null &&
                        friend.nationality!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CountryFlagCircle(
                            nationality: friend.nationality!,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              friend.nationality!,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF6B7280),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isFriend)
                const Icon(
                  Icons.chevron_right,
                  color: Color(0xFF9CA3AF),
                )
              else
                SizedBox(
                  height: 32,
                  child: OutlinedButton(
                    onPressed: (isRequesting || isRequested)
                        ? null
                        : () => _sendFriendRequest(friend),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.pointColor,
                      side: BorderSide(
                        color: (isRequesting || isRequested)
                            ? const Color(0xFFE5E7EB)
                            : AppColors.pointColor,
                      ),
                      backgroundColor: (isRequesting || isRequested)
                          ? const Color(0xFFF3F4F6)
                          : Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      elevation: 0,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isRequesting)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          const Icon(Icons.person_add_alt_1, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          isRequested ? l10n.requestPending : l10n.friendRequest,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _openProfile(UserProfile user) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: user.uid,
          nickname: user.displayNameOrNickname,
          photoURL: user.photoURL,
          email: user.email,
          university: user.university,
        ),
      ),
    );
  }

  Future<void> _sendFriendRequest(UserProfile user) async {
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = _relationshipService.currentUserId;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.loginRequired)),
      );
      return;
    }

    setState(() {
      _requestingIds.add(user.uid);
    });

    try {
      final ok = await _relationshipService.sendFriendRequest(user.uid);
      if (!mounted) return;
      if (ok) {
        setState(() {
          _requestedIds.add(user.uid);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.friendRequestSent)),
        );
      }
    } catch (e) {
      if (!mounted) return;
      String msg = e.toString();
      if (msg.startsWith('Exception: ')) {
        msg = msg.substring('Exception: '.length);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _requestingIds.remove(user.uid);
      });
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final int count;

  const _SectionHeader({
    required this.title,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              count > 99 ? '99+' : count.toString(),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
