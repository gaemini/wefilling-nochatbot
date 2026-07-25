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
  final SnackChatService _service = SnackChatService();
  late final Stream<List<SnackChat>> _todayStream;
  late final Stream<List<SnackChat>> _allStream;
  late final Stream<Set<String>> _mutedIdsStream;

  @override
  void initState() {
    super.initState();
    _todayStream = _service.getTodaySnackChats();
    _allStream = _service.getAllSnackChats();
    _mutedIdsStream = _service.watchMutedSnackChatIds();
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
                if (items.isEmpty) {
                  return _SectionEmpty(
                    message: isKo
                        ? '진행 중인 Snack Chat이 없어요.'
                        : 'No active Snack Chats.',
                  );
                }
                return Column(
                  children: items
                      .map(
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
                      )
                      .toList(),
                );
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
                if (items.isEmpty) {
                  return _SectionEmpty(
                    message: isKo
                        ? '보관된 Snack Chat이 없어요.'
                        : 'No archived Snack Chats.',
                  );
                }
                return Column(
                  children: items
                      .map(
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
                      )
                      .toList(),
                );
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
        (MediaQuery.sizeOf(context).width * 0.045)
            .clamp(14.0, 20.0)
            .toDouble();
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
          fontFamily: 'Pretendard',
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
        (MediaQuery.sizeOf(context).width * 0.045)
            .clamp(14.0, 20.0)
            .toDouble();
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
          fontFamily: 'Pretendard',
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}
