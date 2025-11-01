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
      title: Text(
        AppLocalizations.of(context)!.dm,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      elevation: 0,
      backgroundColor: Colors.white,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(0.5),
        child: Container(
          color: Colors.grey[200],
          height: 0.5,
        ),
      ),
    );
  }

  /// Body 빌드
  Widget _buildBody() {
    if (_currentUser == null) {
      return _buildEmptyState(
        icon: Icons.login,
        title: AppLocalizations.of(context)!.loginRequired,
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
            title: AppLocalizations.of(context)!.noConversations,
            subtitle: AppLocalizations.of(context)!.startFirstConversation,
          );
        }
        
        // 필터 적용: 친구 / 익명
        final filtered = conversations.where((c) {
          final isAnon = c.isOtherUserAnonymous(_currentUser!.uid);
          return _filter == DMFilter.friends ? !isAnon : isAnon;
        }).toList();

        if (filtered.isEmpty) {
          return _buildEmptyState(
            icon: Icons.chat_bubble_outline,
            title: _filter == DMFilter.friends
                ? AppLocalizations.of(context)!.friends
                : AppLocalizations.of(context)!.anonymousUser,
            subtitle: AppLocalizations.of(context)!.noConversations,
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
    final activeColor = Colors.blue[700]!;
    final inactiveColor = Colors.grey[500]!;

    return LayoutBuilder(
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
              child: Container(height: 1, color: Colors.grey[200]),
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
                      height: 44,
                      alignment: Alignment.center,
                      child: Text(
                        AppLocalizations.of(context)!.friends,
                        style: TextStyle(
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
                      height: 44,
                      alignment: Alignment.center,
                      child: Text(
                        AppLocalizations.of(context)!.anonymousUser,
                        style: TextStyle(
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
              bottom: 2,
              child: Container(
                width: indicatorWidth,
                height: 3,
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        );
      },
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

    // 익명인 경우 로컬라이제이션 적용
    final displayName = isAnonymous 
        ? AppLocalizations.of(context)!.anonymousUser 
        : otherUserName;

    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: () => _openConversation(conversation),
        child: Container(
          height: 80,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.grey[200]!,
                width: 0.5,
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
                      children: [
                        // 이름
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // 시간
                        Text(
                          timeString,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 4),
                    
                    // 마지막 메시지
                    Text(
                      conversation.lastMessage.isEmpty 
                          ? AppLocalizations.of(context)!.noMessages 
                          : conversation.lastMessage,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
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
                    color: const Color(0xFFFF5252), // DMColors.unreadBadge
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    unreadCount > 99 ? '99+' : unreadCount.toString(),
                    style: const TextStyle(
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
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.grey[200],
        image: !isAnonymous && photoUrl.isNotEmpty
            ? DecorationImage(
                image: NetworkImage(photoUrl),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: (!isAnonymous && photoUrl.isNotEmpty)
          ? null
          : Icon(
              Icons.person,
              size: 28,
              color: Colors.grey[400],
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
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
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
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.loadingMessages,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
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
          Icon(
            Icons.error_outline,
            size: 80,
            color: Colors.red[300],
          ),
          const SizedBox(height: 16),
          Text(
            AppLocalizations.of(context)!.error,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
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

