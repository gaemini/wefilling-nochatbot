import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../design/tokens.dart';
import '../models/snack_chat.dart';
import '../services/snack_chat_service.dart';
import '../ui/sheets/snack_chat_unfavorite_sheet.dart';
import '../ui/widgets/snack_chat_card.dart';
import '../ui/widgets/create_action_button.dart';
import '../ui/widgets/tab_empty_state.dart';
import '../l10n/group_ui_strings.dart';
import 'snack_chat_info_screen.dart';
import 'snack_chat_screen.dart';
import '../l10n/ui_locale.dart';
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/list_skeletons.dart';

class SnackChatTabView extends StatefulWidget {
  const SnackChatTabView({
    super.key,
    this.onCreateSnackChat,
  });

  final VoidCallback? onCreateSnackChat;

  @override
  State<SnackChatTabView> createState() => _SnackChatTabViewState();
}

class _SnackChatTabViewState extends State<SnackChatTabView> {
  // 서비스 인스턴스를 State에 보관해 rebuild마다 재생성되지 않도록 함
  late SnackChatService _service;
  late Stream<List<SnackChat>> _snackChatsStream;
  late Stream<Set<String>> _mutedIdsStream;
  StreamSubscription<User?>? _authSubscription;
  Timer? _remainingTimeTicker;
  String? _favoriteOwnerUid;
  final Map<String, bool> _favoriteOverrides = <String, bool>{};
  final Map<String, bool> _favoriteDesiredValues = <String, bool>{};
  final Map<String, bool> _favoritePersistedValues = <String, bool>{};
  final Set<String> _favoriteWritesInFlight = <String>{};
  final Set<String> _favoriteConfirmingRooms = <String>{};

  @override
  void initState() {
    super.initState();
    _favoriteOwnerUid = FirebaseAuth.instance.currentUser?.uid;
    _resetStreams();
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      final uid = user?.uid;
      if (uid == _favoriteOwnerUid) return;
      if (!mounted) {
        _clearFavoriteState(uid);
        return;
      }
      setState(() {
        _clearFavoriteState(uid);
        _resetStreams();
      });
    });
    _remainingTimeTicker = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _resetStreams() {
    _service = SnackChatService();
    _snackChatsStream = _service.getSnackChats();
    _mutedIdsStream = _service.watchMutedSnackChatIds();
  }

  @override
  void dispose() {
    _remainingTimeTicker?.cancel();
    unawaited(_authSubscription?.cancel());
    super.dispose();
  }

  void _clearFavoriteState(String? ownerUid) {
    _favoriteOwnerUid = ownerUid;
    _favoriteOverrides.clear();
    _favoriteDesiredValues.clear();
    _favoritePersistedValues.clear();
    _favoriteWritesInFlight.clear();
    _favoriteConfirmingRooms.clear();
  }

  void _ensureFavoriteOwner(String? uid) {
    if (_favoriteOwnerUid != uid) _clearFavoriteState(uid);
  }

  void _retryStreams() {
    setState(_resetStreams);
  }

  Future<bool> _confirmUnfavorite() async {
    return showSnackChatUnfavoriteSheet(context);
  }

  bool _effectiveFavorite(SnackChat chat, String currentUserId) {
    return _favoriteOverrides[chat.id] ?? chat.isFavoritedBy(currentUserId);
  }

  SnackChat _withFavorite(
    SnackChat chat,
    String currentUserId,
    bool value,
  ) {
    final favorites = chat.favoriteUserIds.toSet();
    value ? favorites.add(currentUserId) : favorites.remove(currentUserId);
    return chat.copyWith(favoriteUserIds: favorites.toList(growable: false));
  }

  List<SnackChat> _displayItems(
    List<SnackChat> serverItems,
    String? currentUserId,
  ) {
    _ensureFavoriteOwner(currentUserId);
    if (currentUserId == null || currentUserId.isEmpty) return serverItems;

    final presentRoomIds = serverItems.map((chat) => chat.id).toSet();
    for (final chat in serverItems) {
      final serverValue = chat.isFavoritedBy(currentUserId);
      if (!_favoriteWritesInFlight.contains(chat.id)) {
        final override = _favoriteOverrides[chat.id];
        if (override != null && override == serverValue) {
          _favoriteOverrides.remove(chat.id);
        }
        if (!_favoriteOverrides.containsKey(chat.id)) {
          _favoritePersistedValues[chat.id] = serverValue;
        }
      }
    }
    _favoriteOverrides.removeWhere(
      (roomId, _) =>
          !presentRoomIds.contains(roomId) &&
          !_favoriteWritesInFlight.contains(roomId),
    );
    _favoritePersistedValues.removeWhere(
      (roomId, _) =>
          !presentRoomIds.contains(roomId) &&
          !_favoriteWritesInFlight.contains(roomId),
    );

    final overlaid = serverItems.map((chat) {
      final override = _favoriteOverrides[chat.id];
      return override == null
          ? chat
          : _withFavorite(chat, currentUserId, override);
    });
    // Reapply only the existing unified visibility policy. This makes an
    // expired favorite disappear immediately when unfavorited without moving
    // any room across Today/All or active/expired policies.
    return filterSnackChatsBySection(
      overlaid.toList(growable: false),
      section: SnackChatListSection.unified,
      currentUserId: currentUserId,
    );
  }

  Future<void> _handleToggleFavorite(
    SnackChat chat,
    String? currentUserId,
  ) async {
    if (currentUserId == null || currentUserId.isEmpty) return;
    _ensureFavoriteOwner(currentUserId);
    final nextValue = !_effectiveFavorite(chat, currentUserId);
    if (!nextValue) {
      if (!_favoriteConfirmingRooms.add(chat.id)) return;
      final confirmed = await _confirmUnfavorite();
      _favoriteConfirmingRooms.remove(chat.id);
      if (!confirmed) return;
    }
    if (!mounted ||
        FirebaseAuth.instance.currentUser?.uid != currentUserId ||
        _favoriteOwnerUid != currentUserId) {
      return;
    }

    setState(() {
      _favoritePersistedValues.putIfAbsent(
        chat.id,
        () => chat.isFavoritedBy(currentUserId),
      );
      _favoriteOverrides[chat.id] = nextValue;
      _favoriteDesiredValues[chat.id] = nextValue;
    });
    unawaited(_drainFavoriteWrites(chat.id, currentUserId));
  }

  Future<void> _drainFavoriteWrites(String roomId, String ownerUid) async {
    if (!_favoriteWritesInFlight.add(roomId)) return;
    var showFailure = false;
    try {
      while (_favoriteOwnerUid == ownerUid &&
          FirebaseAuth.instance.currentUser?.uid == ownerUid) {
        final desired = _favoriteDesiredValues[roomId];
        if (desired == null) break;
        final persisted = _favoritePersistedValues[roomId] ?? !desired;
        if (desired == persisted) {
          _favoriteDesiredValues.remove(roomId);
          break;
        }

        try {
          await _service.toggleFavorite(roomId, desired);
        } catch (_) {
          if (_favoriteOwnerUid != ownerUid ||
              FirebaseAuth.instance.currentUser?.uid != ownerUid) {
            return;
          }
          // A superseded request failure must not overwrite the latest tap.
          if (_favoriteDesiredValues[roomId] == desired) {
            _favoriteOverrides[roomId] = persisted;
            _favoriteDesiredValues.remove(roomId);
            showFailure = true;
            break;
          }
          continue;
        }

        if (_favoriteOwnerUid != ownerUid ||
            FirebaseAuth.instance.currentUser?.uid != ownerUid) {
          return;
        }
        _favoritePersistedValues[roomId] = desired;
        if (_favoriteDesiredValues[roomId] == desired) {
          _favoriteDesiredValues.remove(roomId);
          break;
        }
      }
    } finally {
      _favoriteWritesInFlight.remove(roomId);
      if (mounted && _favoriteOwnerUid == ownerUid) {
        setState(() {});
        if (showFailure) {
          final isKo = Localizations.localeOf(context).languageCode == 'ko';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (isChineseUi(context)
                    ? '更新收藏失败。'
                    : isKo
                        ? '즐겨찾기를 변경하지 못했어요.'
                        : 'Couldn’t update favorites.'),
              ),
            ),
          );
        }
      }
    }
  }

  /// 길게 누르기 메뉴: 즐겨찾기 / 알림 끄기·켜기 / 설정.
  /// 즐겨찾기 해제는 기존 확인 시트를 그대로 거치고(`_handleToggleFavorite`),
  /// 알림은 사용자별 `mutedSnackChatIds`(채팅방 설정 화면과 같은 저장소)를 바꾼다.
  Future<void> _showRoomMenu(
    SnackChat chat,
    String? currentUserId, {
    required bool muted,
  }) async {
    if (currentUserId == null || currentUserId.isEmpty) return;
    final favorited = _effectiveFavorite(chat, currentUserId);
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final zh = isChineseUi(context);
    String t(String zhText, String ko, String en) =>
        zh ? zhText : (isKo ? ko : en);
    final items = <(String, String, IconData)>[
      (
        'favorite',
        favorited
            ? t('取消收藏', '즐겨찾기 해제', 'Remove favorite')
            : t('收藏', '즐겨찾기', 'Favorite'),
        favorited ? Icons.star_outline_rounded : Icons.star_rounded,
      ),
      (
        'mute',
        muted
            ? t('开启通知', '알림 켜기', 'Turn on notifications')
            : t('关闭通知', '알림 끄기', 'Mute notifications'),
        muted
            ? Icons.notifications_active_outlined
            : Icons.notifications_off_outlined,
      ),
      ('settings', t('设置', '설정', 'Settings'), Icons.settings_outlined),
    ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      showDragHandle: false,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in items)
                  InkWell(
                    key: ValueKey<String>('snack_chat_menu_${item.$1}'),
                    onTap: () => Navigator.pop(sheetContext, item.$1),
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Row(
                        children: [
                          Icon(item.$3, size: 22, color: Colors.black),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              item.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: uiFontFamily(sheetContext, 'Inter'),
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF000000),
                              ),
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
      ),
    );
    if (!mounted || selected == null) return;
    switch (selected) {
      case 'favorite':
        await _handleToggleFavorite(chat, currentUserId);
      case 'mute':
        await _toggleMute(chat.id, mute: !muted);
      case 'settings':
        await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => SnackChatInfoScreen(snackChatId: chat.id),
          ),
        );
    }
  }

  /// 연타로 같은 요청이 겹치지 않게 방별로 한 번만 보낸다.
  final Set<String> _muteInFlight = <String>{};

  Future<void> _toggleMute(String roomId, {required bool mute}) async {
    if (!_muteInFlight.add(roomId)) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final zh = isChineseUi(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await _service.toggleMuteSnackChat(roomId, mute);
      messenger?.showSnackBar(SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(mute
            ? (zh ? '已关闭此群聊的通知' : isKo ? '이 방의 알림을 껐어요' : 'Notifications muted')
            : (zh ? '已开启此群聊的通知' : isKo ? '이 방의 알림을 켰어요' : 'Notifications on')),
      ));
    } catch (_) {
      messenger?.showSnackBar(SnackBar(
        content: Text(zh
            ? '无法更改通知设置'
            : isKo
                ? '알림 설정을 바꾸지 못했어요'
                : 'Couldn\'t change notifications'),
      ));
    } finally {
      _muteInFlight.remove(roomId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<Set<String>>(
      stream: _mutedIdsStream,
      initialData: const <String>{},
      builder: (context, mutedSnapshot) {
        final mutedIds = mutedSnapshot.data ?? const <String>{};
        return StreamBuilder<List<SnackChat>>(
          stream: _snackChatsStream,
          builder: (context, snapshot) {
            final serverItems = snapshot.data ?? const <SnackChat>[];
            final items = _displayItems(serverItems, currentUserId);
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData) {
              return const _SectionLoading();
            }
            if (snapshot.hasError && items.isEmpty) {
              return _SectionError(onRetry: _retryStreams);
            }
            if (items.isEmpty) {
              return SnackChatEmptyState(
                isKo: isKo,
                onCreate: widget.onCreateSnackChat,
              );
            }

            _service.prefetchRoomEntryData(items);
            final activeItems =
                items.where((chat) => !chat.isExpired()).toList();
            final pastItems = items.where((chat) => chat.isExpired()).toList();
            final hasPastSection = pastItems.isNotEmpty;
            final errorOffset = snapshot.hasError ? 1 : 0;
            final itemIndexByRoomId = <String, int>{
              for (var index = 0; index < activeItems.length; index++)
                activeItems[index].id: index + errorOffset,
              for (var index = 0; index < pastItems.length; index++)
                pastItems[index].id:
                    index + activeItems.length + errorOffset + 1,
            };
            final bottomInset = MediaQuery.paddingOf(context).bottom;
            return Stack(
              children: [
                Positioned.fill(
                  child: ListView.builder(
                    key: const PageStorageKey<String>('snack_chat_list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    scrollCacheExtent: const ScrollCacheExtent.viewport(0.75),
                    padding: EdgeInsets.fromLTRB(0, 4, 0, 88 + bottomInset),
                    itemCount:
                        items.length + errorOffset + (hasPastSection ? 1 : 0),
                    findChildIndexCallback: (key) {
                      if (key is! ValueKey<String>) return null;
                      return itemIndexByRoomId[key.value];
                    },
                    itemBuilder: (context, index) {
                      if (snapshot.hasError && index == 0) {
                        return _SectionError(
                          onRetry: _retryStreams,
                          compact: true,
                        );
                      }
                      final roomIndex = index - errorOffset;
                      if (hasPastSection && roomIndex == activeItems.length) {
                        return _PastSnackChatsHeader(isKo: isKo);
                      }
                      final isPast = roomIndex >= activeItems.length;
                      final chat = isPast
                          ? pastItems[roomIndex - activeItems.length - 1]
                          : activeItems[roomIndex];
                      return SnackChatCard(
                        key: ValueKey<String>(chat.id),
                        snackChat: chat,
                        isPast: isPast,
                        currentUserId: currentUserId,
                        isMuted: mutedIds.contains(chat.id),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SnackChatScreen(
                                snackChatId: chat.id,
                                initialRoom: chat,
                                initialEntryContext:
                                    _service.peekEntryContext(chat.id),
                              ),
                            ),
                          );
                        },
                        onToggleFavorite: () {
                          _handleToggleFavorite(chat, currentUserId);
                        },
                        // 길게 누르면 즐겨찾기·알림·설정 메뉴.
                        onLongPress: isPast
                            ? null
                            : () => _showRoomMenu(
                                  chat,
                                  currentUserId,
                                  muted: mutedIds.contains(chat.id),
                                ),
                      );
                    },
                  ),
                ),
                if (widget.onCreateSnackChat != null)
                  PositionedDirectional(
                    end: kCreateActionMargin,
                    bottom: kCreateActionMargin + bottomInset,
                    child: CreateActionButton(
                      label: isChineseUi(context)
                          ? '创建群聊'
                          : isKo
                              ? '스낵챗 열기'
                              : 'Open Snack Chat',
                      semanticLabel: (isChineseUi(context)
                          ? '创建群聊'
                          : isKo
                              ? '스낵챗 만들기'
                              : 'Create Snack Chat'),
                      onPressed: widget.onCreateSnackChat!,
                      tooltip: isChineseUi(context)
                          ? '创建群聊'
                          : isKo
                              ? '스낵챗 만들기'
                              : 'Create Snack Chat',
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

class _PastSnackChatsHeader extends StatelessWidget {
  const _PastSnackChatsHeader({required this.isKo});

  final bool isKo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Row(
        children: [
          Text(
            (isChineseUi(context)
                ? '过去的群聊'
                : isKo
                    ? '지난 스낵챗'
                    : 'Past Snack Chats'),
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8A8A8A),
            ),
          ),
          const Spacer(),
          Text(
            (isChineseUi(context)
                ? '已收藏的聊天'
                : isKo
                    ? '즐겨찾기한 대화'
                    : 'Favorited chats'),
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 11,
              color: BrandColors.neutral500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    // 채팅방 줄(72) 모양 자리표시(모션 2부 F-1).
    return const ListLoadingSkeleton(
      rows: 4,
      avatarSize: 48,
      rowSpacing: 24,
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
    );
  }
}

class SnackChatEmptyState extends StatelessWidget {
  const SnackChatEmptyState({
    super.key,
    required this.isKo,
    required this.onCreate,
  });

  final bool isKo;
  final VoidCallback? onCreate;

  @override
  Widget build(BuildContext context) {
    final strings = GroupUiStrings.of(context);
    // 높이 700 미만이면 미리보기를 2줄로 줄이고, 그래도 넘치면 스크롤한다.
    final previewRows = MediaQuery.sizeOf(context).height < 700 ? 2 : 3;

    return SafeArea(
      top: false,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: CustomScrollView(
          // 내용이 화면 안에 들어오면 빈 화면이 위아래로 끌리지 않는다.
          // 작은 화면에서 실제로 넘칠 때만 스크롤해 overflow를 피한다.
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16, bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SnackChatEmptyPreview(
                          rows: previewRows,
                          sampleTitle: strings.sampleTitle,
                          sampleRemaining: strings.sampleRemaining,
                          sampleMessage: strings.sampleMessage,
                        ),
                        const SizedBox(height: 20),
                        TabEmptyStateText(
                          title: strings.snackChatEmptyTitle,
                          body: strings.snackChatEmptyBody,
                        ),
                        if (onCreate != null) ...[
                          const SizedBox(height: 16),
                          Center(
                            child: TabEmptyStateButton(
                              key: const Key('snack_chat_empty_create_button'),
                              label: strings.snackChatEmptyButton,
                              onPressed: onCreate!,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({required this.onRetry, this.compact = false});

  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 2 : 10),
      child: MotionPress(
pressedScale: .985, child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text(
          (isChineseUi(context)
              ? '加载失败，点击重试'
              : isKo
                  ? 'Snack Chat을 불러오지 못했습니다. 다시 시도'
                  : 'Could not load. Retry'),
        ),
      )),
    );
  }
}
