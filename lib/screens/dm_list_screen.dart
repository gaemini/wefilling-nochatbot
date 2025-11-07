// lib/screens/dm_list_screen.dart
// DM 목록 화면
// 대화방 목록을 표시하고 대화방 선택 시 대화 화면으로 이동

import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/conversation.dart';
import '../services/dm_service.dart';
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
          // 본인이 본인에게 보낸 DM 체크 (participants가 모두 본인)
          final isSelfDM = c.participants.length == 2 && 
                           c.participants[0] == _currentUser!.uid && 
                           c.participants[1] == _currentUser!.uid;
          
          // 본인 DM은 무조건 숨김
          if (isSelfDM) return false;
          
          final isAnon = c.isOtherUserAnonymous(_currentUser!.uid);
          
          // 친구 탭: 익명이 아니고 게시글 DM도 아닌 경우만 표시
          // 익명 탭: 익명 대화만 표시 (게시글 DM 포함)
          final isPostDM = c.dmTitle != null && c.dmTitle!.isNotEmpty;
          final passesType = _filter == DMFilter.friends 
              ? (!isAnon && !isPostDM)  // 친구 탭: 일반 친구 대화만
              : isAnon;  // 익명 탭: 모든 익명 대화 (게시글 DM 포함)
          
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
                ? (AppLocalizations.of(context)!.friends ?? "") 
                : AppLocalizations.of(context)!.anonymousUser,
            subtitle: _filter == DMFilter.friends
                ? AppLocalizations.of(context)!.noConversations
                : '게시판에 올라온 익명의 작성자와 소통해보세요.',
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
                          AppLocalizations.of(context)!.anonymousUser,
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
    final otherUserName = conversation.getOtherUserName(_currentUser!.uid);
    final otherUserPhoto = conversation.getOtherUserPhoto(_currentUser!.uid);
    final isAnonymous = conversation.isOtherUserAnonymous(_currentUser!.uid);
    final unreadCount = conversation.getMyUnreadCount(_currentUser!.uid);
    final timeString = TimeFormatter.formatConversationTime(
      context,
      conversation.lastMessageTime,
    );

    // 제목 결정: 익명 글 DM이면 "제목: 게시글 제목" 형식, 그 외엔 기존 표시
    final dmTitle = conversation.dmTitle;
    final displayName = (dmTitle != null && dmTitle.isNotEmpty)
        ? '제목: $dmTitle'
        : (isAnonymous 
            ? (AppLocalizations.of(context)!.anonymousUser ?? "") : otherUserName);

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
                        Text(
                          timeString,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: Color(0xFF9CA3AF),
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
              
              // 읽지 않은 메시지 배지
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DMChatScreen(
          conversationId: conversation.id,
          otherUserId: conversation.getOtherUserId(_currentUser!.uid),
        ),
      ),
    );
  }
}

