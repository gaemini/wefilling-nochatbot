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
import '../utils/responsive_helper.dart';
import 'friend_profile_screen.dart';
import 'main_screen.dart';

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
  bool _permissionDenied = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndLoad();
  }

  Future<void> _checkPermissionAndLoad() async {
    try {
      final currentUserId = _relationshipService.currentUserId;

      // 본인 친구 목록은 항상 허용
      if (currentUserId != null && currentUserId == widget.userId) {
        await _loadFriends();
        return;
      }

      // 로그인 안 된 상태에서는 접근 불가
      if (currentUserId == null) {
        _denyAccess();
        return;
      }

      // 친구가 아니면 접근 불가
      final status =
          await _relationshipService.getRelationshipStatus(widget.userId);
      if (status != RelationshipStatus.friends) {
        _denyAccess();
        return;
      }

      await _loadFriends();
    } catch (_) {
      _denyAccess();
    }
  }

  void _denyAccess() {
    if (!mounted) return;
    setState(() {
      _permissionDenied = true;
      _isLoading = false;
      _errorMessage = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.myFriendsOnly),
          backgroundColor: Colors.black87,
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(context).maybePop();
    });
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

      // 친구의 친구 목록에서도 "나"가 보이도록 현재 사용자 필터링을 하지 않는다.
      // (기존: 내 uid를 제외해서 목록에서 사라짐)
      final friends = results[0].toList(growable: false);

      final myFriends = results[1];
      final myFriendIds = myFriends.map((u) => u.uid).toSet();
      // 내 카드가 "이미 친구" 섹션에 자연스럽게 포함되도록(액션 버튼/탭 동작 일관)
      if (currentUserId != null) {
        myFriendIds.add(currentUserId);
      }

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
                  return await _relationshipService
                      .getRelationshipStatus(u.uid);
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
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: width < 360 ? 52 : 56,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Color(0xFF111827),
          ),
          iconSize: 22,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${widget.userName}${AppLocalizations.of(context)!.friendsOfUser}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: context.rf(18).clamp(17, 19).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
        centerTitle: true,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_permissionDenied) {
      final l10n = AppLocalizations.of(context)!;
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.lock_outline,
                  color: Color(0xFF6B7280),
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.myFriendsOnly,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.pointColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    l10n.back,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF667085),
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
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
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _loadFriends,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF344054),
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
            const Icon(
              Icons.people_outline_rounded,
              size: 34,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context)!.noFriendsYet,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
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
      color: const Color(0xFF667085),
      onRefresh: _loadFriends,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
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
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
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
    final currentUserId = _relationshipService.currentUserId;
    final isMe = currentUserId != null && friend.uid == currentUserId;
    final isRequesting = _requestingIds.contains(friend.uid);
    final isRequested = _requestedIds.contains(friend.uid);

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
            Material(
              color: Colors.white,
              child: InkWell(
                onTap: (isFriend || isMe)
                    ? () {
                        if (isMe) {
                          _openMyPage();
                        } else {
                          _openProfile(friend);
                        }
                      }
                    : null,
                child: Padding(
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
                        _friendAvatar(friend, avatarSize),
                        SizedBox(width: isCompact ? 10 : 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _displayNameWithMeSuffix(
                                  friend.displayNameOrNickname,
                                  isMe,
                                ),
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize:
                                      context.rf(14).clamp(13, 15).toDouble(),
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827),
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (friend.nationality != null &&
                                  friend.nationality!.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    CountryFlagCircle(
                                      nationality: friend.nationality!,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        friend.nationality!,
                                        style: const TextStyle(
                                          fontFamily: 'Pretendard',
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF8B93A1),
                                          height: 1.2,
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
                        const SizedBox(width: 4),
                        if (isFriend || isMe)
                          const SizedBox.square(
                            dimension: 40,
                            child: Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color: Color(0xFF98A2B3),
                            ),
                          )
                        else
                          TextButton(
                            onPressed: (isRequesting || isRequested)
                                ? null
                                : () => _sendFriendRequest(friend),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF344054),
                              disabledForegroundColor: const Color(0xFF98A2B3),
                              minimumSize: const Size(44, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 6,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            child: isRequesting
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF667085),
                                    ),
                                  )
                                : Text(
                                    isRequested
                                        ? l10n.requestPending
                                        : l10n.friendRequest,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                      ],
                    ),
                  ),
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

  Widget _friendAvatar(UserProfile friend, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFE5E7EB),
      ),
      child: friend.hasProfileImage
          ? ClipOval(
              child: Image.network(
                friend.photoURL!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.person_outline_rounded,
                  size: size * 0.5,
                  color: const Color(0xFF667085),
                ),
              ),
            )
          : Icon(
              Icons.person_outline_rounded,
              size: size * 0.5,
              color: const Color(0xFF667085),
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

  void _openMyPage() {
    // 하단 네비게이션바가 있는 "원래" 마이페이지 탭으로 이동
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const MainScreen(initialTabIndex: 3),
      ),
      (route) => false,
    );
  }

  String _displayNameWithMeSuffix(String name, bool isMe) {
    if (!isMe) return name;
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ko' ? '$name (나)' : '$name (Me)';
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
      if (mounted) {
        setState(() {
          _requestingIds.remove(user.uid);
        });
      }
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
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360 ? 12.0 : (width < 600 ? 16.0 : 24.0);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            10,
            horizontalPadding,
            7,
          ),
          child: Text(
            '$title  ${count > 99 ? '99+' : count}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF667085),
              letterSpacing: -0.2,
            ),
          ),
        ),
      ),
    );
  }
}
