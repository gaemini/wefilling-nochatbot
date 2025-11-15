// lib/screens/dm_list_screen.dart
// DM 목록 화면
// 대화방 목록을 표시하고 대화방 선택 시 대화 화면으로 이동

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/conversation.dart';
import '../models/user_profile.dart';
import '../services/dm_service.dart';
import '../services/relationship_service.dart';
import '../utils/time_formatter.dart';
import '../l10n/app_localizations.dart';
import 'dm_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

// DM 목록 필터: 친구 / 익명
enum DMFilter { friends, anonymous }

class DMListScreen extends StatefulWidget {
  const DMListScreen({super.key});

  @override
  State<DMListScreen> createState() => _DMListScreenState();
}

class _DMListScreenState extends State<DMListScreen> {
  final DMService _dmService = DMService();
  final RelationshipService _relationshipService = RelationshipService();
  final _currentUser = FirebaseAuth.instance.currentUser;
  Set<String> _hiddenConversationIds = {};

  @override
  void initState() {
    super.initState();
    _loadHiddenConversations();
  }

  Future<void> _loadHiddenConversations() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('hidden_conversations') ?? <String>[];
    setState(() {
      _hiddenConversationIds = list.toSet();
    });
  }
  
  // 상단 배너(친구 / 익명) 필터
  DMFilter _filter = DMFilter.friends;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _filter == DMFilter.friends
          ? FloatingActionButton(
              onPressed: _showFriendSelectionSheet,
              backgroundColor: const Color(0xFF5865F2),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  /// AppBar 빌드
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      toolbarHeight: 0,
    );
  }

  /// Body 빌드
  Widget _buildBody() {
    if (_currentUser == null) {
      return _buildEmptyState(
        icon: Icons.login,
        title: AppLocalizations.of(context)!.loginRequired ?? '로그인이 필요합니다',
        subtitle: '',
      );
    }
    
    return Column(
      children: [
        _buildFilterBanners(),
        Expanded(
          child: StreamBuilder<List<Conversation>>(
      stream: _dmService.getMyConversations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        if (snapshot.hasError) {
          print('❌ DM 목록 로드 오류: ${snapshot.error}');
          
          // Permission denied 오류 감지
          final errorMessage = snapshot.error.toString();
          if (errorMessage.contains('permission-denied')) {
            return _buildErrorState(
              'Firebase Security Rules가 배포되지 않았거나\n권한이 없습니다.\n\n앱을 다시 시작해주세요.',
            );
          }
          
          return _buildErrorState(snapshot.error.toString());
        }

        final conversations = snapshot.data ?? [];

        if (conversations.isEmpty) {
          return _buildEmptyState(
            icon: Icons.chat_bubble_outline,
            title: AppLocalizations.of(context)!.noConversations ?? '대화가 없습니다',
            subtitle: AppLocalizations.of(context)!.startFirstConversation ?? '첫 대화를 시작해보세요',
          );
        }
        
        // 필터 적용: 친구 / 익명
        final filtered = conversations.where((c) {
          // 현재 사용자가 participants에 포함되어 있는지 확인
          if (!c.participants.contains(_currentUser!.uid)) {
            print('❌ [DM필터] 제외: ${c.id} (현재 사용자가 participants에 없음!)');
            return false;
          }
          
          // 본인이 본인에게 보낸 DM 체크 (participants가 모두 본인)
          final isSelfDM = c.participants.length == 2 && 
                           c.participants[0] == _currentUser!.uid && 
                           c.participants[1] == _currentUser!.uid;
          
          // 본인 DM은 무조건 숨김
          if (isSelfDM) {
            print('  ❌ 제외: ${c.id} (본인 DM)');
            return false;
          }

          // 익명 여부 확인: conversationId가 'anon_'으로 시작하거나 isAnonymous 필드 확인
          final isAnonById = c.id.startsWith('anon_');
          final isAnonByField = c.isOtherUserAnonymous(_currentUser!.uid);
          final isAnon = isAnonById || isAnonByField;
          
          // 친구 탭: 익명이 아닌 대화만 표시 (일반 친구 대화)
          // 익명 탭: 익명 대화만 표시 (게시글 DM 포함)
          final passesType = _filter == DMFilter.friends 
              ? !isAnon  // 친구 탭: 익명이 아닌 대화
              : isAnon;  // 익명 탭: 익명 대화
          
          final notHiddenLocal = !_hiddenConversationIds.contains(c.id);
          final notArchivedServer = !(c.archivedBy.contains(_currentUser!.uid));
          // 상대방이 나가서 참여자가 1명만 남은 경우도 숨김 (메시지 전송/조회 불가)
          final hasOtherParticipant = c.participants.length >= 2;
          
          return passesType && notHiddenLocal && notArchivedServer && hasOtherParticipant;
        }).toList();

        if (filtered.isEmpty) {
          return _buildEmptyState(
            icon: Icons.chat_bubble_outline,
            title: _filter == DMFilter.friends
                    ? AppLocalizations.of(context)!.friends
                : 'Anonymous',
            subtitle: _filter == DMFilter.friends
                ? AppLocalizations.of(context)!.noConversations
                : AppLocalizations.of(context)!.anonymousDescription,
          );
        }

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            return _buildConversationCard(filtered[index]);
          },
        );
      },
          ),
        ),
      ],
    );
  }

  /// 상단 필터 탭(친구 / 익명) - 밑줄 인디케이터 스타일
  Widget _buildFilterBanners() {
    const activeColor = Color(0xFF5865F2);
    const inactiveColor = Color(0xFF9CA3AF);

    return Container(
      color: Colors.white,
      child: LayoutBuilder(
      builder: (context, constraints) {
        final tabWidth = constraints.maxWidth / 2;
        final indicatorWidth = 42.0;
        final leftForFriends = (tabWidth - indicatorWidth) / 2;
        final leftForAnonymous = tabWidth + (tabWidth - indicatorWidth) / 2;

        return Stack(
          children: [
            // 하단 라인
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
                child: Container(height: 1, color: const Color(0xFFE5E7EB)),
            ),

            // 탭 텍스트 영역
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (_filter != DMFilter.friends) setState(() => _filter = DMFilter.friends);
                    },
                    child: Container(
                        height: 48,
                      alignment: Alignment.center,
                      child: Text(
                        AppLocalizations.of(context)!.friends,
                        style: TextStyle(
                            fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _filter == DMFilter.friends ? activeColor : inactiveColor,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      if (_filter != DMFilter.anonymous) setState(() => _filter = DMFilter.anonymous);
                    },
                    child: Container(
                        height: 48,
                      alignment: Alignment.center,
                      child: Text(
                        'Anonymous',
                        style: TextStyle(
                            fontFamily: 'Pretendard',
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _filter == DMFilter.anonymous ? activeColor : inactiveColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // 인디케이터
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              left: _filter == DMFilter.friends ? leftForFriends : leftForAnonymous,
                bottom: 0,
              child: Container(
                width: indicatorWidth,
                  height: 2.5,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        );
      },
      ),
    );
  }

  /// 대화방 카드 빌드
  Widget _buildConversationCard(Conversation conversation) {
    final otherUserId = conversation.getOtherUserId(_currentUser!.uid);
    final isAnonymous = conversation.isOtherUserAnonymous(_currentUser!.uid);
    final timeString = TimeFormatter.formatConversationTime(
      context,
      conversation.lastMessageTime,
    );

    // 제목 결정: 익명 글 DM이면 "제목/Topic: 게시글 제목" 형식
    final dmTitle = conversation.dmTitle;
    final hasCustomTitle = dmTitle != null && dmTitle.isNotEmpty;

    // 익명이 아닌 경우 실시간 프로필 조회
    if (!isAnonymous && !hasCustomTitle) {
      return FutureBuilder<DocumentSnapshot>(
        future: FirebaseFirestore.instance.collection('users').doc(otherUserId).get(),
        builder: (context, userSnapshot) {
          // 로딩 중이거나 오류가 있어도 기본 정보로 표시
          String displayName;
          String photoUrl;
          
          if (userSnapshot.connectionState == ConnectionState.waiting) {
            // 로딩 중: 대화방에 저장된 이름 사용
            displayName = conversation.getOtherUserName(_currentUser!.uid);
            photoUrl = conversation.getOtherUserPhoto(_currentUser!.uid);
          } else if (userSnapshot.hasData && userSnapshot.data!.exists) {
            final userData = userSnapshot.data!.data() as Map<String, dynamic>?;
            // 닉네임 우선, 없으면 displayName 사용
            displayName = userData?['nickname'] ?? userData?['displayName'] ?? 'Unknown';
            photoUrl = userData?['photoURL'] ?? '';
          } else {
            // 프로필 조회 실패 시 대화방에 저장된 이름 사용
            displayName = conversation.getOtherUserName(_currentUser!.uid);
            photoUrl = conversation.getOtherUserPhoto(_currentUser!.uid);
          }

          // 배지는 카드 콘텐츠 내부에서 StreamBuilder로 처리
          return _buildConversationCardWithBadge(
            conversation: conversation,
            displayName: displayName,
            otherUserPhoto: photoUrl,
            isAnonymous: isAnonymous,
            timeString: timeString,
          );
        },
      );
    } else {
      // 익명이거나 커스텀 타이틀이 있는 경우
      final displayName = hasCustomTitle
          ? '${AppLocalizations.of(context)!.topic}: $dmTitle'
          : 'Anonymous';
      final photoUrl = conversation.getOtherUserPhoto(_currentUser!.uid);

      return _buildConversationCardWithBadge(
        conversation: conversation,
        displayName: displayName,
        otherUserPhoto: photoUrl,
        isAnonymous: isAnonymous,
        timeString: timeString,
      );
    }
  }

  /// 배지와 함께 대화방 카드 빌드 (StreamBuilder 사용)
  Widget _buildConversationCardWithBadge({
    required Conversation conversation,
    required String displayName,
    required String otherUserPhoto,
    required bool isAnonymous,
    required String timeString,
  }) {
    return StreamBuilder<int>(
      stream: _dmService.getActualUnreadCountStream(conversation.id, _currentUser!.uid),
      initialData: 0,
      builder: (context, snapshot) {
        final unreadCount = snapshot.data ?? 0;

        return _buildConversationCardContent(
          conversation: conversation,
          displayName: displayName,
          otherUserPhoto: otherUserPhoto,
          isAnonymous: isAnonymous,
          timeString: timeString,
          unreadCount: unreadCount,
        );
      },
    );
  }

  /// 대화방 카드 콘텐츠 빌드 (FutureBuilder 내부용)
  Widget _buildConversationCardContent({
    required Conversation conversation,
    required String displayName,
    required String otherUserPhoto,
    required bool isAnonymous,
    required String timeString,
    required int unreadCount,
  }) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openConversation(conversation),
        child: Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Color(0xFFF3F4F6),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              // 프로필 이미지
              _buildProfileImage(otherUserPhoto, isAnonymous),
              
              const SizedBox(width: 12),
              
              // 내용 영역
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF111827),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                    // 마지막 메시지
                    Text(
                      conversation.lastMessage.isEmpty 
                          ? (AppLocalizations.of(context)!.noMessages ?? "") : conversation.lastMessage,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: const Color(0xFF6B7280),
                        fontWeight: unreadCount > 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              
              // 오른쪽 영역 (날짜 + 배지)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 날짜 (상단)
                  Text(
                    timeString,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  
                  const SizedBox(height: 4),
                  
                  // 읽지 않은 메시지 배지 (하단)
                  if (unreadCount > 0)
                    Container(
                      constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        unreadCount > 99 ? '99+' : unreadCount.toString(),
                        style: const TextStyle(
                          fontFamily: 'Pretendard',
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 프로필 이미지 빌드
  Widget _buildProfileImage(String photoUrl, bool isAnonymous) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFE5E7EB),
        image: !isAnonymous && photoUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: (!isAnonymous && photoUrl.isNotEmpty)
          ? null
          : const Icon(
              Icons.person,
              size: 24,
              color: Color(0xFF6B7280),
            ),
    );
  }

  /// 빈 상태 빌드
  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: const Color(0xFFD1D5DB),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF9CA3AF),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 로딩 상태 빌드
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF5865F2)),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.loadingMessages,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
    );
  }

  /// 오류 상태 빌드
  Widget _buildErrorState(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 80,
            color: Color(0xFFFCA5A5),
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.error,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFFEF4444),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
            error,
              style: const TextStyle(
                fontFamily: 'Pretendard',
              fontSize: 14,
                fontWeight: FontWeight.w400,
                color: Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// 대화방 열기
  void _openConversation(Conversation conversation) {
    final otherUserId = conversation.getOtherUserId(_currentUser!.uid);
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📂 대화방 열기');
    print('  - conversationId: ${conversation.id}');
    print('  - participants: ${conversation.participants}');
    print('  - 내 UID: ${_currentUser!.uid}');
    print('  - 상대방 UID: $otherUserId');
    print('  - 상대방 이름: ${conversation.getOtherUserName(_currentUser!.uid)}');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DMChatScreen(
          conversationId: conversation.id,
          otherUserId: otherUserId,
        ),
      ),
    );
  }

  /// 친구 선택 바텀시트 표시
  void _showFriendSelectionSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // 핸들 바
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              
              // 헤더
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      AppLocalizations.of(context)!.friendSelection,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              
              // 친구 목록
              Expanded(
                child: StreamBuilder<List<UserProfile>>(
                  stream: _relationshipService.getFriends(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: Color(0xFF5865F2)),
                      );
                    }
                    
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '친구 목록을 불러올 수 없습니다',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      );
                    }
                    
                    final friends = snapshot.data ?? [];
                    
                    if (friends.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.people_outline,
                              size: 64,
                              color: Color(0xFFD1D5DB),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '친구가 없습니다',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    
                    return ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        final friend = friends[index];
                        return _buildFriendSelectionCard(friend);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 친구 선택 카드
  Widget _buildFriendSelectionCard(UserProfile friend) {
    return InkWell(
      onTap: () {
        Navigator.pop(context); // 바텀시트 닫기
        _startConversationWithFriend(friend);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
        ),
        child: Row(
          children: [
            // 프로필 이미지
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE5E7EB),
              ),
              child: friend.hasProfileImage
                  ? ClipOval(
                      child: Image.network(
                        friend.photoURL!,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.person,
                          size: 24,
                          color: Color(0xFF6B7280),
                        ),
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
                  if (friend.nickname != null && 
                      friend.nickname != friend.displayName &&
                      friend.nickname!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      friend.displayName,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                        color: Color(0xFF6B7280),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            
            // 화살표 아이콘
            const Icon(
              Icons.chevron_right,
              color: Color(0xFF9CA3AF),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  /// 친구와 대화 시작
  Future<void> _startConversationWithFriend(UserProfile friend) async {
    try {
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🚀 친구와 대화 시작');
      print('  - 친구 이름: ${friend.displayNameOrNickname}');
      print('  - 친구 UID: ${friend.uid}');
      print('  - 내 UID: ${_currentUser?.uid}');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      final conversationId = await _dmService.getOrCreateConversation(
        friend.uid,
        isOtherUserAnonymous: false,  // 친구는 익명이 아님
        isFriend: true,  // 친구 프로필에서 시작한 대화임을 명시
      );
      
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('✅ 대화방 생성/조회 완료');
      print('  - conversationId: $conversationId');
      print('  - 예상 형식: ${_currentUser?.uid}_${friend.uid} (사전순 정렬)');
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      
      if (conversationId != null && mounted) {
        // 대화방으로 이동
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => DMChatScreen(
              conversationId: conversationId,
              otherUserId: friend.uid,
            ),
          ),
        );
      } else {
        print('❌ 대화방 ID가 null입니다');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('대화방을 만들 수 없습니다'),
              backgroundColor: Color(0xFFEF4444),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ 대화 시작 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('대화를 시작할 수 없습니다'),
            backgroundColor: Color(0xFFEF4444),
          ),
        );
      }
    }
  }
}

