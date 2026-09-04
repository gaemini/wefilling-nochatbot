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
  Timer? _remainingTimeTicker;

  @override
  void initState() {
    super.initState();
    _resetStreams();
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
    super.dispose();
  }

  void _retryStreams() {
    setState(_resetStreams);
  }

  Future<bool> _confirmUnfavorite() async {
    return showSnackChatUnfavoriteSheet(context);
  }

  Future<void> _handleToggleFavorite(
      SnackChat chat, String? currentUserId) async {
    final nextValue = !chat.isFavoritedBy(currentUserId);
    if (!nextValue) {
      final confirmed = await _confirmUnfavorite();
      if (!confirmed) return;
    }
    await _service.toggleFavorite(chat.id, nextValue);
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
            final items = snapshot.data ?? const <SnackChat>[];
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
                    itemBuilder: (context, index) {
                      if (snapshot.hasError && index == 0) {
                        return _SectionError(
                          onRetry: _retryStreams,
                          compact: true,
                        );
                      }
                      final chat = items[index - errorOffset];
                      return SnackChatCard(
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
    final topPadding = isCompact ? 16.0 : context.rs(26).clamp(20, 30);
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
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SnackChatWelcomeIllustration(compact: isCompact),
                      SizedBox(
                        height: context
                            .rs(isCompact ? 14 : 20)
                            .clamp(12, 22)
                            .toDouble(),
                      ),
                      Text(
                        isKo
                            ? '짧게 시작해도, 대화는 깊어질 수 있어요'
                            : 'Start small. Talk freely.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(19).clamp(17, 20).toDouble(),
                          fontWeight: FontWeight.w800,
                          height: 1.35,
                          letterSpacing: -0.3,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: context.rs(7).clamp(6, 9).toDouble()),
                      Text(
                        isKo
                            ? '필요한 시간만 채팅방을 열고,\n서로 다른 언어로도 편하게 이야기해 보세요.'
                            : 'Open a room for as long as you need,\nand chat comfortably across languages.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(13).clamp(12, 14).toDouble(),
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          color: const Color(0xFF6B7280),
                        ),
                      ),
                      SizedBox(
                        height: context
                            .rs(isCompact ? 18 : 24)
                            .clamp(16, 26)
                            .toDouble(),
                      ),
                      _FeatureRow(
                        icon: Icons.schedule_rounded,
                        title: isKo ? '시간을 정하는 채팅방' : 'Time-limited rooms',
                        description: isKo
                            ? '24시간 또는 종료 없이, 대화에 맞는 시간을 선택해요.'
                            : 'Choose 24 hours or keep the room open.',
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
                      if (onCreate != null) ...[
                        SizedBox(
                          height: context
                              .rs(isCompact ? 20 : 26)
                              .clamp(18, 28)
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
    final scale = compact ? 0.84 : 1.0;
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
                  color: const Color(0xFF6D4FC2),
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
