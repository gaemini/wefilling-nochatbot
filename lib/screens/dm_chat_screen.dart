// lib/screens/dm_chat_screen.dart
// DM 대화 화면
// 메시지 목록과 입력창을 표시하고 실시간 메시지 전송/수신

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/dm_message.dart';
import '../services/dm_service.dart';
import '../services/post_service.dart';
import '../services/content_filter_service.dart';
import '../services/storage_service.dart';
import '../services/user_info_cache_service.dart';
import '../utils/time_formatter.dart';
import '../l10n/app_localizations.dart';
import '../design/tokens.dart';
import 'package:intl/intl.dart';
import 'post_detail_screen.dart';
import '../ui/widgets/fullscreen_image_viewer.dart';
import 'dm_image_send_preview_screen.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/logger.dart';
import '../ui/snackbar/app_snackbar.dart';

// DM 전용 색상
class DMColors {
  static const myMessageBg = Color(0xFF4A90E2); // Primary blue
  static const myMessageText = Colors.white;
  static const otherMessageBg = Color(0xFFF0F0F0); // Light grey
  static const otherMessageText = Color(0xFF333333); // Dark grey
  static const inputBg = Color(0xFFF8F8F8);
  static const inputBorder = Color(0xFFE0E0E0);
}

class DMChatScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  /// 게시글 상세/카드에서 DM으로 진입한 경우, 첫 전송 메시지에 붙일 게시글 컨텍스트
  /// - 상대방 채팅창에 "게시글에서 보낸 메시지" 카드(썸네일+미리보기)로 표시된다.
  final String? originPostId;
  final String? originPostImageUrl;
  final String? originPostPreview;

  const DMChatScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    this.originPostId,
    this.originPostImageUrl,
    this.originPostPreview,
  });

  @override
  State<DMChatScreen> createState() => _DMChatScreenState();
}

class _DMChatScreenState extends State<DMChatScreen> {
  final DMService _dmService = DMService();
  final StorageService _storageService = StorageService();
  final UserInfoCacheService _userInfoCacheService = UserInfoCacheService();
  final _currentUser = FirebaseAuth.instance.currentUser;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  Stream<DMUserInfo?>? _otherUserInfoStream;
  // UX: 캐시 스냅샷(fromCache) → 서버 스냅샷 전환으로 인한 플리커를 방지하기 위해
  // 서버에서 확인된 최신 상대 프로필 정보를 별도로 보관한다.
  DMUserInfo? _serverOtherUserInfo;
  bool _serverOtherUserInfoFetchInFlight = false;
  Timer? _autoMarkReadDebounce;
  bool _autoMarkReadInFlight = false;
  
  // 대화방이 없을 수 있으므로 초기에 서버 구독을 시작하지 않는다.
  StreamSubscription<List<DMMessage>>? _recentMessagesSub;
  List<DMMessage> _messages = <DMMessage>[];
  Object? _messagesError;
  bool _isMessagesLoading = false; // 캐시/서버 초기 로드
  bool _isLoadingMore = false; // 과거 페이지 로드
  bool _hasMore = true; // 더 과거 메시지가 있는지(추정)
  DateTime? _visibilityStartTime; // leave 기록 기반 가시성 시작 시간
  // 초기 진입 체감 속도를 위해 "최근 N개"만 먼저 보여준다.
  // (과거 메시지는 사용자가 위로 스크롤하면 자동으로 추가 로드)
  static const int _recentLimit = 40;
  static const int _pageSize = 50;
  // 로컬 캐시도 과하게 많이 읽으면 첫 렌더가 무거워질 수 있어 recentLimit에 맞춘다.
  static const int _initialCacheLimit = _recentLimit;

  // 첫 메시지 전송으로 실제 conversationId가 바뀔 수 있어, 화면 내에서는 별도로 추적한다.
  late String _activeConversationId;
  // null: 아직 확인 전(초기 로딩), false: 없음(첫 메시지 전송 시 생성), true: 존재
  bool? _conversationExists;
  bool _isConversationInitializing = true;
  
  Conversation? _conversation;
  bool _isLoading = false;
  bool _isLeaving = false; // 나가기 진행 중 플래그
  static const String _anonTitlePrefsPrefix = 'dm_anon_title__'; // conversationId -> post content
  String? _preloadedDmContent; // 미리 로드된 게시글 본문(대화방 제목용)
  String? _backfilledPostId; // dmContent 백필을 1회만 수행하기 위한 가드
  bool _isBlocked = false; // 차단 여부
  bool _isBlockedBy = false; // 차단당한 여부
  File? _pendingImage; // 첨부 대기 이미지 (1장 제한)
  double? _uploadProgress; // 이미지 업로드 진행률 (0~1)
  bool _originPostContextAttached = false; // 현재 진입(세션)에서 게시글 컨텍스트를 1회만 부착
  bool _composerPostContextDismissed = false; // 입력창 위 미리보기 카드 닫힘 여부

  @override
  void initState() {
    super.initState();
    _activeConversationId = widget.conversationId;
    _otherUserInfoStream = _userInfoCacheService.watchUserInfo(widget.otherUserId);
    _scrollController.addListener(_onScroll);
    
    _checkBlockStatus(); // 차단 상태 확인
    _preloadPostContentIfAnonymous(); // 익명이면 게시글 본문 미리 로드
    _initConversationState();

    // 상대 프로필은 서버 기준 최신값을 먼저 확보 (캐시 플리커 방지)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_isAnonymous) return;
      _ensureServerOtherUserInfo(widget.otherUserId);
    });
  }

  void _ensureServerOtherUserInfo(String userId) {
    if (_serverOtherUserInfo != null) return;
    if (_serverOtherUserInfoFetchInFlight) return;
    _serverOtherUserInfoFetchInFlight = true;

    _userInfoCacheService
        .getUserInfo(userId, forceRefresh: true)
        .then((info) {
      if (!mounted) return;
      if (info == null) return;
      setState(() {
        _serverOtherUserInfo = DMUserInfo(
          uid: info.uid,
          nickname: info.nickname,
          photoURL: info.photoURL,
          photoVersion: info.photoVersion,
          isFromCache: false,
        );
      });
    }).whenComplete(() {
      _serverOtherUserInfoFetchInFlight = false;
    });
  }
  
  /// 디버그: Firestore에 실제로 저장된 데이터 확인
  /// 차단 상태 확인
  Future<void> _checkBlockStatus() async {
    try {
      final isBlocked = await ContentFilterService.isUserBlocked(widget.otherUserId);
      final isBlockedBy = await ContentFilterService.isBlockedByUser(widget.otherUserId);
      
      if (mounted) {
        setState(() {
          _isBlocked = isBlocked;
          _isBlockedBy = isBlockedBy;
        });
      }
    } catch (e) {
      Logger.error('차단 상태 확인 실패: $e');
    }
  }
  
  String? _extractPostIdFromConversationId(String conversationId) {
    if (!conversationId.startsWith('anon_')) return null;
    final parts = conversationId.split('_');
    if (parts.length < 4) return null;
    var postId = parts.sublist(3).join('_');
    // __timestamp 형식의 접미사 제거
    if (postId.contains('__')) {
      postId = postId.split('__').first;
    }
    return postId.isEmpty ? null : postId;
  }

  /// 익명 게시글 DM이면 게시글 본문을 미리 로드 (AppBar에 즉시 표시)
  Future<void> _preloadPostContentIfAnonymous() async {
    final postId = _extractPostIdFromConversationId(widget.conversationId);
    if (postId == null) return;

    try {
      // 1) 로컬 캐시(SharedPreferences) 우선 - UX 개선 (즉시 표시)
      final prefs = await SharedPreferences.getInstance();
      final cached = (prefs.getString('$_anonTitlePrefsPrefix${widget.conversationId}') ?? '').trim();
      if (cached.isNotEmpty && mounted) {
        setState(() {
          _preloadedDmContent = cached;
        });
        return;
      }

      // 2) Firestore에서 게시글 본문 로드
      final postDoc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
      final content = postDoc.exists ? (postDoc.data()?['content'] as String?) : null;
      if (!mounted) return;
      if (content != null && content.trim().isNotEmpty) {
        final normalized = content.trim();
        await prefs.setString('$_anonTitlePrefsPrefix${widget.conversationId}', normalized);
        setState(() {
          _preloadedDmContent = normalized;
        });
      }
    } catch (e) {
      Logger.error('게시글 본문 미리 로드 실패: $e');
    }
  }

  /// 기존 대화방 문서에 dmContent가 없으면 게시글 본문으로 1회 백필
  Future<void> _ensureDmContentBackfilled({required String postId}) async {
    if (_backfilledPostId == postId) return;

    try {
      final postDoc = await FirebaseFirestore.instance.collection('posts').doc(postId).get();
      final content = postDoc.exists ? (postDoc.data()?['content'] as String?) : null;
      final normalized = content?.trim() ?? '';
      if (normalized.isEmpty) {
        _backfilledPostId = postId; // 더 시도해도 의미 없으므로 가드
        return;
      }

      // UI용 프리로드도 갱신
      if (mounted) {
        setState(() {
          _preloadedDmContent = normalized;
        });
      }

      // 로컬 캐시 저장(다음 진입부터 즉시 표시)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('$_anonTitlePrefsPrefix${widget.conversationId}', normalized);
      } catch (_) {}

      // 대화방 문서에 dmContent가 비어있을 때만 best-effort로 업데이트 (목록도 같이 정상화)
      final convRef = FirebaseFirestore.instance.collection('conversations').doc(_activeConversationId);
      final convDoc = await convRef.get();
      if (convDoc.exists) {
        final data = convDoc.data() as Map<String, dynamic>;
        final existing = (data['dmContent'] as String?)?.trim() ?? '';
        if (existing.isEmpty) {
          try {
            await convRef.update({'dmContent': normalized});
          } catch (e) {
            // Rules 상 업데이트가 막혀도 UI는 게시글에서 직접 가져와 표시하면 됨
            Logger.error('dmContent 백필 업데이트 실패(무시): $e');
          }
        }
      }

      _backfilledPostId = postId;
    } catch (e) {
      Logger.error('dmContent 백필 실패(무시): $e');
      _backfilledPostId = postId;
    }
  }
  Future<void> _initConversationState() async {
    try {
      if (mounted) {
        setState(() {
          _isConversationInitializing = true;
          _conversationExists = null;
        });
      }
      
      // Firebase Auth UID 형식 검증 (20~30자 영숫자, 언더스코어 포함 가능)
      final uidPattern = RegExp(r'^[a-zA-Z0-9_-]{20,30}$');
      if (!uidPattern.hasMatch(widget.otherUserId)) {
        Logger.log('❌ 잘못된 userId 형식: ${widget.otherUserId} (길이: ${widget.otherUserId.length}자)');
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Localizations.localeOf(context).languageCode == 'ko'
                    ? '이 사용자에게는 메시지를 보낼 수 없습니다'
                    : 'Cannot send message to this user'
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      // DM conversation ID 형식 검증 (타임스탬프 포함 형식도 지원)
      final validIdPattern = RegExp(r'^(anon_)?[a-zA-Z0-9_-]+_[a-zA-Z0-9_-]+(_[a-zA-Z0-9_-]+)?(_\d{13})?(__\d+)?$');
      if (!validIdPattern.hasMatch(_activeConversationId)) {
        Logger.log('❌ 잘못된 conversation ID 형식: $_activeConversationId');
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)!.error}: 잘못된 대화방 ID입니다'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }
      
      final convRef = FirebaseFirestore.instance
          .collection('conversations')
          .doc(_activeConversationId);

      // 0) Firestore 로컬 캐시 우선으로 빠르게 존재 여부를 판단 (재진입 UX 개선)
      DocumentSnapshot<Map<String, dynamic>>? cachedConv;
      try {
        cachedConv = await convRef.get(const GetOptions(source: Source.cache));
      } catch (_) {
        cachedConv = null;
      }

      if (cachedConv != null && cachedConv.exists) {
        _conversationExists = true;
        if (mounted) {
          setState(() {
            // 캐시에 존재하면 메시지/캐시 로딩을 바로 시작하고 스켈레톤을 빨리 해제한다.
            _isConversationInitializing = false;
          });
        }
        // 메시지/대화방 로딩은 백그라운드에서 진행 (UI 블로킹 방지)
        unawaited(_initializeMessagesStream(conversationId: _activeConversationId));
        unawaited(_loadConversation());
        unawaited(_markAsRead());
      }

      // 1) 서버로 최종 확인 (권한/참여자 검증 포함)
      final conv = await convRef.get(const GetOptions(source: Source.server));

      _conversationExists = conv.exists;
      if (mounted) setState(() {});
      
      // 대화방이 존재하지 않으면 메시지 전송 시까지 대기
      if (_conversationExists == false) {
        
        // 본인 DM 체크
        if (widget.otherUserId == _currentUser?.uid) {
          Logger.log('❌ 본인 DM 생성 시도 차단');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '본인에게는 메시지를 보낼 수 없습니다'
                      : 'Cannot send message to yourself'
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        
        // 대화방이 없으면 생성하지 않고 대기 상태로 설정
      }
      
      // 참여자 확인 (대화방이 이미 존재했던 경우에만)
      if (_conversationExists == true && conv.exists) {
        final data = conv.data() as Map<String, dynamic>;
        final participants = List<String>.from(data['participants'] ?? []);
        
        // 본인이 본인에게 보낸 DM 체크
        final isSelfDM = participants.length == 2 && 
                        participants[0] == _currentUser?.uid && 
                        participants[1] == _currentUser?.uid;
        
        if (isSelfDM) {
          Logger.log('❌ 본인 DM은 허용되지 않음');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '본인에게는 메시지를 보낼 수 없습니다'
                      : 'Cannot send message to yourself'
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        
        if (!participants.contains(_currentUser?.uid)) {
          Logger.log('❌ 대화방 참여자가 아님');
          if (mounted) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${AppLocalizations.of(context)!.error}: 대화방 참여자가 아닙니다'),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          return;
        }
      }
      
      // 대화방이 존재하면 정상 진행
      if (_conversationExists == true) {
        // 이미 캐시 경로에서 시작했을 수 있으므로, 중복 구독/중복 로딩을 피하기 위해
        // 메시지 스트림이 아직 없다면 시작한다.
        if (_recentMessagesSub == null) {
          unawaited(_initializeMessagesStream(conversationId: _activeConversationId));
        }
        unawaited(_loadConversation());
        unawaited(_markAsRead());
      }
    } catch (e) {
      Logger.error('대화 초기화 오류: $e');
      Logger.error('오류 상세: ${e.runtimeType} - ${e.toString()}');
      // 권한 오류인 경우 뒤로가기
      if (e.toString().contains('permission-denied')) {
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)!.error}: 접근 권한이 없습니다'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isConversationInitializing = false;
        });
      }
    }
  }


  @override
  void dispose() {
    _autoMarkReadDebounce?.cancel();
    _recentMessagesSub?.cancel();
    _messageController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleAutoMarkAsRead(List<DMMessage> messages) {
    if (!mounted) return;
    final me = _currentUser;
    if (me == null) return;
    if (_isLeaving) return;
    if (_autoMarkReadInFlight) return;

    // 상대방이 보낸 "안 읽음" 메시지가 있으면, 채팅 화면이 열려 있는 동안 즉시 읽음 처리
    final hasUnreadIncoming = messages.any((m) => m.senderId != me.uid && !m.isRead);
    if (!hasUnreadIncoming) return;

    _autoMarkReadDebounce?.cancel();
    _autoMarkReadDebounce = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted) return;
      if (_autoMarkReadInFlight) return;
      _autoMarkReadInFlight = true;
      try {
        await _dmService.markAsRead(_activeConversationId);
      } catch (_) {
        // best-effort
      } finally {
        _autoMarkReadInFlight = false;
      }
    });
  }

  /// 대화방 정보 로드
  Future<void> _loadConversation() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(_activeConversationId)
          .get();
      
      if (doc.exists && mounted) {
        setState(() {
          _conversation = Conversation.fromFirestore(doc);
        });

        // 익명 게시글 DM의 경우: dmContent가 없으면 게시글에서 본문을 가져와 1회 백필
        final conv = _conversation;
        if (conv != null &&
            conv.postId != null &&
            conv.postId!.isNotEmpty &&
            conv.isOtherUserAnonymous(_currentUser!.uid)) {
          final existingContent = (conv.dmContent ?? '').trim();
          if (existingContent.isEmpty) {
            await _ensureDmContentBackfilled(postId: conv.postId!);
          } else if (_preloadedDmContent == null || _preloadedDmContent!.isEmpty) {
            // 이미 dmContent가 있으면 프리로드에도 반영
            if (mounted) {
              setState(() {
                _preloadedDmContent = existingContent;
              });
            }
          }
        }
      }
    } catch (e) {
      Logger.error('대화방 정보 로드 오류: $e');
    }
  }

  /// 메시지 스트림 초기화
  /// - 기본: 전체 대화 표시(일반 진입)
  /// - 예외: 사용자가 실제로 '채팅방 나가기'를 한 기록이 있으면, 그 시점 이후만 표시
  Future<void> _initializeMessagesStream({String? conversationId}) async {
    try {
      final targetConversationId = conversationId ?? _activeConversationId;
      _activeConversationId = targetConversationId;

      // 사용자가 실제로 '나가기'를 한 적이 있으면 해당 시점 이후만 표시
      final visibilityStartTime = await _dmService.getUserMessageVisibilityStartTime(targetConversationId);
      _visibilityStartTime = visibilityStartTime;

      // 1) 로컬 캐시를 먼저 읽어 즉시 렌더링 (문자앱 UX)
      setState(() {
        _isMessagesLoading = true;
        _messagesError = null;
        _hasMore = true;
      });
      final cached = await _dmService.loadCachedMessages(
        targetConversationId,
        limit: _initialCacheLimit,
        visibilityStartTime: visibilityStartTime,
      );
      if (mounted && cached.isNotEmpty) {
        setState(() {
          _messages = cached..sort(_compareMessagesDesc);
        });
      }

      // 2) 서버 최근 N개 스트림 구독 + 로컬 캐시 저장
      await _recentMessagesSub?.cancel();
      _recentMessagesSub = _dmService
          .watchRecentMessagesAndCache(
            targetConversationId,
            limit: _recentLimit,
            visibilityStartTime: visibilityStartTime,
          )
          .listen((recent) {
        if (!mounted) return;
        setState(() {
          _messages = _mergeRecentIntoAll(recent, _messages);
          _isMessagesLoading = false;
        });
      }, onError: (e) {
        if (!mounted) return;
        setState(() {
          _messagesError = e;
          _isMessagesLoading = false;
        });
      });
    } catch (e) {
      Logger.error('메시지 스트림 초기화 실패: $e');
      if (!mounted) return;
      setState(() {
        _messagesError = e;
        _isMessagesLoading = false;
      });
    }
  }

  int _compareMessagesDesc(DMMessage a, DMMessage b) {
    final t = b.createdAt.compareTo(a.createdAt);
    if (t != 0) return t;
    return b.id.compareTo(a.id);
  }

  List<DMMessage> _mergeRecentIntoAll(List<DMMessage> recent, List<DMMessage> existingAll) {
    final byId = <String, DMMessage>{};
    for (final m in existingAll) {
      byId[m.id] = m;
    }
    for (final m in recent) {
      byId[m.id] = m;
    }
    final merged = byId.values.toList(growable: false)..sort(_compareMessagesDesc);
    // 메모리 상한: 너무 오래 열어두거나 과거를 많이 불러와도 과도한 메모리 사용을 방지
    const int hardCap = 800;
    if (merged.length > hardCap) {
      return merged.take(hardCap).toList(growable: false);
    }
    return merged;
  }

  void _onScroll() {
    if (!mounted) return;
    if (_conversationExists != true) return;
    if (_isLoadingMore) return;
    if (!_hasMore) return;
    if (_isConversationInitializing) return;
    if (_messages.isEmpty) return;
    if (!_scrollController.hasClients) return;

    // reverse=true에서 "더 과거(위)"로 스크롤할수록 pixels가 maxScrollExtent에 가까워진다.
    const threshold = 240.0;
    final pos = _scrollController.position;
    // ✅ 중요: 초기 attach/레이아웃 단계에서 maxScrollExtent가 0인 경우,
    // pos.pixels(대개 0)가 조건을 만족해 자동으로 과거 페이지를 연쇄 로드할 수 있다.
    // "사용자가 실제로 스크롤했을 때만" 과거 로드를 트리거한다.
    if (pos.maxScrollExtent <= 0) return;
    if (pos.userScrollDirection == ScrollDirection.idle) return;

    if (pos.pixels >= (pos.maxScrollExtent - threshold)) {
      _loadMoreMessages();
    }
  }

  Future<void> _loadMoreMessages() async {
    if (!mounted) return;
    if (_conversationExists != true) return;
    if (_isLoadingMore) return;
    if (!_hasMore) return;
    if (_messages.isEmpty) return;

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final before = _messages.last.createdAt; // 가장 오래된 메시지보다 더 과거를 로드
      final older = await _dmService.fetchOlderMessages(
        _activeConversationId,
        before: before,
        limit: _pageSize,
        visibilityStartTime: _visibilityStartTime,
      );

      if (!mounted) return;

      if (older.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoadingMore = false;
        });
        return;
      }

      setState(() {
        _messages = _mergeRecentIntoAll(older, _messages);
        _isLoadingMore = false;
        if (older.length < _pageSize) {
          _hasMore = false;
        }
      });
    } catch (e) {
      Logger.error('이전 메시지 로드 실패(무시): $e');
      if (!mounted) return;
      setState(() {
        _isLoadingMore = false;
      });
    }
  }

  Widget _buildLoadMoreIndicator() {
    if (_isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    // 버튼은 제거하고(요청사항), 스크롤 자동 로드만 사용한다.
    return const SizedBox.shrink();
  }

  /// 읽음 처리
  Future<void> _markAsRead() async {
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await _dmService.markAsRead(_activeConversationId);
      
      // UI 강제 업데이트를 위해 스트림 재초기화
      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      Logger.error('⚠️ 읽음 처리 중 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentUser == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.dm ?? "")),
        body: Center(
          child: Text(AppLocalizations.of(context)!.loginRequired ?? ""),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // 익명 게시글 DM인 경우에만 게시글로 돌아가기 배너 추가
          if (_conversation != null && 
              _conversation!.postId != null && 
              _conversation!.postId!.isNotEmpty &&
              _conversation!.isOtherUserAnonymous(_currentUser!.uid))
            _buildPostNavigationBanner(),
          Expanded(child: _buildMessageList()),
          _buildInputArea(),
        ],
      ),
    );
  }

  bool get _isAnonymous {
    return _activeConversationId.startsWith('anon_') || 
        (_conversation?.isOtherUserAnonymous(_currentUser!.uid) ?? false);
  }

  /// AppBar 빌드
  PreferredSizeWidget _buildAppBar() {
    final otherUserId = widget.otherUserId;
    final dmContent = (_conversation?.dmContent ?? _preloadedDmContent)?.trim();
    final postId = _conversation?.postId ?? _extractPostIdFromConversationId(_activeConversationId);
    final isPostBasedAnonymous = _isAnonymous && (postId != null && postId.isNotEmpty);
    
    // ⏳ 로딩 상태: 데이터가 준비되지 않았을 때
    if (_conversation == null && (dmContent == null || dmContent.isEmpty)) {
      final l10n = AppLocalizations.of(context)!;
      final resolvedName = _isAnonymous
          ? (l10n.anonymous ?? 'Anonymous')
          : (_serverOtherUserInfo?.nickname ?? '');
      final resolvedPhotoUrl = _isAnonymous ? '' : (_serverOtherUserInfo?.photoURL ?? '');
      final resolvedPhotoVersion = _isAnonymous ? 0 : (_serverOtherUserInfo?.photoVersion ?? 0);

      return AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            // 대화방이 없어도 상대 프로필을 먼저 보여준다(오류 오해 방지)
            UserAvatar(
              uid: otherUserId,
              photoUrl: resolvedPhotoUrl,
              photoVersion: resolvedPhotoVersion,
              isAnonymous: _isAnonymous,
              size: 36,
              placeholderColor: const Color(0xFFE5E7EB),
              placeholderIconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: resolvedName.trim().isNotEmpty
                  ? Text(
                      resolvedName.trim(),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : Container(
                      width: 120,
                      height: 16,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
            ),
          ],
        ),
      );
    }

    // 🎯 익명 게시글 DM: AppBar 제목을 "게시글 본문"으로 표시
    if (isPostBasedAnonymous) {
      final primaryTitle = (dmContent != null && dmContent.isNotEmpty)
          ? dmContent
          : AppLocalizations.of(context)!.anonymous;
      final secondaryTitle = AppLocalizations.of(context)!.anonymous;

      String _formatHeaderDate() {
        final date = _conversation?.lastMessageTime ?? _conversation?.createdAt;
        if (date == null) return '';
        return DateFormat('yyyy.MM.dd').format(date);
      }

      return AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: Colors.grey[200],
              child: const Icon(Icons.person, size: 20),  // 익명이므로 기본 아이콘
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    primaryTitle,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    secondaryTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                    ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Text(
              _formatHeaderDate(),
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.black87),
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 4,
            color: Colors.white,
            surfaceTintColor: Colors.white,
            offset: const Offset(0, 8),
            onSelected: (value) {
              if (value == 'leave') {
                _confirmLeaveConversation();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'leave',
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF6B7280).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.exit_to_app,
                        size: 16,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      AppLocalizations.of(context)!.leaveChatRoom ?? "채팅방 나가기",
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      );
    }
    
    // 초기 표시 값을 캐시 상태에 따라 조건부로 설정
    // - ⚠️ 대화방(_conversation)이 아직 로드되지 않은 상태에서는 "탈퇴 계정"으로 판단하지 않는다.
    //   (이 오판 때문에 'Deleted Account'가 잠깐 보였다가 사라지는 플리커가 발생할 수 있음)
    final hasCachedConversation = _conversation != null;
    final cachedStatus = _conversation?.participantStatus[otherUserId];
    final cachedName = _conversation?.getOtherUserName(_currentUser!.uid) ?? '';
    final deletedLabel = AppLocalizations.of(context)!.deletedAccount ?? 'Deleted Account';
    
    // 익명이 아닐 때만 탈퇴 계정 체크
    final isCachedDeleted = !_isAnonymous && hasCachedConversation && (
        cachedStatus == 'deleted' ||
        cachedName.isEmpty ||
        cachedName == 'DELETED_ACCOUNT' ||
        cachedName == deletedLabel
    );

    // 서버 최신값을 백그라운드로 확보 (옛 값 노출 방지)
    if (!_isAnonymous && !isCachedDeleted) {
      _ensureServerOtherUserInfo(otherUserId);
    }

    // 실시간으로 사용자 정보 조회 (일반 DM만)
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: StreamBuilder<DMUserInfo?>(
        stream: (_isAnonymous || isCachedDeleted) ? null : _otherUserInfoStream,
        // 캐시 기반 초기값을 UI에 노출하지 않는다(플리커 방지)
        initialData: null,
        builder: (context, snapshot) {
          final info = snapshot.data;
          final DMUserInfo? freshFromStream =
              (info != null && info.isFromCache == false) ? info : null;
          final DMUserInfo? resolved = _serverOtherUserInfo ?? freshFromStream;
          final bool isUserInfoReady = resolved != null;

          final otherUserName = (isCachedDeleted || resolved == null)
              ? (isCachedDeleted ? deletedLabel : '')
              : (resolved.nickname == 'DELETED_ACCOUNT' ? deletedLabel : resolved.nickname);
          
          // photoURL이 있으면 표시하되, 캐시 스냅샷은 노출하지 않는다.
          final otherUserPhoto = (isCachedDeleted || resolved == null) ? '' : resolved.photoURL;
          final otherUserPhotoVersion =
              (isCachedDeleted || resolved == null) ? 0 : resolved.photoVersion;
          
          final primaryTitle =
              _isAnonymous ? AppLocalizations.of(context)!.anonymous : otherUserName;
          final secondaryTitle = null;

    String _formatHeaderDate() {
      final date = _conversation?.lastMessageTime ?? _conversation?.createdAt;
      if (date == null) return '';
      return DateFormat('yyyy.MM.dd').format(date);
    }

          return AppBar(
            elevation: 0,
            backgroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                UserAvatar(
                  uid: otherUserId,
                  photoUrl: otherUserPhoto,
                  photoVersion: otherUserPhotoVersion,
                  isAnonymous: _isAnonymous,
                  size: 36,
                  placeholderColor: const Color(0xFFE5E7EB),
                  placeholderIconSize: 20,
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_isAnonymous && !isCachedDeleted && !isUserInfoReady)
                  Container(
                    width: 140,
                    height: 14,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                else
                  Text(
                    primaryTitle,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (secondaryTitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    secondaryTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_conversation != null) ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Text(
                _formatHeaderDate(),
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.black87),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
          color: Colors.white,
          surfaceTintColor: Colors.white,
          offset: const Offset(0, 8),
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'block',
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.block,
                      size: 16,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)!.blockThisUser ?? "",
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(height: 1),
            PopupMenuItem(
              value: 'delete',
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF6B7280).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.exit_to_app,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    AppLocalizations.of(context)!.leaveChatRoom,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'block') {
              _showBlockConfirmation();
            } else if (value == 'delete') {
              _confirmLeaveConversation();
            }
          },
        ),
      ],
    );
        },
      ),
    );
  }

  /// 채팅방 보관(삭제) - 서버 플래그 기반
  Future<void> _archiveConversation() async {
    try {
      await _dmService.archiveConversation(_activeConversationId);
      if (!mounted) return;
      Navigator.pop(context);
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      AppSnackBar.show(
        context,
        message: isKo
            ? '채팅방이 목록에서 삭제되었습니다'
            : 'This chat has been removed from your list.',
        type: AppSnackBarType.info,
      );
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: '${AppLocalizations.of(context)!.error}: $e',
        type: AppSnackBarType.error,
      );
    }
  }

  /// 나가기 확인 다이얼로그
  Future<void> _confirmLeaveConversation() async {
    // 중요한 액션임을 알림 (로그아웃 다이얼로그와 동일 UX)
    HapticFeedback.mediumImpact();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final l10n = AppLocalizations.of(dialogContext)!;
        final isKo = Localizations.localeOf(dialogContext).languageCode == 'ko';

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          elevation: 8,
          contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
          title: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: BrandColors.error.withAlpha(26),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  color: BrandColors.error,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                l10n.leaveChatRoom,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ],
          ),
          content: Text(
            isKo ? '이 채팅방에서 나가시겠습니까?' : 'Are you sure you want to leave this chat?',
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF374151),
              height: 1.5,
            ),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(dialogContext).pop(false);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade300, width: 1),
                      ),
                      backgroundColor: Colors.white,
                    ),
                    child: Text(
                      l10n.cancel ?? '',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6B7280),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      HapticFeedback.heavyImpact();
                      Navigator.of(dialogContext).pop(true);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      backgroundColor: BrandColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      disabledBackgroundColor: const Color(0xFFE5E7EB),
                    ),
                    child: Text(
                      isKo ? '나가기' : 'Leave',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _leaveConversation();
    }
  }

  /// 대화방 나가기
  Future<void> _leaveConversation() async {
    try {
      // 스트림을 먼저 해제해 나간 직후 권한 오류가 토스트로 보이지 않게 한다
      if (mounted) {
        setState(() {
          _isLeaving = true;
          _recentMessagesSub?.cancel();
          _recentMessagesSub = null;
          _messages = <DMMessage>[];
          _messagesError = null;
        });
      }

      await _dmService.leaveConversation(_activeConversationId);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '채팅방에서 나갔습니다. 다시 메시지를 보내면 이전 대화 내역은 보이지 않습니다.'
                : 'You left the chat. Previous messages will not be visible if you send a new message.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      Logger.error('대화방 나가기 오류: $e');
      
      // 오류가 발생해도 사용자에게는 성공적으로 나간 것처럼 처리 (인스타그램 방식)
      Logger.error('오류 발생했지만 사용자 경험을 위해 성공 처리');
      
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '채팅방에서 나갔습니다'
                : 'You left the chat',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLeaving = false;
        });
      }
    }
  }

  /// 메시지 목록 빌드
  Widget _buildMessageList() {
    // ✅ 대화방이 없다고 확정되기 전까지는(초기화 중) '없음' 문구 대신 스켈레톤을 유지한다.
    if (_conversationExists == false && !_isConversationInitializing) {
      return _buildStartConversationPlaceholder(isConversationCreated: false);
    }

    // ✅ 초기화/존재 확인 중이라도, 메시지가 이미 있으면(로컬 캐시 등) 바로 렌더링한다.
    if ((_isConversationInitializing || _conversationExists == null) && _messages.isEmpty) {
      return _buildConversationLoadingSkeleton();
    }

    if (_messagesError != null) {
      Logger.error('❌ 메시지 로드 오류: $_messagesError');
      final errorMessage = _messagesError.toString();
      if (errorMessage.contains('permission-denied')) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_outline, size: 64, color: Colors.red[300]),
                const SizedBox(height: 16),
                Text(
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '권한 오류'
                      : 'Permission Error',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? 'Firebase Security Rules가 배포되지 않았거나\n권한이 없습니다.\n\n앱을 다시 시작해주세요.'
                      : 'Firebase Security Rules are not deployed\nor you don\'t have permission.\n\nPlease restart the app.',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      return Center(
        child: Text(
          '${AppLocalizations.of(context)!.error}: $_messagesError',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }

    if (_isMessagesLoading && _messages.isEmpty) {
      return _buildConversationLoadingSkeleton();
    }

    final messages = _messages;
    if (messages.isEmpty) {
      // 대화방 존재 확인이 끝나지 않았으면 스켈레톤을 유지한다.
      if (_conversationExists == null || _isConversationInitializing) {
        return _buildConversationLoadingSkeleton();
      }
      return _buildStartConversationPlaceholder(isConversationCreated: true);
    }

    // ✅ 실시간 채팅 중에도 읽음 상태를 서버에 반영
    _scheduleAutoMarkAsRead(messages);

    // ✅ 읽음/안읽음 표시는 "최신 안읽음 1개 + 최신 읽음 1개"만 노출
    final myUid = _currentUser!.uid;
    String? latestMyUnreadMessageId;
    String? latestMyReadMessageId;
    for (final m in messages) {
      if (m.senderId != myUid) continue;
      if (!m.isRead && latestMyUnreadMessageId == null) {
        latestMyUnreadMessageId = m.id;
      } else if (m.isRead && latestMyReadMessageId == null) {
        latestMyReadMessageId = m.id;
      }
      if (latestMyUnreadMessageId != null && latestMyReadMessageId != null) break;
    }

    String? _statusFor(DMMessage m) {
      if (m.senderId != myUid) return null;
      if (m.id == latestMyUnreadMessageId) return '1';
      if (m.id == latestMyReadMessageId) return AppLocalizations.of(context)!.read;
      return null;
    }

    final timeLabels = List<String>.generate(
      messages.length,
      (i) => TimeFormatter.formatMessageTime(context, messages[i].createdAt),
      growable: false,
    );
    final statusLabels = List<String?>.generate(
      messages.length,
      (i) => _statusFor(messages[i]),
      growable: false,
    );

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      reverse: true,
      itemCount: messages.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        // reverse=true에서 "마지막 인덱스"는 화면 상단(가장 과거) 영역에 위치한다.
        if (_hasMore && index == messages.length) {
          return _buildLoadMoreIndicator();
        }

        final message = messages[index];
        final isMine = message.isMine(_currentUser!.uid);
        final String? statusText = statusLabels[index];

        // 시간/읽음 라벨은 동일 내용이 연속될 때 마지막(더 최신) 1개만 노출
        final String timeText = timeLabels[index];
        final String? prevTimeText = index > 0 ? timeLabels[index - 1] : null;
        final String? prevStatusText = index > 0 ? statusLabels[index - 1] : null;
        final bool showTimeText = prevTimeText == null || timeText != prevTimeText;
        final bool showStatusText =
            statusText != null && (prevStatusText == null || statusText != prevStatusText);

        // 같은 발신자의 연속 메시지인지 확인
        final isConsecutive = index < messages.length - 1 &&
            messages[index + 1].senderId == message.senderId;

        // 날짜 구분선 표시 여부 확인 (해당 날짜의 첫 메시지 위에 표시)
        final showDateSeparator = index == messages.length - 1 ||
            !_isSameDay(message.createdAt, messages[index + 1].createdAt);

        return Column(
          children: [
            if (showDateSeparator) _buildDateSeparator(message.createdAt),
            _buildMessageBubble(
              message,
              isMine,
              isConsecutive,
              timeText: timeText,
              showTimeText: showTimeText,
              statusText: statusText,
              showStatusText: showStatusText,
            ),
          ],
        );
      },
    );
  }

  Widget _buildConversationLoadingSkeleton() {
    // "대화방 없음" 문구가 먼저 보이는 UX를 방지하기 위한 초기 로딩 스켈레톤
    // - Shimmer 의존성을 추가하지 않고, 가벼운 회색 버블 6개만 렌더링한다.
    final base = Colors.grey.shade200;
    final base2 = Colors.grey.shade100;
    final widths = <double>[0.62, 0.48, 0.72, 0.40, 0.66, 0.52];

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      itemCount: widths.length,
      itemBuilder: (context, i) {
        final isMine = i.isEven;
        final w = MediaQuery.of(context).size.width * widths[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Align(
            alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: w,
              height: 16 + (i % 3) * 10,
              decoration: BoxDecoration(
                color: isMine ? base : base2,
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStartConversationPlaceholder({
    required bool isConversationCreated,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    final resolvedName = _isAnonymous
        ? (l10n.anonymous ?? 'Anonymous')
        : (_serverOtherUserInfo?.nickname.trim().isNotEmpty == true
            ? _serverOtherUserInfo!.nickname.trim()
            : '');

    final resolvedPhotoUrl = _isAnonymous ? '' : (_serverOtherUserInfo?.photoURL ?? '');
    final resolvedPhotoVersion = _isAnonymous ? 0 : (_serverOtherUserInfo?.photoVersion ?? 0);

    final title = resolvedName.isNotEmpty
        ? (isKo ? '$resolvedName님과 대화를 시작해보세요' : 'Start a chat with $resolvedName')
        : (isKo ? '대화를 시작해보세요' : 'Start a chat');

    final subtitle = isKo
        ? '첫 메시지를 보내면 대화방이 자동으로 생성되고\n여기서 계속 대화할 수 있어요.'
        : 'Send your first message to create the chat,\nthen continue the conversation here.';

    final hint = isKo
        ? (isConversationCreated
            ? '대화가 시작되면 여기에 메시지가 표시됩니다.'
            : '아직 대화방이 없어요. 메시지를 보내면 시작됩니다.')
        : (isConversationCreated
            ? 'Messages will appear here once the chat starts.'
            : 'No chat yet. Send a message to start.');

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            UserAvatar(
              uid: widget.otherUserId,
              photoUrl: resolvedPhotoUrl,
              photoVersion: resolvedPhotoVersion,
              isAnonymous: _isAnonymous,
              size: 72,
              placeholderColor: const Color(0xFFE5E7EB),
              placeholderIconSize: 28,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B7280),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4B5563),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 같은 날짜인지 확인
  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }

  /// 날짜 구분선 빌드
  Widget _buildDateSeparator(DateTime date) {
    final weekdays = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];
    final weekday = weekdays[date.weekday - 1];
    final dateText = '${date.month}월 ${date.day}일 $weekday';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      alignment: Alignment.center,
      child: Text(
        dateText,
        style: TextStyle(
          color: Colors.grey[500],
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 메시지 버블 빌드
  Widget _buildMessageBubble(
    DMMessage message,
    bool isMine,
    bool isConsecutive, {
    required String timeText,
    bool showTimeText = true,
    String? statusText,
    bool showStatusText = true,
  }) {
    // 게시글 컨텍스트는 postId만 있어도 카드로 노출한다.
    final hasPostContext =
        (message.postId != null && message.postId!.trim().isNotEmpty);
    final hasImage = message.imageUrl != null && message.imageUrl!.isNotEmpty;
    final hasText = message.text.trim().isNotEmpty;
    // 게시글 컨텍스트가 있으면 "이미지 단독"으로 취급하지 않음 (컨텍스트 카드도 함께 렌더링)
    final isImageOnly = hasImage && !hasText && !hasPostContext;

    if (isMine) {
      return Padding(
        padding: EdgeInsets.only(
          left: 60,
          right: 12,
          top: isConsecutive ? 2 : 8,
          bottom: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 시간과 읽음 표시
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Visibility(
                  visible: showTimeText,
                  maintainAnimation: true,
                  maintainSize: true,
                  maintainState: true,
                  child: Text(
                    timeText,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                ),
                if (statusText != null)
                  Visibility(
                    visible: showStatusText,
                    maintainAnimation: true,
                    maintainSize: true,
                    maintainState: true,
                    child: Text(
                      statusText,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            // 메시지 버블 (이미지만 있으면 테두리 없음)
            Flexible(
              child: isImageOnly
                  ? _buildImageBubble(
                      imageUrl: message.imageUrl!,
                      isMine: true,
                      heroTag: 'dm_image_${widget.conversationId}_${message.id}',
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(
                        color: DMColors.myMessageBg,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(18),
                          bottomRight: Radius.circular(4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (hasPostContext) ...[
                            _buildPostContextCard(message, isMine: true),
                            if (hasImage || hasText) const SizedBox(height: 8),
                          ],
                          if (hasImage) ...[
                            _buildImageBubble(
                              imageUrl: message.imageUrl!,
                              isMine: true,
                              heroTag: 'dm_image_${widget.conversationId}_${message.id}',
                            ),
                            if (hasText) const SizedBox(height: 8),
                          ],
                          if (hasText)
                            Text(
                              message.text,
                              style: const TextStyle(
                                color: DMColors.myMessageText,
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      );
    } else {
      return Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 60,
          top: isConsecutive ? 2 : 8,
          bottom: 2,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // 메시지 버블 (이미지만 있으면 테두리 없음)
            Flexible(
              child: isImageOnly
                  ? _buildImageBubble(
                      imageUrl: message.imageUrl!,
                      isMine: false,
                      heroTag: 'dm_image_${widget.conversationId}_${message.id}',
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: const BoxDecoration(
                        color: DMColors.otherMessageBg,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (hasPostContext) ...[
                            _buildPostContextCard(message, isMine: false),
                            if (hasImage || hasText) const SizedBox(height: 8),
                          ],
                          if (hasImage) ...[
                            _buildImageBubble(
                              imageUrl: message.imageUrl!,
                              isMine: false,
                              heroTag: 'dm_image_${widget.conversationId}_${message.id}',
                            ),
                            if (hasText) const SizedBox(height: 8),
                          ],
                          if (hasText)
                            Text(
                              message.text,
                              style: const TextStyle(
                                color: DMColors.otherMessageText,
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(width: 6),
            // 시간 표시
            Visibility(
              visible: showTimeText,
              maintainAnimation: true,
              maintainSize: true,
              maintainState: true,
              child: Text(
                timeText,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 11,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildPostContextCard(DMMessage message, {required bool isMine}) {
    final postId = message.postId?.trim() ?? '';
    final img = (message.postImageUrl?.trim().isNotEmpty ?? false)
        ? message.postImageUrl!.trim()
        : '';
    final preview = (message.postPreview ?? '').trim();
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final borderColor = isMine ? Colors.white.withOpacity(0.35) : Colors.grey.shade300;

    return GestureDetector(
      onTap: postId.isEmpty ? null : () => _navigateToPost(postId),
      child: Container(
        decoration: BoxDecoration(
          color: isMine ? Colors.white.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (img.isNotEmpty)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    fadeOutDuration: const Duration(milliseconds: 150),
                    placeholder: (_, __) => _buildMediaPlaceholder(
                      isMine: isMine,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      child: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (_, __, ___) => _buildMediaPlaceholder(
                      isMine: isMine,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                      child: Icon(
                        Icons.image_outlined,
                        size: 20,
                        color: isMine ? Colors.white70 : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.article_outlined,
                        size: 16,
                        color: isMine ? Colors.white70 : Colors.grey.shade700,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isKo ? '게시글에서 보낸 메시지' : 'Sent from a post',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isMine ? Colors.white70 : Colors.grey.shade800,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (postId.isNotEmpty)
                        Text(
                          isKo ? '보기' : 'View',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isMine ? Colors.white : Colors.blue.shade700,
                          ),
                        ),
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      preview,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: isMine ? Colors.white : Colors.grey.shade800,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageBubble({
    required String imageUrl,
    required bool isMine,
    required String heroTag,
  }) {
    const maxWidth = 240.0;
    const maxHeight = 240.0;

    return GestureDetector(
      onTap: () => _openImageViewer(imageUrl, heroTag: heroTag),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: maxWidth,
            maxHeight: maxHeight,
          ),
          child: Hero(
            tag: heroTag,
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              fit: BoxFit.cover,
              fadeInDuration: const Duration(milliseconds: 150),
              fadeOutDuration: const Duration(milliseconds: 150),
              placeholder: (_, __) => _buildMediaPlaceholder(
                isMine: isMine,
                borderRadius: BorderRadius.circular(14),
                child: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              errorWidget: (_, __, ___) => _buildMediaPlaceholder(
                isMine: isMine,
                borderRadius: BorderRadius.circular(14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      size: 18,
                      color: isMine ? Colors.white70 : Colors.grey[600],
                    ),
                    const SizedBox(width: 6),
                    Text(
                      Localizations.localeOf(context).languageCode == 'ko'
                          ? '이미지 로드 실패'
                          : 'Failed to load image',
                      style: TextStyle(
                        fontSize: 12,
                        color: isMine ? Colors.white70 : Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMediaPlaceholder({
    required bool isMine,
    required BorderRadius borderRadius,
    required Widget child,
  }) {
    final bg = isMine ? Colors.white.withOpacity(0.16) : const Color(0xFFF3F4F6);
    final border =
        isMine ? Colors.white.withOpacity(0.22) : Colors.black.withOpacity(0.06);
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: borderRadius,
        border: Border.all(color: border),
      ),
      alignment: Alignment.center,
      child: child,
    );
  }

  void _openImageViewer(String imageUrl, {required String heroTag}) {
    // 다른 페이지(게시글/후기 등)와 동일한 전체화면 이미지 뷰어 사용
    showFullscreenImageViewer(
      context,
      imageUrls: [imageUrl],
      initialIndex: 0,
      heroTag: heroTag,
    );
  }

  /// 입력창 빌드
  Widget _buildInputArea() {
    final canSend = !_isBlocked &&
        !_isBlockedBy &&
        !_isLoading &&
        (_messageController.text.trim().isNotEmpty || _pendingImage != null);

    final originPostId = (widget.originPostId ?? '').trim();
    final shouldShowComposerPostContext = originPostId.isNotEmpty &&
        !_originPostContextAttached &&
        !_composerPostContextDismissed;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✅ 게시글에서 DM으로 진입한 경우: "보내기 전" 컨텍스트 미리보기 카드
            // - 사용자는 메시지를 입력한 뒤 전송할 수 있고,
            // - 첫 전송 시에만 실제 메시지에 post_context로 부착된다.
            if (shouldShowComposerPostContext) ...[
              _buildComposerPostContextPreview(),
              const SizedBox(height: 8),
            ],
            if (_conversationExists == false &&
                !_isAnonymous &&
                !_isBlocked &&
                !_isBlockedBy) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  Localizations.localeOf(context).languageCode == 'ko'
                      ? '첫 메시지를 보내면 대화방이 생성돼요.'
                      : 'Send your first message to create this chat.',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_pendingImage != null) ...[
              _buildAttachmentPreview(),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 첨부 버튼 (+)
                InkWell(
                  onTap: (_isBlocked || _isBlockedBy || _isLoading) ? null : _pickImage,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (_isBlocked || _isBlockedBy || _isLoading) ? Colors.grey[200] : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.grey[300]!, width: 1),
                    ),
                    child: Icon(
                      Icons.add,
                      color: (_isBlocked || _isBlockedBy || _isLoading) ? Colors.grey[400] : Colors.grey[700],
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 120),
                    decoration: BoxDecoration(
                      color: (_isBlocked || _isBlockedBy) ? Colors.grey[200] : DMColors.inputBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: DMColors.inputBorder, width: 0.5),
                    ),
                    child: TextField(
                      controller: _messageController,
                      enabled: !_isBlocked && !_isBlockedBy && !_isLoading,
                      maxLines: null,
                      maxLength: 500,
                      textInputAction: TextInputAction.newline,
                      decoration: InputDecoration(
                        hintText: (_isBlocked || _isBlockedBy)
                            ? '차단된 사용자에게 메시지를 보낼 수 없습니다'
                            : AppLocalizations.of(context)!.typeMessage,
                        hintStyle: TextStyle(
                          color: (_isBlocked || _isBlockedBy) ? Colors.grey[600] : Colors.grey[500],
                          fontSize: 15,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        border: InputBorder.none,
                        counterText: '',
                      ),
                      style: const TextStyle(fontSize: 15, height: 1.4),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 전송 버튼 - DM 아이콘과 구분되는 상향 화살표 버튼
                InkWell(
                  onTap: canSend ? _sendMessage : null,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: canSend ? DMColors.myMessageBg : Colors.grey[300],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComposerPostContextPreview() {
    final postId = (widget.originPostId ?? '').trim();
    final img = (widget.originPostImageUrl ?? '').trim();
    final preview = (widget.originPostPreview ?? '').trim();
    final isKo = Localizations.localeOf(context).languageCode == 'ko';

    return GestureDetector(
      onTap: postId.isEmpty ? null : () => _navigateToPost(postId),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey[200]!, width: 1),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 썸네일 (있으면)
            if (img.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CachedNetworkImage(
                  imageUrl: img,
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 56,
                    height: 56,
                    color: Colors.grey[200],
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 56,
                    height: 56,
                    color: Colors.grey[200],
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.article_outlined,
                      size: 22,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              )
            else
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.article_outlined,
                  size: 22,
                  color: Color(0xFF6B7280),
                ),
              ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isKo ? '이 게시글에 대해 DM 보내기' : 'Message about this post',
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF111827),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          setState(() {
                            _composerPostContextDismissed = true;
                          });
                        },
                        customBorder: const CircleBorder(),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close,
                            size: 18,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      preview,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4B5563),
                        height: 1.35,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview() {
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final showProgress = _isLoading && (_uploadProgress != null);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.file(
              _pendingImage!,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isKorean ? '이미지 1장 선택됨' : '1 image selected',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 4),
                if (showProgress) ...[
                  Text(
                    isKorean
                        ? '업로드 중... ${((_uploadProgress ?? 0) * 100).round()}%'
                        : 'Uploading... ${((_uploadProgress ?? 0) * 100).round()}%',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: (_uploadProgress ?? 0).clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor: const AlwaysStoppedAnimation<Color>(DMColors.myMessageBg),
                    ),
                  ),
                ] else ...[
                  Text(
                    isKorean ? '전송하면 상대방에게 이미지가 표시됩니다' : 'It will be visible to the other user',
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 12,
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
          IconButton(
            onPressed: _isLoading
                ? null
                : () {
                    setState(() {
                      _pendingImage = null;
                      _uploadProgress = null;
                    });
                  },
            icon: const Icon(Icons.close, size: 18),
            color: Colors.grey[600],
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            splashRadius: 18,
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    if (_pendingImage != null) {
      // 1장 제한: 이미 선택되어 있으면 안내
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '이미지는 한 번에 1장만 첨부할 수 있어요'
                : 'You can attach only 1 image at a time',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(isKorean ? '사진 선택' : 'Choose from library'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickImageFrom(ImageSource.gallery);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: Text(isKorean ? '카메라 촬영' : 'Take a photo'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _pickImageFrom(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickImageFrom(ImageSource source) async {
    try {
      final xfile = await _imagePicker.pickImage(source: source);
      if (xfile == null) return;

      if (!mounted) return;

      final pickedFile = File(xfile.path);
      final shouldSend = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DMImageSendPreviewScreen(imageFile: pickedFile),
          fullscreenDialog: true,
        ),
      );

      if (!mounted) return;
      if (shouldSend != true) return;

      setState(() {
        _pendingImage = pickedFile;
        _uploadProgress = null;
      });
      await _sendMessage();
    } catch (e) {
      Logger.error('이미지 선택 오류: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '이미지를 불러올 수 없습니다'
                : 'Unable to pick an image',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// 메시지 전송
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    final imageFile = _pendingImage;
    if ((text.isEmpty && imageFile == null) || _isLoading) return;

    setState(() => _isLoading = true);
    _messageController.clear();
    FocusScope.of(context).unfocus();

    String? uploadedImageUrl;
    try {
      // 실제로 메시지를 보낼 conversationId를 결정
      String actualConversationId = _activeConversationId;
      
      // 대화방이 존재하지 않으면 첫 메시지 전송 시 생성
      if (_conversationExists != true) {
        
        // conversationId에서 익명 여부와 postId 추출
        final isAnonymousConv = _activeConversationId.startsWith('anon_');
        String? postId;
        if (isAnonymousConv) {
          final parts = _activeConversationId.split('_');
          if (parts.length >= 4) {
            postId = parts.sublist(3).join('_');
            // __timestamp 형식의 접미사 제거
            if (postId.contains('__')) {
              postId = postId.split('__').first;
            }
          }
        }
        // 일반(비익명) 대화방이라도 게시글에서 진입했다면 postId를 대화방 문서에 저장해두는 것이 UX에 유리
        final originPostId = (widget.originPostId ?? '').trim();
        if (postId == null || postId.trim().isEmpty) {
          postId = originPostId.isEmpty ? null : originPostId;
        }
        
        final newConversationId = await _dmService.getOrCreateConversation(
          widget.otherUserId,
          postId: postId,
          isOtherUserAnonymous: isAnonymousConv,
        );
        
        if (newConversationId == null) {
          Logger.error('❌ 대화방 생성 실패');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(AppLocalizations.of(context)!.cannotSendDM ?? ""),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 2),
              ),
            );
          }
          _messageController.text = text; // 메시지 복원
          return;
        }
        
        Logger.log('   - 일치 여부: ${newConversationId == _activeConversationId}');
        
        // ✅ 수정: 새로 생성된 conversationId를 사용
        actualConversationId = newConversationId;
        _conversationExists = true;
      }
      
      Logger.log('📤 메시지 전송 시도: conversationId=$actualConversationId');
      // 이미지가 있으면 먼저 업로드
      if (imageFile != null) {
        if (mounted) {
          setState(() => _uploadProgress = 0.0);
        }
        uploadedImageUrl = await _storageService.uploadDmImage(
          imageFile,
          userId: _currentUser!.uid,
          conversationId: actualConversationId,
          onProgress: (p) {
            if (!mounted) return;
            setState(() => _uploadProgress = p);
          },
        );
        if (uploadedImageUrl == null || uploadedImageUrl!.isEmpty) {
          throw Exception('이미지 업로드에 실패했습니다');
        }
      }

      // 게시글에서 DM으로 진입한 경우: 현재 채팅 세션에서 첫 전송 메시지에만 1회 컨텍스트 부착
      final shouldAttachPostContext = !_originPostContextAttached &&
          widget.originPostId != null &&
          widget.originPostId!.trim().isNotEmpty &&
          !_composerPostContextDismissed;

      final success = await _dmService.sendMessage(
        actualConversationId,
        text,
        imageUrl: uploadedImageUrl,
        postId: shouldAttachPostContext ? widget.originPostId : null,
        postImageUrl: shouldAttachPostContext ? widget.originPostImageUrl : null,
        postPreview: shouldAttachPostContext ? widget.originPostPreview : null,
      );
      Logger.log('📤 메시지 전송 결과: success=$success');
      
      if (success) {
        Logger.log('✅ 메시지 전송 성공 - 후속 처리 시작');
        if (shouldAttachPostContext) {
          _originPostContextAttached = true;
        }
        if (mounted) {
          setState(() {
            _pendingImage = null; // 전송 성공 시 첨부 해제
            _uploadProgress = null;
          });
        }
        
        // 첫 메시지 전송으로 conversationId가 실제로 확정/변경될 수 있으므로,
        // 로컬 캐시 기반 메시지 로딩 + 서버 동기화를 해당 ID로 재시작한다.
        if (_activeConversationId != actualConversationId) {
          Logger.log('🔄 activeConversationId 업데이트: $_activeConversationId → $actualConversationId');
          _activeConversationId = actualConversationId;
        }
        if (mounted) {
          setState(() {
            _conversationExists = true;
          });
        }
        await _initializeMessagesStream(conversationId: actualConversationId);

        if (_conversation == null) {
          Logger.log('📖 대화방 정보 로드 시작');
          await _loadConversation();
        }
        // 메시지 목록 맨 아래로 스크롤
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.messageSendFailed ?? ""),
              duration: const Duration(seconds: 2),
            ),
          );
        }
        // 실패 시 업로드된 이미지 정리(best-effort)
        if (uploadedImageUrl != null && uploadedImageUrl!.isNotEmpty) {
          try {
            await _storageService.deleteImage(uploadedImageUrl!);
          } catch (_) {}
        }
        // 실패 시 텍스트 복원
        _messageController.text = text;
      }
    } catch (e) {
      Logger.error('메시지 전송 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.error ?? ""),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      // 실패 시 업로드된 이미지 정리(best-effort)
      if (uploadedImageUrl != null && uploadedImageUrl!.isNotEmpty) {
        try {
          await _storageService.deleteImage(uploadedImageUrl!);
        } catch (_) {}
      }
      _messageController.text = text;
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 차단 확인 다이얼로그
  Future<void> _showBlockConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.blockThisUser ?? ""),
        content: Text(AppLocalizations.of(context)!.blockConfirm ?? ""),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.cancel ?? ""),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              AppLocalizations.of(context)!.block,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // 차단 로직 구현 (향후 추가)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localizations.localeOf(context).languageCode == 'ko'
                ? '차단 기능은 곧 추가됩니다'
                : 'Block feature coming soon'
          )
        ),
      );
    }
  }

  /// 게시글 네비게이션 배너 빌드
  Widget _buildPostNavigationBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.article_outlined,
            color: Colors.blue.shade700,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              Localizations.localeOf(context).languageCode == 'ko'
                  ? '이 대화는 게시글에서 시작되었습니다'
                  : 'This conversation started from a post',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _navigateToPost(_conversation!.postId!),
            style: TextButton.styleFrom(
              foregroundColor: Colors.blue.shade700,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              Localizations.localeOf(context).languageCode == 'ko'
                  ? '게시글 보기'
                  : 'View Post',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 게시글로 이동
  Future<void> _navigateToPost(String postId) async {
    try {
      // PostService를 사용하여 postId로 Post 객체 가져오기
      final post = await PostService().getPostById(postId);
      if (post != null && mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PostDetailScreen(post: post),
          ),
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                Localizations.localeOf(context).languageCode == 'ko'
                    ? '게시글을 찾을 수 없습니다'
                    : 'Post not found'
              )
            ),
          );
        }
      }
    } catch (e) {
      Logger.error('게시글 로드 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localizations.localeOf(context).languageCode == 'ko'
                  ? '게시글을 불러오는 중 오류가 발생했습니다'
                  : 'An error occurred while loading the post'
            )
          ),
        );
      }
    }
  }
}

