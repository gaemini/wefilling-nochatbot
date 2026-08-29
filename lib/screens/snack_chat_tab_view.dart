import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/snack_chat.dart';
import '../services/snack_chat_service.dart';
import '../ui/sheets/snack_chat_unfavorite_sheet.dart';
import '../ui/widgets/snack_chat_card.dart';
import 'snack_chat_screen.dart';

class SnackChatTabView extends StatefulWidget {
  const SnackChatTabView({super.key});

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
              return _SectionEmpty(
                message: isKo ? '참여 중인 스낵챗이 없어요.' : 'No Snack Chats yet.',
              );
            }

            _service.prefetchRoomEntryData(items);
            final errorOffset = snapshot.hasError ? 1 : 0;
            final bottomInset = MediaQuery.paddingOf(context).bottom;
            return ListView.builder(
              key: const PageStorageKey<String>('snack_chat_list'),
              physics: const AlwaysScrollableScrollPhysics(),
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

class _SectionEmpty extends StatelessWidget {
  final String message;
  const _SectionEmpty({required this.message});

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        (MediaQuery.sizeOf(context).width * 0.045).clamp(14.0, 20.0).toDouble();
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          24,
          horizontalPadding,
          88 + MediaQuery.paddingOf(context).bottom,
        ),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: ['NotoSansKR'],
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B7280),
          ),
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
