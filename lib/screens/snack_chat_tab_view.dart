import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../design/tokens.dart';
import '../models/snack_chat.dart';
import '../services/snack_chat_service.dart';
import '../constants/app_constants.dart';
import '../ui/sheets/snack_chat_unfavorite_sheet.dart';
import '../ui/widgets/app_fab.dart';
import '../ui/widgets/snack_chat_card.dart';
import '../utils/responsive_helper.dart';
import 'snack_chat_screen.dart';

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
                isKo ? '즐겨찾기를 변경하지 못했어요.' : 'Couldn’t update favorites.',
              ),
            ),
          );
        }
      }
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
            final errorOffset = snapshot.hasError ? 1 : 0;
            final itemIndexByRoomId = <String, int>{
              for (var index = 0; index < items.length; index++)
                items[index].id: index + errorOffset,
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
                    itemCount: items.length + errorOffset,
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
                      final chat = items[index - errorOffset];
                      return SnackChatCard(
                        key: ValueKey<String>(chat.id),
                        snackChat: chat,
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
                      );
                    },
                  ),
                ),
                if (widget.onCreateSnackChat != null)
                  PositionedDirectional(
                    end: 16,
                    bottom: 16 + bottomInset,
                    child: AppFab(
                      icon: IconStyles.add,
                      onPressed: widget.onCreateSnackChat,
                      semanticLabel: isKo ? '새 스낵챗 만들기' : 'Create a Snack Chat',
                      tooltip: isKo ? '스낵챗 만들기' : 'Create Snack Chat',
                      heroTag: 'create_snack_chat_fab',
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

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: CircularProgressIndicator()),
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
    final media = MediaQuery.of(context);
    final isCompact = media.size.height < 700 || context.isCompactLayout;
    final horizontalPadding = media.size.width < 360
        ? 14.0
        : media.size.width < 430
            ? 16.0
            : 20.0;
    final topPadding = isCompact ? 14.0 : context.rs(22).clamp(18, 26);
    final bottomPadding = isCompact ? 18.0 : 24.0;

    return SafeArea(
      top: false,
      child: CustomScrollView(
        // 내용이 화면 안에 들어오면 빈 화면이 위아래로 끌리지 않는다.
        // 작은 화면에서 실제로 넘칠 때만 스크롤해 overflow를 피한다.
        physics: const ClampingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              topPadding.toDouble(),
              horizontalPadding,
              bottomPadding,
            ),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        isKo
                            ? '필요한 시간만 열어 두는 번역 채팅'
                            : 'A translated chat for exactly as long as you need',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(21).clamp(18, 22).toDouble(),
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          letterSpacing: -0.4,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: context.rs(7).clamp(6, 9).toDouble()),
                      Text(
                        isKo
                            ? '친구들과 24시간 또는 종료 없이 대화하고,\n서로 다른 언어의 메시지도 바로 이해할 수 있어요.'
                            : 'Chat with friends for 24 hours or without an end time,\nand understand messages across languages.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(13.5).clamp(12.5, 14).toDouble(),
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                      SizedBox(
                        height: context
                            .rs(isCompact ? 12 : 16)
                            .clamp(10, 18)
                            .toDouble(),
                      ),
                      _SnackChatWelcomeIllustration(compact: isCompact),
                      SizedBox(
                        height: context
                            .rs(isCompact ? 12 : 18)
                            .clamp(10, 20)
                            .toDouble(),
                      ),
                      Text(
                        isKo ? '스낵챗에서 할 수 있어요' : 'What Snack Chat offers',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(13).clamp(12, 14).toDouble(),
                          fontWeight: FontWeight.w800,
                          height: 1.3,
                          color: const Color(0xFF475467),
                        ),
                      ),
                      SizedBox(height: context.rs(10).clamp(8, 12).toDouble()),
                      _FeatureRow(
                        icon: Icons.schedule_rounded,
                        title:
                            isKo ? '대화 시간을 직접 선택' : 'Choose the room duration',
                        description: isKo
                            ? '가벼운 대화는 24시간, 계속할 대화는 종료 없이 열어요.'
                            : 'Use 24 hours for quick chats or keep important rooms open.',
                      ),
                      SizedBox(height: context.rs(12).clamp(10, 14).toDouble()),
                      _FeatureRow(
                        icon: Icons.translate_rounded,
                        title: isKo
                            ? '실시간 다국어 번역'
                            : 'Live multilingual translation',
                        description: isKo
                            ? '상대방 메시지를 내가 설정한 언어로 바로 번역해요.'
                            : 'Translate messages instantly into your chosen language.',
                      ),
                      SizedBox(height: context.rs(12).clamp(10, 14).toDouble()),
                      _FeatureRow(
                        icon: Icons.notes_rounded,
                        title: isKo ? '놓친 대화도 빠르게 정리' : 'Catch up quickly',
                        description: isKo
                            ? '안 읽은 메시지와 오늘 대화의 중요한 내용을 정리해요.'
                            : 'Review the key points from unread messages and today’s chat.',
                      ),
                      if (onCreate != null) ...[
                        SizedBox(
                          height: context
                              .rs(isCompact ? 16 : 22)
                              .clamp(14, 24)
                              .toDouble(),
                        ),
                        SizedBox(
                          height: context.rh(48, min: 46, max: 52),
                          child: FilledButton.icon(
                            key: const Key('snack_chat_empty_create_button'),
                            onPressed: onCreate,
                            icon: Icon(
                              Icons.add_comment_outlined,
                              size: context.ri(19).clamp(18, 21).toDouble(),
                            ),
                            label: Text(
                              isKo
                                  ? '첫 스낵챗 만들기'
                                  : 'Create your first Snack Chat',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize:
                                    context.rf(14).clamp(13, 15).toDouble(),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              elevation: 0,
                              backgroundColor: AppColors.pointColor,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
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
    );
  }
}

class _SnackChatWelcomeIllustration extends StatelessWidget {
  const _SnackChatWelcomeIllustration({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scale = compact ? 0.68 : 0.78;
    return Center(
      child: SizedBox(
        width: 126 * scale,
        height: 104 * scale,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 92 * scale,
              height: 92 * scale,
              decoration: const BoxDecoration(
                color: Color(0xFFF4F8FD),
                shape: BoxShape.circle,
              ),
            ),
            Positioned(
              left: 15 * scale,
              top: 20 * scale,
              child: Container(
                width: 70 * scale,
                height: 54 * scale,
                decoration: BoxDecoration(
                  color: AppColors.pointColor,
                  borderRadius: BorderRadius.circular(18 * scale),
                ),
                child: Icon(
                  Icons.chat_bubble_rounded,
                  color: Colors.white,
                  size: 28 * scale,
                ),
              ),
            ),
            Positioned(
              right: 8 * scale,
              bottom: 8 * scale,
              child: Container(
                width: 48 * scale,
                height: 48 * scale,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x12000000),
                      blurRadius: 7,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.translate_rounded,
                  color: const Color(0xFF087BB5),
                  size: 22 * scale,
                ),
              ),
            ),
            Positioned(
              right: 13 * scale,
              top: 4 * scale,
              child: Container(
                width: 34 * scale,
                height: 34 * scale,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  color: const Color(0xFF667085),
                  size: 19 * scale,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: context.rs(2)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: context.rh(32, min: 30, max: 34),
            child: Icon(
              icon,
              color: const Color(0xFF475467),
              size: context.ri(20).clamp(19, 22).toDouble(),
            ),
          ),
          SizedBox(width: context.rs(10).clamp(8, 12).toDouble()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(14).clamp(13, 15).toDouble(),
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: const Color(0xFF111827),
                  ),
                ),
                SizedBox(height: context.rs(2).clamp(1, 3).toDouble()),
                Text(
                  description,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(12).clamp(11, 13).toDouble(),
                    fontWeight: FontWeight.w500,
                    height: 1.4,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      child: TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text(
          isKo ? 'Snack Chat을 불러오지 못했습니다. 다시 시도' : 'Could not load. Retry',
        ),
      ),
    );
  }
}
