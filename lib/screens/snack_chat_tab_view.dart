import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/snack_chat.dart';
import '../services/snack_chat_service.dart';
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

  @override
  void initState() {
    super.initState();
    _todayStream = _service.getManageableTodaySnackChats();
    _allStream = _service.getManageableAllSnackChats();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
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
                    ? '관리할 활성 Snack Chat이 없어요.'
                    : 'No active Snack Chats to manage.',
              );
            }
            return Column(
              children: items
                  .map(
                    (chat) => SnackChatCard(
                      snackChat: chat,
                      currentUserId: currentUserId,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SnackChatScreen(snackChatId: chat.id),
                          ),
                        );
                      },
                      onToggleFavorite: () async {
                        try {
                          await _service.toggleFavorite(
                            chat.id,
                            !chat.isFavoritedBy(currentUserId),
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isKo
                                  ? '즐겨찾기를 변경하지 못했어요.'
                                  : 'Could not update favorite.'),
                            ),
                          );
                        }
                      },
                    ),
                  )
                  .toList(),
            );
          },
        ),
        const SizedBox(height: 10),
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
                message:
                    isKo ? '이전 Snack Chat이 없어요.' : 'No previous Snack Chats.',
              );
            }
            return Column(
              children: items
                  .map(
                    (chat) => SnackChatCard(
                      snackChat: chat,
                      currentUserId: currentUserId,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                SnackChatScreen(snackChatId: chat.id),
                          ),
                        );
                      },
                      onToggleFavorite: () async {
                        try {
                          await _service.toggleFavorite(
                            chat.id,
                            !chat.isFavoritedBy(currentUserId),
                          );
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isKo
                                  ? '즐겨찾기를 변경하지 못했어요.'
                                  : 'Could not update favorite.'),
                            ),
                          );
                        }
                      },
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 16,
          fontWeight: FontWeight.w800,
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
      child: Text(
        message,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Color(0xFF6B7280),
        ),
      ),
    );
  }
}
