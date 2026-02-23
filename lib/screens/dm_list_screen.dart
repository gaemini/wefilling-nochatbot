import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/conversation.dart';
import '../models/user_profile.dart';
import '../services/dm_service.dart';
import '../services/relationship_service.dart';
import '../services/user_info_cache_service.dart';
import '../utils/time_formatter.dart';
import '../l10n/app_localizations.dart';
import 'dm_chat_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/logger.dart';
import '../constants/app_constants.dart';
import '../ui/widgets/user_avatar.dart';

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
  final UserInfoCacheService _userInfoCacheService = UserInfoCacheService();
  final _currentUser = FirebaseAuth.instance.currentUser;
  Set<String> _hiddenConversationIds = {};
  // 첫 진입 UX:
  // - 캐시(empty) → 서버 전환 과정에서 "대화 없음"이 잠깐 보였다가 리스트가 나타나는 플래시를 방지한다.
  bool _serverSnapshotSeen = false;
  bool _allowEmptyState = false;
  List<Conversation> _lastNonEmptyConversations = const [];
  static const Duration _emptyStateGrace = Duration(milliseconds: 1500);
  Timer? _emptyStateGraceTimer;
  static const String _anonTitlePrefsPrefix =
      'dm_anon_title__'; // conversationId -> post content
  final Map<String, String> _anonTitleCache =
      {}; // conversationId -> post content
  final Set<String> _anonPrefetchInFlightPostIds = {};
  bool _anonPrefetchScheduled = false;
  bool _anonCacheLoaded = false;
  static const int _anonPrefetchMaxConversations = 25; // UX/성능 균형(최근 것 우선)

  String _truncate(String text, {int max = 40}) {
    final t = text.trim();
    if (t.isEmpty) return t;
    return t.length > max ? '${t.substring(0, max)}...' : t;
  }

  Future<void> _loadCachedAnonTitles() async {
    final prefs = await SharedPreferences.getInstance();
    final keys =
        prefs.getKeys().where((k) => k.startsWith(_anonTitlePrefsPrefix));
    for (final k in keys) {
      final convId = k.substring(_anonTitlePrefsPrefix.length);
      final v = prefs.getString(k);
      if (v != null && v.trim().isNotEmpty) {
        _anonTitleCache[convId] = v.trim();
      }
    }
    _anonCacheLoaded = true;
    if (mounted) setState(() {});
  }

  void _scheduleAnonTitlePrefetch(List<Conversation> conversations) {
    if (_anonPrefetchScheduled) return;
    _anonPrefetchScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _anonPrefetchScheduled = false;
      if (!mounted) return;
      await _prefetchAnonTitles(conversations);
    });
  }

  Future<void> _prefetchAnonTitles(List<Conversation> conversations) async {
    // dmContent가 비어있는 익명+게시글 DM만 대상
    final targets = conversations
        .where((c) {
          final isAnon = c.isOtherUserAnonymous(_currentUser!.uid);
          final postId = (c.postId ?? '').trim();
          if (!isAnon) return false;
          if (postId.isEmpty) return false;
          if ((c.dmContent ?? '').trim().isNotEmpty) return false;
          if ((_anonTitleCache[c.id] ?? '').trim().isNotEmpty) return false;
          return true;
        })
        .take(_anonPrefetchMaxConversations)
        .toList();

    if (targets.isEmpty) return;

    // postId를 모아 배치(whereIn 10개 제한)로 가져오기
    final postIds = <String>{};
    for (final c in targets) {
      final pid = (c.postId ?? '').trim();
      if (pid.isNotEmpty && !_anonPrefetchInFlightPostIds.contains(pid)) {
        postIds.add(pid);
      }
    }
    if (postIds.isEmpty) return;

    for (final pid in postIds) {
      _anonPrefetchInFlightPostIds.add(pid);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = postIds.toList();
      final Map<String, String> postContentById = {};

      // 여러 whereIn 쿼리를 "가능한 한" 병렬로 수행 (체감 속도 개선)
      final List<List<String>> chunks = [];
      for (var i = 0; i < ids.length; i += 10) {
        chunks.add(ids.sublist(i, (i + 10).clamp(0, ids.length)));
      }
      // 동시성 과도 방지(3개씩)
      for (var i = 0; i < chunks.length; i += 3) {
        final batchChunks = chunks.sublist(i, (i + 3).clamp(0, chunks.length));
        final snaps = await Future.wait(batchChunks.map((chunk) {
          return FirebaseFirestore.instance
              .collection('posts')
              .where(FieldPath.documentId, whereIn: chunk)
              .get();
        }));
        for (final snap in snaps) {
          for (final doc in snap.docs) {
            final content = (doc.data()['content'] as String?)?.trim() ?? '';
            if (content.isNotEmpty) {
              postContentById[doc.id] = content;
            }
          }
        }
      }

      // conversationId -> content 매핑 + 로컬 캐시 저장
      final List<Future<void>> prefWrites = [];
      for (final c in targets) {
        final pid = (c.postId ?? '').trim();
        final content = (postContentById[pid] ?? '').trim();
        if (content.isEmpty) continue;

        _anonTitleCache[c.id] = content;
        prefWrites
            .add(prefs.setString('$_anonTitlePrefsPrefix${c.id}', content));
      }
      // prefs 쓰기는 병렬 처리
      if (prefWrites.isNotEmpty) {
        await Future.wait(prefWrites);
      }

      if (mounted) setState(() {});
    } catch (e) {
      Logger.error('익명 DM 타이틀 프리패치 실패(무시): $e');
    } finally {
      for (final pid in postIds) {
        _anonPrefetchInFlightPostIds.remove(pid);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadHiddenConversations();
    _loadCachedAnonTitles();

    // 서버 스냅샷을 받기 전까지는 empty state를 잠깐 유예하고 스켈레톤을 보여준다.
    _emptyStateGraceTimer = Timer(_emptyStateGrace, () {
      if (!mounted) return;
      setState(() {
        _allowEmptyState = true;
      });
    });
  }

  @override
  void dispose() {
    _emptyStateGraceTimer?.cancel();
    _emptyStateGraceTimer = null;
    super.dispose();
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
      floatingActionButton: _buildFloatingActionButtons(),
    );
  }

  /// FloatingActionButton 빌드
  Widget? _buildFloatingActionButtons() {
    if (_filter == DMFilter.friends) {
      return FloatingActionButton(
        onPressed: _showFriendSelectionSheet,
        backgroundColor: AppColors.pointColor,
        child: const Icon(Icons.add, color: Colors.white),
      );
    }

    return null;
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
          child: StreamBuilder<
              ({
                List<Conversation> conversations,
                bool isFromCache,
                bool hasPendingWrites
              })>(
            stream: _dmService.getMyConversationsWithMeta(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return _buildListSkeleton();
              }

              if (snapshot.hasError) {
                Logger.error('❌ DM 목록 로드 오류: ${snapshot.error}');

                // Permission denied 오류 감지
                final errorMessage = snapshot.error.toString();
                if (errorMessage.contains('permission-denied')) {
                  return _buildErrorState(
                    Localizations.localeOf(context).languageCode == 'ko'
                        ? 'Firebase Security Rules가 배포되지 않았거나\n권한이 없습니다.\n\n앱을 다시 시작해주세요.'
                        : 'Firebase Security Rules are not deployed\nor you don\'t have permission.\n\nPlease restart the app.',
                  );
                }

                return _buildErrorState(snapshot.error.toString());
              }

              final payload = snapshot.data;
              final conversations = payload?.conversations ?? <Conversation>[];
              final isFromCache = payload?.isFromCache ?? false;

              // 서버 스냅샷이 한 번이라도 오면(= fromCache=false) empty state 유예를 해제한다.
              if (!_serverSnapshotSeen && payload != null && !isFromCache) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (_serverSnapshotSeen) return;
                  setState(() {
                    _serverSnapshotSeen = true;
                    _allowEmptyState = true;
                  });
                });
              }

              // 캐시(empty) 이벤트가 순간적으로 들어오면, 직전 목록을 유지해 깜빡임을 줄인다.
              if (conversations.isNotEmpty) {
                _lastNonEmptyConversations = conversations;
              } else if (isFromCache && _lastNonEmptyConversations.isNotEmpty) {
                // UI에는 직전 값을 사용하고, 실제 empty 여부는 서버 스냅샷에서 확정한다.
                // (필터/숨김 처리 등은 아래 로직에서 동일하게 적용됨)
              }

              final effectiveConversations = (conversations.isEmpty &&
                      isFromCache &&
                      _lastNonEmptyConversations.isNotEmpty)
                  ? _lastNonEmptyConversations
                  : conversations;

              if (effectiveConversations.isEmpty) {
                // 서버 스냅샷이 오기 전(또는 짧은 유예 시간)에는 empty state 대신 스켈레톤을 보여준다.
                if (!_allowEmptyState) {
                  return _buildListSkeleton();
                }
                return _buildEmptyState(
                  icon: Icons.send_outlined,
                  title: AppLocalizations.of(context)!.noConversations ??
                      '대화가 없습니다',
                  subtitle:
                      AppLocalizations.of(context)!.startFirstConversation ??
                          '첫 대화를 시작해보세요',
                );
              }

              // 익명 게시글 DM 타이틀은 탭과 무관하게 백그라운드로 미리 준비 (체감 속도 개선)
              // - 목록에서 "하나씩 채워지는" 느낌을 줄이기 위해 로컬 캐시 중심으로 갱신
              if (_anonCacheLoaded) {
                _scheduleAnonTitlePrefetch(effectiveConversations);
              }

              // 필터 적용: 친구 / 익명
              final filtered = effectiveConversations.where((c) {
                // 본인이 본인에게 보낸 DM 체크 (participants가 모두 본인)
                final isSelfDM = c.participants.length == 2 &&
                    c.participants[0] == _currentUser!.uid &&
                    c.participants[1] == _currentUser!.uid;

                // 본인 DM은 무조건 숨김
                if (isSelfDM) {
                  return false;
                }

                final isAnon = c.isOtherUserAnonymous(_currentUser!.uid);

                // 친구 탭: 비익명 대화는 모두 표시(게시글에서 시작된 DM 포함)
                // 익명 탭: 익명 대화만 표시
                final passesType =
                    _filter == DMFilter.friends ? !isAnon : isAnon;

                final notHiddenLocal = !_hiddenConversationIds.contains(c.id);
                // ✅ archivedBy 체크 제거: getMyConversations에서 이미 처리됨 (새 메시지 자동 복원)
                // ✅ userLeftAt 체크도 getMyConversations에서 이미 처리됨
                // 상대방이 나가서 참여자가 1명만 남은 경우도 숨김 (메시지 전송/조회 불가)
                final hasOtherParticipant = c.participants.length >= 2;

                return passesType && notHiddenLocal && hasOtherParticipant;
              }).toList();

              if (filtered.isEmpty) {
                if (!_allowEmptyState && !_serverSnapshotSeen) {
                  return _buildListSkeleton();
                }
                return _buildEmptyState(
                  icon: Icons.send_outlined,
                  title: _filter == DMFilter.friends
                      ? AppLocalizations.of(context)!.friends
                      : AppLocalizations.of(context)!.anonymous,
                  subtitle: _filter == DMFilter.friends
                      ? AppLocalizations.of(context)!.noConversations
                      : AppLocalizations.of(context)!.anonymousDescription,
                );
              }

              return ListView.builder(
                padding: EdgeInsets.zero,
                // ✅ 목록 아이템 높이는 항상 76으로 고정(카드 컨테이너)되어 있어
                // 레이아웃 계산 비용을 줄이기 위해 itemExtent를 지정한다.
                // (최신 대화가 상단으로 재정렬되어도 스크롤/렌더가 더 안정적)
                itemExtent: 76,
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final conversation = filtered[index];
                  final preferLatestSkeleton =
                      isFromCache && !_serverSnapshotSeen;
                  // ✅ 중요: 정렬 변경(최신 대화 상단 이동) 시에도
                  // 각 Row의 Stream/Future 상태가 다른 대화로 섞이지 않도록 고유 Key를 부여한다.
                  return KeyedSubtree(
                    key: ValueKey<String>('dm_conv_${conversation.id}'),
                    child: _buildConversationCard(
                      conversation,
                      preferLatestSkeleton: preferLatestSkeleton,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// DM 목록 스켈레톤 (첫 진입/캐시→서버 전환 플리커 방지)
  Widget _buildListSkeleton() {
    // 상단 필터 배너 아래에 자연스럽게 보이도록 리스트 형태로 렌더링
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemExtent: 76,
      itemCount: 8,
      itemBuilder: (context, index) {
        final base = Colors.grey.shade200;
        final base2 = Colors.grey.shade100;
        return Container(
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                decoration: BoxDecoration(
                  color: base,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 120 + (index % 3) * 30,
                      height: 14,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 180 + (index % 4) * 20,
                      height: 12,
                      decoration: BoxDecoration(
                        color: base2,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    width: 34,
                    height: 10,
                    decoration: BoxDecoration(
                      color: base2,
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: base2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// 상단 필터 탭(친구 / 익명) - 밑줄 인디케이터 스타일
  Widget _buildFilterBanners() {
    const activeColor = AppColors.pointColor;
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
                        if (_filter != DMFilter.friends)
                          setState(() => _filter = DMFilter.friends);
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
                            color: _filter == DMFilter.friends
                                ? activeColor
                                : inactiveColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () {
                        if (_filter != DMFilter.anonymous)
                          setState(() => _filter = DMFilter.anonymous);
                      },
                      child: Container(
                        height: 48,
                        alignment: Alignment.center,
                        child: Text(
                          AppLocalizations.of(context)!.anonymous,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _filter == DMFilter.anonymous
                                ? activeColor
                                : inactiveColor,
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
                left: _filter == DMFilter.friends
                    ? leftForFriends
                    : leftForAnonymous,
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

  /// 대화방 카드 빌드 (실시간 조회)
  Widget _buildConversationCard(
    Conversation conversation, {
    required bool preferLatestSkeleton,
  }) {
    final otherUserId = conversation.getOtherUserId(_currentUser!.uid);
    final isAnonymous = conversation.isOtherUserAnonymous(_currentUser!.uid);
    final timeString = TimeFormatter.formatConversationTime(
      context,
      conversation.lastMessageTime,
    );
    final dmContent = conversation.dmContent;
    final myUnread = conversation.getMyUnreadCount(_currentUser!.uid);

    // 🔍 디버그: 익명 대화방 데이터 확인
    if (isAnonymous && kDebugMode) {
      Logger.log('🔍 익명 대화방 데이터:');
      Logger.log('  - ID: ${conversation.id.substring(0, 20)}...');
      Logger.log('  - dmContent: ${dmContent ?? "null"}');
      Logger.log('  - lastMessage: ${conversation.lastMessage}');
    }

    // 🎯 익명 대화방이고 게시글 기반인 경우 (dmContent가 있으면)
    final isPostBasedAnonymous = isAnonymous &&
        ((dmContent != null && dmContent.isNotEmpty) ||
            (conversation.postId != null &&
                conversation.postId!.isNotEmpty) // postId만 있어도 게시글 기반
        );

    if (isPostBasedAnonymous) {
      // ✅ 사용자 친화 UX:
      // - 대화방별 unreadCount를 위해 messages 서브컬렉션을 "방마다" 구독하면
      //   목록 진입이 느려지고 스크롤이 버벅일 수 있다.
      // - 서버(Cloud Functions)가 conversations.unreadCount를 단일 소스로 관리하므로 이를 사용한다.
      final existing = (dmContent ?? '').trim();
      final cached = (_anonTitleCache[conversation.id] ?? '').trim();
      final titleText = existing.isNotEmpty
          ? _truncate(existing)
          : (cached.isNotEmpty
              ? _truncate(cached)
              : (Localizations.localeOf(context).languageCode == 'ko'
                  ? '익명 게시글'
                  : 'Anonymous post'));

      return _buildConversationCardContent(
        conversation: conversation,
        displayName: titleText,
        otherUserId: otherUserId,
        otherUserPhoto: '', // 익명이므로 사진 없음
        otherUserPhotoVersion: 0,
        isAnonymous: isAnonymous,
        timeString: timeString,
        unreadCount: myUnread,
        hideProfile: true,
        isLatestPreviewLoading: preferLatestSkeleton,
      );
    }

    // 초기 표시 값을 캐시 상태에 따라 조건부로 설정
    final cachedStatus = conversation.participantStatus[otherUserId];
    final cachedName = conversation.getOtherUserName(_currentUser!.uid);
    final deletedLabel =
        AppLocalizations.of(context)!.deletedAccount ?? 'Deleted Account';

    // 익명이 아닐 때만 탈퇴 계정 체크
    final isCachedDeleted = !isAnonymous &&
        (cachedStatus == 'deleted' ||
            cachedName.isEmpty ||
            cachedName == 'DELETED_ACCOUNT' ||
            cachedName == deletedLabel);

    // ✅ 사용자 문서 스트림 기반: 최신 프로필/닉네임이 자연스럽게 반영됨
    if (isCachedDeleted) {
      // 탈퇴로 확정이면 굳이 user 문서를 구독하지 않음
      return _buildConversationCardContent(
        conversation: conversation,
        displayName: deletedLabel,
        otherUserId: otherUserId,
        otherUserPhoto: '',
        otherUserPhotoVersion: 0,
        isAnonymous: false,
        timeString: timeString,
        unreadCount: myUnread,
        hideProfile: false,
        isLatestPreviewLoading: preferLatestSkeleton,
      );
    }

    // ✅ 권장 방식:
    // - 상대방 users/{uid} 문서를 실시간 구독해 변경을 즉시 반영한다.
    // - Firestore fromCache 스냅샷(오래된 로컬 캐시)에서는 "옛 닉/사진"을 보여주지 않고
    //   서버에서 확인된 값(fromCache=false)부터 렌더링하여 DM 목록 플리커를 제거한다.
    if (isAnonymous) {
      return _buildConversationCardContent(
        conversation: conversation,
        displayName: AppLocalizations.of(context)!.anonymous,
        otherUserId: otherUserId,
        otherUserPhoto: '',
        otherUserPhotoVersion: 0,
        isAnonymous: true,
        timeString: timeString,
        unreadCount: myUnread,
        hideProfile: true,
        isTitleLoading: false,
        isLatestPreviewLoading: preferLatestSkeleton,
      );
    }

    final initial = _userInfoCacheService.getCachedUserInfo(otherUserId);

    return StreamBuilder<DMUserInfo?>(
      stream: _userInfoCacheService.watchUserInfo(otherUserId),
      initialData: initial,
      builder: (context, snap) {
        final info = snap.data;

        // 문서가 없으면(탈퇴 등) 삭제 계정으로 표시
        if (info == null) {
          return _buildConversationCardContent(
            conversation: conversation,
            displayName: deletedLabel,
            otherUserId: otherUserId,
            otherUserPhoto: '',
            otherUserPhotoVersion: 0,
            isAnonymous: false,
            timeString: timeString,
            unreadCount: myUnread,
            hideProfile: false,
            isTitleLoading: false,
            isLatestPreviewLoading: preferLatestSkeleton,
          );
        }

        final isServerFresh = info.isFromCache == false;

        // fromCache 단계에서는 옛 정보가 보이지 않도록 타이틀은 스켈레톤 처리
        final showTitleSkeleton = preferLatestSkeleton || !isServerFresh;

        final resolvedName = (info.nickname).trim();
        final displayName =
            (resolvedName.isEmpty || resolvedName == 'DELETED_ACCOUNT')
                ? deletedLabel
                : resolvedName;

        return _buildConversationCardContent(
          conversation: conversation,
          displayName: displayName,
          otherUserId: otherUserId,
          otherUserPhoto: isServerFresh ? info.photoURL : '',
          otherUserPhotoVersion: isServerFresh ? info.photoVersion : 0,
          isAnonymous: false,
          timeString: timeString,
          unreadCount: myUnread,
          hideProfile: false,
          isTitleLoading: showTitleSkeleton,
          isLatestPreviewLoading: preferLatestSkeleton,
        );
      },
    );
  }

  /// 대화방 카드 콘텐츠 빌드 (FutureBuilder 내부용)
  Widget _buildConversationCardContent({
    required Conversation conversation,
    required String displayName,
    required String otherUserId,
    required String otherUserPhoto,
    required int otherUserPhotoVersion,
    required bool isAnonymous,
    required String timeString,
    required int unreadCount,
    bool hideProfile = false, // 프로필 숨김 여부
    bool isTitleLoading = false, // 최신 사용자 정보 로딩 중(플리커 방지)
    bool isLatestPreviewLoading = false, // 마지막 메시지/시간 등 최신 정보 로딩 중
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
              // 프로필 이미지 (hideProfile이 false일 때만 표시)
              if (!hideProfile) ...[
                UserAvatar(
                  uid: otherUserId,
                  photoUrl: otherUserPhoto,
                  photoVersion: otherUserPhotoVersion,
                  isAnonymous: isAnonymous,
                  size: 48,
                  placeholderIconSize: 24,
                ),
                const SizedBox(width: 12),
              ],

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
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: isTitleLoading
                                ? Container(
                                    width: 120,
                                    height: 14,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE5E7EB),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  )
                                : Text(
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
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    // 마지막 메시지 (캐시→서버 전환/최신 정보 로딩 중에는 스켈레톤으로 부드럽게)
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeOut,
                      transitionBuilder: (child, anim) =>
                          FadeTransition(opacity: anim, child: child),
                      child: isLatestPreviewLoading
                          ? Container(
                              key: const ValueKey<String>('dm_last_skeleton'),
                              width: 180,
                              height: 12,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                            )
                          : Text(
                              conversation.lastMessage.isEmpty
                                  ? (AppLocalizations.of(context)!.noMessages ??
                                      "")
                                  : conversation.lastMessage,
                              key: ValueKey<String>(
                                'dm_last_${conversation.id}_${conversation.lastMessage}',
                              ),
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                color: const Color(0xFF6B7280),
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: isLatestPreviewLoading
                        ? Container(
                            key: const ValueKey<String>('dm_time_skeleton'),
                            width: 34,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3F4F6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          )
                        : Text(
                            timeString,
                            key: ValueKey<String>(
                              'dm_time_${conversation.id}_$timeString',
                            ),
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                  ),

                  const SizedBox(height: 4),

                  // 읽지 않은 메시지 배지 (하단)
                  if (unreadCount > 0)
                    Container(
                      constraints:
                          const BoxConstraints(minWidth: 20, minHeight: 20),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
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
          const CircularProgressIndicator(color: AppColors.pointColor),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                        child: CircularProgressIndicator(
                            color: AppColors.pointColor),
                      );
                    }

                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          Localizations.localeOf(context).languageCode == 'ko'
                              ? '친구 목록을 불러올 수 없습니다'
                              : 'Unable to load friend list',
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
                            Text(
                              Localizations.localeOf(context).languageCode ==
                                      'ko'
                                  ? '친구가 없습니다'
                                  : 'No friends yet',
                              style: const TextStyle(
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
      Logger.log(
          '🚀 친구와 대화 시작: ${friend.displayNameOrNickname} (${friend.uid})');

      final conversationId = await _dmService.getOrCreateConversation(
        friend.uid,
        isOtherUserAnonymous: false,
      );

      Logger.log('✅ 대화방 ID: $conversationId');

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
        Logger.log('❌ 대화방 ID가 null입니다');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(Localizations.localeOf(context).languageCode == 'ko'
                  ? '대화방을 만들 수 없습니다'
                  : 'Cannot create conversation'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('❌ 대화 시작 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(Localizations.localeOf(context).languageCode == 'ko'
                ? '대화를 시작할 수 없습니다'
                : 'Cannot start conversation'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }
}
