// lib/screens/user_friends_list_screen.dart
// 특정 사용자의 친구 목록 화면
// 프로필 친구 네트워크 탐색 목록

import 'dart:async';
import 'package:flutter/material.dart';
import '../services/relationship_service.dart';
import '../models/user_profile.dart';
import '../constants/app_constants.dart';
import '../widgets/country_flag_circle.dart';
import '../l10n/app_localizations.dart';
import '../utils/logger.dart';
import '../utils/responsive_helper.dart';
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
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<ProfileFriendNetworkMember> _friends =
      const <ProfileFriendNetworkMember>[];
  final Set<String> _requestingIds = <String>{};
  final Set<String> _requestedIds = <String>{};
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int? _nextCursor;
  int _totalCount = 0;
  int _mutualCount = 0;
  String _query = '';
  Timer? _searchDebounce;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _loadFriends();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (_scrollController.position.extentAfter < 260) {
      unawaited(_loadMore());
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final normalized = value.trim();
      if (normalized == _query) return;
      setState(() => _query = normalized);
      unawaited(_loadFriends());
    });
  }

  Future<void> _loadFriends() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
      final page = await _relationshipService.getProfileFriendNetwork(
        targetUid: widget.userId,
        pageSize: 20,
        query: _query,
        forceRefresh: true,
      );

      if (mounted) {
        setState(() {
          _friends = page.friends;
          _nextCursor = page.nextCursor;
          _totalCount = page.totalCount;
          _mutualCount = page.mutualCount;
          _isLoading = false;
        });
        Logger.log('✅ ${widget.userName}의 친구 목록 로드: ${page.friends.length}명');
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

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    if (cursor == null || _isLoading || _isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final page = await _relationshipService.getProfileFriendNetwork(
        targetUid: widget.userId,
        pageSize: 20,
        cursor: cursor,
        query: _query,
      );
      if (!mounted) return;
      setState(() {
        final known = _friends.map((item) => item.profile.uid).toSet();
        _friends = [
          ..._friends,
          ...page.friends.where((item) => known.add(item.profile.uid)),
        ];
        _nextCursor = page.nextCursor;
        _isLoadingMore = false;
      });
    } catch (error) {
      Logger.error('친구 목록 추가 로드 오류: $error');
      if (mounted) setState(() => _isLoadingMore = false);
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
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
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
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
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
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_friends.isEmpty && _query.isEmpty) {
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
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
          ],
        ),
      );
    }

    final mutualGroup =
        _friends.where((member) => member.isMutual).toList(growable: false);
    final alreadyFriendsGroup = _friends
        .where((member) =>
            !member.isMutual && (member.isMyFriend || member.isCurrentUser))
        .toList(growable: false);
    final otherGroup = _friends
        .where((member) =>
            !member.isMutual && !member.isMyFriend && !member.isCurrentUser)
        .toList(growable: false);

    final l10n = AppLocalizations.of(context)!;

    return RefreshIndicator(
      color: const Color(0xFF667085),
      onRefresh: _loadFriends,
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(child: _buildSearchField()),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
              child: Text(
                Localizations.localeOf(context).languageCode == 'ko'
                    ? '친구 $_totalCount명'
                        '${_mutualCount > 0 ? ' · 함께 아는 친구 $_mutualCount명' : ''}'
                    : '$_totalCount friends'
                        '${_mutualCount > 0 ? ' · $_mutualCount mutual' : ''}',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF667085),
                ),
              ),
            ),
          ),
          if (_friends.isEmpty && _query.isNotEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text(
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '검색 결과가 없어요.'
                      : 'No matching friends.',
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: ['NotoSansKR'],
                    fontSize: 14,
                    color: Color(0xFF98A2B3),
                  ),
                ),
              ),
            ),
          if (mutualGroup.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: Localizations.localeOf(context).languageCode == 'ko'
                    ? '함께 아는 친구'
                    : 'Mutual friends',
                count: mutualGroup.length,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildFriendCard(
                  mutualGroup[index],
                ),
                childCount: mutualGroup.length,
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 8)),
          ],
          if (alreadyFriendsGroup.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: l10n.alreadyFriends,
                count: alreadyFriendsGroup.length,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildFriendCard(
                  alreadyFriendsGroup[index],
                ),
                childCount: alreadyFriendsGroup.length,
              ),
            ),
          ],
          if (otherGroup.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: l10n.notFriends,
                count: otherGroup.length,
              ),
            ),
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildFriendCard(otherGroup[index]),
                childCount: otherGroup.length,
              ),
            ),
          ],
          if (_isLoadingMore)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: MediaQuery.paddingOf(context).bottom + 24,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: isKo ? '닉네임 검색' : 'Search by nickname',
          prefixIcon: const Icon(Icons.search_rounded, size: 21),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                    setState(() {});
                  },
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
          filled: false,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 13),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFFE2E8F0)),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF475569), width: 1.3),
          ),
        ),
      ),
    );
  }

  Widget _buildFriendCard(
    ProfileFriendNetworkMember member,
  ) {
    final friend = member.profile;
    final l10n = AppLocalizations.of(context)!;
    final currentUserId = _relationshipService.currentUserId;
    final isMe = currentUserId != null && friend.uid == currentUserId;
    final isRequesting = _requestingIds.contains(friend.uid);
    final isRequested =
        member.isPendingOut || _requestedIds.contains(friend.uid);

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
                onTap: () => _openProfile(friend),
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
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(14).clamp(13, 15).toDouble(),
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827),
                                  height: 1.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (friend.isSchoolVerified) ...[
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.verified_rounded,
                                        size: 14, color: AppColors.pointColor),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        Localizations.localeOf(context)
                                                    .languageCode ==
                                                'ko'
                                            ? '학교 인증'
                                            : 'School verified',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: ['NotoSansKR'],
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
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
                                          fontFamily: 'Inter',
                                          fontFamilyFallback: const [
                                            'NotoSansKR'
                                          ],
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
                        if (member.isMyFriend || isMe || member.isCurrentUser)
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
                                      fontFamily: 'Inter',
                                      fontFamilyFallback: const ['NotoSansKR'],
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
          allowNonFriendsPreview: true,
        ),
      ),
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
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
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
