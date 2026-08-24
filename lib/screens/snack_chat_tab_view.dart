import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
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
  late Stream<List<SnackChat>> _todayStream;
  late Stream<List<SnackChat>> _allStream;
  late Stream<Set<String>> _mutedIdsStream;

  @override
  void initState() {
    super.initState();
    _resetStreams();
  }

  void _resetStreams() {
    _service = SnackChatService();
    _todayStream = _service.getTodaySnackChats();
    _allStream = _service.getAllSnackChats();
    _mutedIdsStream = _service.watchMutedSnackChatIds();
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
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<Set<String>>(
      stream: _mutedIdsStream,
      initialData: const <String>{},
      builder: (context, mutedSnapshot) {
        final mutedIds = mutedSnapshot.data ?? const <String>{};
        return ListView(
          padding: const EdgeInsets.only(bottom: 76),
          children: [
            _SectionTitle(title: l10n.today),
            StreamBuilder<List<SnackChat>>(
              stream: _todayStream,
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
                    message: isKo
                        ? '진행 중인 Snack Chat이 없어요.'
                        : 'No active Snack Chats.',
                  );
                }
                return Column(children: [
                  if (snapshot.hasError)
                    _SectionError(onRetry: _retryStreams, compact: true),
                  ...items.map(
                    (chat) => SnackChatCard(
                      snackChat: chat,
                      currentUserId: currentUserId,
                      isMuted: mutedIds.contains(chat.id),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SnackChatScreen(snackChatId: chat.id),
                          ),
                        );
                      },
                      onToggleFavorite: () {
                        _handleToggleFavorite(chat, currentUserId);
                      },
                    ),
                  ),
                ]);
              },
            ),
            const SizedBox(height: 6),
            _SectionTitle(title: l10n.all),
            StreamBuilder<List<SnackChat>>(
              stream: _allStream,
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
                    message: isKo
                        ? '보관된 Snack Chat이 없어요.'
                        : 'No archived Snack Chats.',
                  );
                }
                return Column(children: [
                  if (snapshot.hasError)
                    _SectionError(onRetry: _retryStreams, compact: true),
                  ...items.map(
                    (chat) => SnackChatCard(
                      snackChat: chat,
                      currentUserId: currentUserId,
                      isMuted: mutedIds.contains(chat.id),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SnackChatScreen(snackChatId: chat.id),
                          ),
                        );
                      },
                      onToggleFavorite: () {
                        _handleToggleFavorite(chat, currentUserId);
                      },
                    ),
                  ),
                ]);
              },
            ),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    final horizontalPadding =
        (MediaQuery.sizeOf(context).width * 0.045).clamp(14.0, 20.0).toDouble();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        7,
        horizontalPadding,
        6,
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: Color(0xFF111827),
        ),
      ),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        2,
        horizontalPadding,
        12,
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF6B7280),
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
