import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;
import '../../services/snack_chat_discovery_service.dart';
import '../../utils/snack_chat_mentions.dart';
import '../../l10n/ui_locale.dart';

const snackChatMentionsEnabled =
    bool.fromEnvironment('SNACK_CHAT_MENTIONS', defaultValue: true);

class SnackChatMentionPicker extends StatefulWidget {
  const SnackChatMentionPicker(
      {super.key,
      required this.roomId,
      required this.controller,
      required this.focusNode});
  final String roomId;
  final SnackChatMentionController controller;
  final FocusNode focusNode;
  @override
  State<SnackChatMentionPicker> createState() => _SnackChatMentionPickerState();
}

class _SnackChatMentionPickerState extends State<SnackChatMentionPicker> {
  Future<List<Map<String, dynamic>>>? _people;
  String? _room;
  String? _owner;
  DateTime? _loadedAt;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<
          TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final range = widget.controller.activeQuery;
        if (!snackChatMentionsEnabled || range == null)
          return const SizedBox.shrink();
        final owner = FirebaseAuth.instance.currentUser?.uid;
        if (owner == null) return const SizedBox.shrink();
        if (_owner != owner ||
            _room != widget.roomId ||
            _people == null ||
            DateTime.now().difference(_loadedAt!).inSeconds > 30) {
          _room = widget.roomId;
          _owner = owner;
          _loadedAt = DateTime.now();
          _people = SnackChatDiscoveryService().participants(widget.roomId);
        }
        final needle = unorm
            .nfc(value.text.substring(range.start + 1, range.end))
            .toLowerCase();
        return FutureBuilder<List<Map<String, dynamic>>>(
            future: _people,
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return Row(children: [
                  Expanded(
                      child: Text(
                          switch (
                              Localizations.localeOf(context).languageCode) {
                            'ko' => '참여자를 불러오지 못했어요.',
                            'zh' => '成员加载失败。',
                            _ => 'Could not load participants.',
                          },
                          style: const TextStyle(fontSize: 13))),
                  IconButton(
                      tooltip: switch (
                          Localizations.localeOf(context).languageCode) {
                        'ko' => '참여자 다시 불러오기',
                        'zh' => '重新加载成员',
                        _ => 'Retry participants'
                      },
                      icon: const Icon(Icons.refresh, size: 20),
                      onPressed: () => setState(() => _people = null)),
                ]);
              if (snapshot.connectionState != ConnectionState.done ||
                  !snapshot.hasData)
                return const LinearProgressIndicator(minHeight: 2);
              final people = snapshot.data!
                  .where((p) => unorm
                      .nfc(p['displayName'] as String)
                      .toLowerCase()
                      .contains(needle))
                  .toList();
              if (people.isEmpty)
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                      switch (Localizations.localeOf(context).languageCode) {
                        'ko' => '일치하는 참여자가 없어요.',
                        'zh' => '没有匹配的成员。',
                        _ => 'No matching participants.',
                      },
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF64748B))),
                );
              return ConstrainedBox(
                  constraints: BoxConstraints(
                      maxHeight: (MediaQuery.sizeOf(context).height -
                                  MediaQuery.viewInsetsOf(context).bottom -
                                  MediaQuery.viewPaddingOf(context).vertical -
                                  kToolbarHeight)
                              .clamp(0.0, 560.0) *
                          .32),
                  child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: people.length,
                      itemBuilder: (context, index) {
                        final person = people[index];
                        return ListTile(
                            dense: false,
                            visualDensity: VisualDensity.standard,
                            leading: const Icon(Icons.person_outline_rounded,
                                size: 20, color: Color(0xFF64748B)),
                            title: Text(person['displayName'] as String,
                                style: TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    fontFamily: uiFontFamily(context, 'Inter'),
                                    fontFamilyFallback: const [
                                      'NotoSansKR',
                                      'NotoSansSC'
                                    ],
                                    color: const Color(0xFF111827))),
                            onTap: () {
                              widget.controller.insertMention(
                                  person['userId'] as String,
                                  person['displayName'] as String);
                              widget.focusNode.requestFocus();
                            });
                      }));
            });
      });
}
