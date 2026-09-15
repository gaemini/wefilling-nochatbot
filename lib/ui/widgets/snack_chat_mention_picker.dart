import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../../l10n/ui_locale.dart';
import '../../services/avatar_cache_service.dart';
import '../../services/snack_chat_discovery_service.dart';
import '../../services/user_info_cache_service.dart';
import '../../utils/profile_photo_policy.dart';
import '../../utils/snack_chat_mentions.dart';
import 'user_avatar.dart';

const snackChatMentionsEnabled =
    bool.fromEnvironment('SNACK_CHAT_MENTIONS', defaultValue: true);

class SnackChatMentionPicker extends StatefulWidget {
  const SnackChatMentionPicker({
    super.key,
    required this.roomId,
    required this.controller,
    required this.focusNode,
    required this.participantIds,
    this.blockedUserIds = const <String>{},
    this.fallbackNames = const <String, String>{},
  });

  final String roomId;
  final SnackChatMentionController controller;
  final FocusNode focusNode;
  final List<String> participantIds;
  final Set<String> blockedUserIds;
  final Map<String, String> fallbackNames;

  @override
  State<SnackChatMentionPicker> createState() => _SnackChatMentionPickerState();
}

class _SnackChatMentionPickerState extends State<SnackChatMentionPicker> {
  final UserInfoCacheService _profileCache = UserInfoCacheService();
  final SnackChatDiscoveryService _participantService =
      SnackChatDiscoveryService();
  final Map<String, DMUserInfo> _profiles = <String, DMUserInfo>{};

  Set<String>? _serverAllowedIds;
  bool _loading = true;
  bool _failed = false;
  int _loadGeneration = 0;
  late String _signature;

  @override
  void initState() {
    super.initState();
    _signature = _participantSignature();
    _primeParticipants();
  }

  @override
  void didUpdateWidget(covariant SnackChatMentionPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _participantSignature();
    if (signature != _signature) {
      _signature = signature;
      _primeParticipants();
    }
  }

  String _participantSignature() =>
      '${widget.roomId}|${_eligibleParticipantIds().join('|')}';

  List<String> _eligibleParticipantIds() {
    final self = FirebaseAuth.instance.currentUser?.uid;
    return widget.participantIds
        .map((id) => id.trim())
        .where((id) =>
            id.isNotEmpty && id != self && !widget.blockedUserIds.contains(id))
        .toSet()
        .take(50)
        .toList(growable: false);
  }

  Future<void> _primeParticipants({bool forceRefresh = false}) async {
    final owner = FirebaseAuth.instance.currentUser?.uid;
    final participantIds = _eligibleParticipantIds();
    final generation = ++_loadGeneration;

    _profiles
      ..clear()
      ..addEntries(participantIds.map((id) {
        final cached = _profileCache.getCachedUserInfo(id);
        return cached == null ? null : MapEntry(id, cached);
      }).whereType<MapEntry<String, DMUserInfo>>());
    _serverAllowedIds = null;
    _loading = participantIds.isNotEmpty && owner != null;
    _failed = false;
    if (mounted) setState(() {});
    if (participantIds.isEmpty || owner == null) return;

    // 서버의 최종 참여자 검증과 로컬 프로필 복원을 동시에 시작한다.
    // 로컬 데이터가 있으면 네트워크 응답을 기다리지 않고 먼저 표시한다.
    final serverFuture = _participantService.participants(
      widget.roomId,
      forceRefresh: forceRefresh,
    );
    try {
      final restored = await _profileCache.hydrateUsers(participantIds);
      if (!_isCurrent(owner, generation)) return;
      final restoredProfiles = restored.values.whereType<DMUserInfo>();
      if (restoredProfiles.isNotEmpty) {
        setState(() {
          for (final profile in restoredProfiles) {
            _profiles[profile.uid] = profile;
          }
        });
        unawaited(_warmAvatars(restoredProfiles));
      }

      final rows = await serverFuture;
      if (!_isCurrent(owner, generation)) return;
      final eligibleIds = participantIds.toSet();
      final fresh = <String, DMUserInfo>{};
      for (final row in rows) {
        final userId = (row['userId'] ?? '').toString().trim();
        final displayName = (row['displayName'] ?? '').toString().trim();
        if (!eligibleIds.contains(userId) || displayName.isEmpty) continue;
        fresh[userId] = DMUserInfo(
          uid: userId,
          nickname: displayName,
          photoURL: (row['photoURL'] ?? '').toString().trim(),
          photoVersion: (row['photoVersion'] as num?)?.toInt() ?? 0,
        );
      }
      setState(() {
        _serverAllowedIds = fresh.keys.toSet();
        _profiles.addAll(fresh);
        _loading = false;
        _failed = false;
      });
      unawaited(_profileCache.seedUserInfoBatch(fresh.values));
      unawaited(_warmAvatars(fresh.values));
    } catch (_) {
      if (!_isCurrent(owner, generation)) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  bool _isCurrent(String owner, int generation) =>
      mounted &&
      generation == _loadGeneration &&
      FirebaseAuth.instance.currentUser?.uid == owner;

  Future<void> _warmAvatars(Iterable<DMUserInfo> profiles) async {
    final queue = profiles
        .where((profile) =>
            profile.photoVersion > 0 &&
            ProfilePhotoPolicy.isAllowedProfilePhotoUrl(profile.photoURL))
        .take(20)
        .toList(growable: false);
    const concurrency = 4;
    for (var start = 0; start < queue.length; start += concurrency) {
      final end = (start + concurrency).clamp(0, queue.length);
      await Future.wait(queue
          .sublist(start, end)
          .map((profile) => AvatarCacheService().getOrDownloadAvatar(
                uid: profile.uid,
                photoVersion: profile.photoVersion,
                photoUrl: profile.photoURL,
              )));
    }
  }

  String _nameFor(String userId) {
    final profile = _profiles[userId];
    if (profile != null &&
        !profile.isDeletedAccount &&
        profile.nickname.trim().isNotEmpty) {
      return profile.nickname.trim();
    }
    return widget.fallbackNames[userId]?.trim() ?? '';
  }

  String _localized(String ko, String zh, String en) =>
      switch (Localizations.localeOf(context).languageCode) {
        'ko' => ko,
        'zh' => zh,
        _ => en,
      };

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, _) {
        final range = widget.controller.activeQuery;
        if (!snackChatMentionsEnabled || range == null) {
          return const SizedBox.shrink();
        }
        final needle = unorm
            .nfc(value.text.substring(range.start + 1, range.end))
            .toLowerCase();
        final allowedIds = _serverAllowedIds;
        final people = _eligibleParticipantIds()
            .where((id) => allowedIds == null || allowedIds.contains(id))
            .map((id) => (id: id, name: _nameFor(id), profile: _profiles[id]))
            .where((person) =>
                person.name.isNotEmpty &&
                unorm.nfc(person.name).toLowerCase().contains(needle))
            .toList(growable: false);

        final availableHeight = MediaQuery.sizeOf(context).height -
            MediaQuery.viewInsetsOf(context).bottom -
            MediaQuery.viewPaddingOf(context).vertical -
            kToolbarHeight;
        final maxHeight = (availableHeight * .34).clamp(0.0, 300.0);
        if (maxHeight < 48) return const SizedBox.shrink();

        Widget child;
        if (people.isEmpty && _loading) {
          child = _statusRow(
            label: _localized('참여자를 불러오는 중', '正在加载成员', 'Loading members'),
            leading: const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF2D9CDB),
              ),
            ),
          );
        } else if (people.isEmpty && _failed) {
          child = _statusRow(
            label: _localized(
              '참여자를 불러오지 못했어요.',
              '成员加载失败。',
              'Could not load members.',
            ),
            trailing: TextButton(
              onPressed: () => _primeParticipants(forceRefresh: true),
              child: Text(_localized('다시 시도', '重试', 'Retry')),
            ),
          );
        } else if (people.isEmpty) {
          child = _statusRow(
            label: _localized(
              '일치하는 참여자가 없어요.',
              '没有匹配的成员。',
              'No matching members.',
            ),
          );
        } else {
          child = ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
              itemCount: people.length,
              separatorBuilder: (_, __) => const SizedBox(height: 1),
              itemBuilder: (context, index) {
                final person = people[index];
                final profile = person.profile;
                return InkWell(
                  onTap: () {
                    widget.controller.insertMention(person.id, person.name);
                    widget.focusNode.requestFocus();
                  },
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 56),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      child: Row(
                        children: [
                          UserAvatar(
                            uid: person.id,
                            photoUrl: profile?.photoURL ?? '',
                            photoVersion: profile?.photoVersion ?? 0,
                            isAnonymous: false,
                            size: 40,
                            placeholderColor: const Color(0xFFF2F4F7),
                            placeholderIconSize: 21,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              person.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: uiFontFamily(context, 'Inter'),
                                fontFamilyFallback: const [
                                  'NotoSansKR',
                                  'NotoSansSC',
                                ],
                                fontSize: 15.5,
                                height: 1.25,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFF101828),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        }

        return DecoratedBox(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE4E7EC))),
          ),
          child: child,
        );
      },
    );
  }

  Widget _statusRow({
    required String label,
    Widget? leading,
    Widget? trailing,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        child: Row(
          children: [
            if (leading != null) ...[leading, const SizedBox(width: 10)],
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
                  fontSize: 13.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF344054),
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
