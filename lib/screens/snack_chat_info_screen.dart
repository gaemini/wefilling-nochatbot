import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../models/snack_chat.dart';
import '../models/user_profile.dart';
import '../repositories/users_repository.dart';
import '../services/snack_chat_service.dart';
import '../ui/sheets/snack_chat_unfavorite_sheet.dart';
import '../utils/country_flag_helper.dart';
import '../utils/responsive_helper.dart';
import 'friend_profile_screen.dart';

class SnackChatInfoScreen extends StatefulWidget {
  final String snackChatId;

  const SnackChatInfoScreen({
    super.key,
    required this.snackChatId,
  });

  @override
  State<SnackChatInfoScreen> createState() => _SnackChatInfoScreenState();
}

class _SnackChatInfoScreenState extends State<SnackChatInfoScreen> {
  final SnackChatService _snackChatService = SnackChatService();
  final UsersRepository _usersRepository = UsersRepository();

  bool _isInviting = false;
  bool _isInviteSheetOpen = false;
  bool _isMuted = false;
  bool _isUpdatingMute = false;
  bool _isUpdatingFavorite = false;
  int _muteMutationGeneration = 0;
  bool _isUpdatingTitle = false;
  bool _isSendingAnnouncement = false;
  bool _isCreatorTextDialogOpen = false;
  String? _pendingAnnouncementBody;
  String? _pendingAnnouncementEventId;
  Future<List<UserProfile>>? _participantsFuture;
  String _participantsSignature = '';
  SnackChat? _lastRoom;
  late Stream<SnackChat?> _roomStream;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  @override
  void initState() {
    super.initState();
    _roomStream = _snackChatService.watchSnackChat(widget.snackChatId);
    _loadMuteState();
  }

  Future<void> _loadMuteState() async {
    final generation = _muteMutationGeneration;
    final muted = await _snackChatService.isSnackChatMuted(widget.snackChatId);
    if (mounted && generation == _muteMutationGeneration) {
      setState(() => _isMuted = muted);
    }
  }

  void _retryRoomStream() {
    if (!mounted) return;
    setState(() {
      _roomStream = _snackChatService.watchSnackChat(widget.snackChatId);
    });
  }

  Future<void> _toggleMute() async {
    if (_isUpdatingMute) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final previous = _isMuted;
    final newVal = !_isMuted;
    _muteMutationGeneration++;
    setState(() {
      _isUpdatingMute = true;
      _isMuted = newVal;
    });
    try {
      await _snackChatService.toggleMuteSnackChat(widget.snackChatId, newVal);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isMuted = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo
                ? '알림 설정을 저장하지 못했습니다.'
                : 'Could not update notification settings.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingMute = false);
      } else {
        _isUpdatingMute = false;
      }
    }
  }

  Future<List<UserProfile>> _loadParticipants(SnackChat room) async {
    if (room.participantIds.isEmpty) return const <UserProfile>[];
    unawaited(_snackChatService.ensureParticipantIntegrity(room));
    final users =
        await _usersRepository.getFreshUserProfilesBatch(room.participantIds);
    users.sort(
        (a, b) => a.displayNameOrNickname.compareTo(b.displayNameOrNickname));
    return users;
  }

  void _ensureParticipantsFuture(SnackChat room) {
    final signature = room.participantIds.toList()..sort();
    final key = signature.join('|');
    if (_participantsFuture == null || _participantsSignature != key) {
      _participantsSignature = key;
      _participantsFuture = _loadParticipants(room);
    }
  }

  Future<void> _openInviteSheet(SnackChat room) async {
    if (!room.canInviteMembers(_uid) || _isInviting || _isInviteSheetOpen) {
      return;
    }
    _isInviteSheetOpen = true;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    late final List<UserProfile> myFriends;
    try {
      myFriends = await _usersRepository.getUserFriends(_uid!);
    } catch (_) {
      _isInviteSheetOpen = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '친구 목록을 불러오지 못했습니다.' : 'Could not load your friends.',
          ),
        ),
      );
      return;
    }
    final currentIds = room.participantIds.toSet();
    final candidates =
        myFriends.where((f) => !currentIds.contains(f.uid)).toList();
    if (!mounted) {
      _isInviteSheetOpen = false;
      return;
    }

    if (candidates.isEmpty) {
      _isInviteSheetOpen = false;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '초대 가능한 친구가 없습니다.' : 'No friends available to invite.',
          ),
        ),
      );
      return;
    }

    final selected = <String>{};
    var searchQuery = '';
    var searchFieldVersion = 0;
    var isClosing = false;
    Set<String>? result;
    try {
      result = await showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              final l10n = AppLocalizations.of(context)!;
              final visibleCandidates = candidates.where((friend) {
                if (searchQuery.isEmpty) return true;
                return friend.displayNameOrNickname
                    .toLowerCase()
                    .contains(searchQuery);
              }).toList(growable: false);
              final sheetHeight = (MediaQuery.sizeOf(context).height * 0.82)
                  .clamp(420.0, 720.0)
                  .toDouble();

              return SafeArea(
                top: false,
                child: SizedBox(
                  height: sheetHeight,
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD0D5DD),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            context.rs(20).clamp(16, 24).toDouble(),
                            context.rs(18).clamp(16, 22).toDouble(),
                            context.rs(20).clamp(16, 24).toDouble(),
                            0,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.snackChatSelectParticipants,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(18).clamp(17, 20).toDouble(),
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  letterSpacing: -0.2,
                                  color: const Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                l10n.snackChatMaxParticipants,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: context
                                      .rf(12.5)
                                      .clamp(12, 13.5)
                                      .toDouble(),
                                  fontWeight: FontWeight.w500,
                                  height: 1.4,
                                  color: const Color(0xFF667085),
                                ),
                              ),
                              SizedBox(
                                height: context.rs(12).clamp(10, 14).toDouble(),
                              ),
                              TextField(
                                key: ValueKey(searchFieldVersion),
                                textInputAction: TextInputAction.search,
                                onChanged: (value) {
                                  setSheetState(
                                    () => searchQuery =
                                        value.trim().toLowerCase(),
                                  );
                                },
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(14).clamp(13, 15).toDouble(),
                                  color: const Color(0xFF111827),
                                ),
                                decoration: InputDecoration(
                                  hintText: l10n.searchByName,
                                  hintStyle: const TextStyle(
                                    fontFamily: 'Inter',
                                    fontFamilyFallback: const ['NotoSansKR'],
                                    fontSize: 14,
                                    color: Color(0xFF98A2B3),
                                  ),
                                  prefixIcon: const Icon(
                                    Icons.search_rounded,
                                    size: 20,
                                    color: Color(0xFF667085),
                                  ),
                                  prefixIconConstraints: const BoxConstraints(
                                    minWidth: 36,
                                    minHeight: 44,
                                  ),
                                  suffixIcon: searchQuery.isEmpty
                                      ? null
                                      : IconButton(
                                          onPressed: () {
                                            setSheetState(() {
                                              searchQuery = '';
                                              searchFieldVersion++;
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                        ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  border: const UnderlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Color(0xFFEAECF0)),
                                  ),
                                  enabledBorder: const UnderlineInputBorder(
                                    borderSide:
                                        BorderSide(color: Color(0xFFEAECF0)),
                                  ),
                                  focusedBorder: const UnderlineInputBorder(
                                    borderSide: BorderSide(
                                      color: Color(0xFF667085),
                                      width: 1.4,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Expanded(
                          child: visibleCandidates.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                    ),
                                    child: Text(
                                      l10n.snackChatNoFriendsToInvite,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontFamilyFallback: const [
                                          'NotoSansKR'
                                        ],
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF667085),
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  padding: EdgeInsets.fromLTRB(
                                    context.rs(8).clamp(4, 12).toDouble(),
                                    2,
                                    context.rs(8).clamp(4, 12).toDouble(),
                                    12,
                                  ),
                                  itemCount: visibleCandidates.length,
                                  itemBuilder: (_, index) {
                                    final friend = visibleCandidates[index];
                                    final checked =
                                        selected.contains(friend.uid);
                                    return _InviteParticipantTile(
                                      friend: friend,
                                      selected: checked,
                                      onTap: () {
                                        setSheetState(() {
                                          if (checked) {
                                            selected.remove(friend.uid);
                                          } else {
                                            selected.add(friend.uid);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                        ),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            context.rs(20).clamp(16, 24).toDouble(),
                            8,
                            context.rs(20).clamp(16, 24).toDouble(),
                            12,
                          ),
                          child: SizedBox(
                            width: double.infinity,
                            height: context.rh(48, min: 44, max: 50),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                elevation: 0,
                                backgroundColor: const Color(0xFF344054),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor:
                                    const Color(0xFFD0D5DD),
                                disabledForegroundColor:
                                    const Color(0xFF98A2B3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: selected.isEmpty || isClosing
                                  ? null
                                  : () {
                                      setSheetState(() => isClosing = true);
                                      FocusScope.of(sheetContext).unfocus();
                                      Navigator.of(sheetContext).pop(
                                        Set<String>.from(selected),
                                      );
                                    },
                              child: Text(
                                isKo
                                    ? '초대하기 (${selected.length}명)'
                                    : 'Invite (${selected.length})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(15).clamp(14, 16).toDouble(),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      _isInviteSheetOpen = false;
    }

    if (result == null || result.isEmpty || !mounted) return;

    setState(() => _isInviting = true);
    try {
      final invited = await _snackChatService.inviteParticipants(
        room.id,
        participantIds: result.toList(),
      );
      if (invited.isEmpty || !mounted) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo
                ? '${invited.length}명을 초대했습니다.'
                : 'Invited ${invited.length} participants.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '초대 실패: $e' : 'Invite failed: $e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isInviting = false);
    }
  }

  Future<void> _toggleFavorite(SnackChat room) async {
    if (_isUpdatingFavorite) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    final nextValue = !room.isFavoritedBy(currentUserId);
    setState(() => _isUpdatingFavorite = true);
    try {
      if (!nextValue) {
        final confirmed = await showSnackChatUnfavoriteSheet(context);
        if (!mounted || !confirmed) return;
      }
      await _snackChatService.toggleFavorite(room.id, nextValue);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo
                ? '즐겨찾기 설정을 저장하지 못했습니다.'
                : 'Could not update favorite settings.',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isUpdatingFavorite = false);
      } else {
        _isUpdatingFavorite = false;
      }
    }
  }

  Future<String?> _showCreatorTextDialog({
    required String title,
    required String hintText,
    required String actionLabel,
    required int maxLength,
    required int maxLines,
    String initialValue = '',
  }) async {
    if (_isCreatorTextDialogOpen || !mounted) return null;
    _isCreatorTextDialogOpen = true;
    final dialogRoute = DialogRoute<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (_) => _CreatorTextDialog(
        title: title,
        hintText: hintText,
        actionLabel: actionLabel,
        maxLength: maxLength,
        maxLines: maxLines,
        initialValue: initialValue,
      ),
    );
    try {
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push<String>(dialogRoute);
      // Route.popped는 reverse transition 시작 시 완료된다. 다이얼로그의
      // element가 overlay에서 완전히 제거된 뒤 부모 화면 상태를 바꿔야
      // _InactiveElements 해제 경합이 발생하지 않는다.
      await dialogRoute.completed;
      return result;
    } finally {
      _isCreatorTextDialogOpen = false;
    }
  }

  Future<void> _changeRoomTitle(SnackChat room) async {
    if (_isUpdatingTitle || _uid != room.creatorId) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final nextTitle = await _showCreatorTextDialog(
      title: isKo ? '스낵챗 이름 변경' : 'Rename Snack Chat',
      hintText: isKo ? '새 이름을 입력해 주세요.' : 'Enter a new name.',
      actionLabel: isKo ? '변경' : 'Rename',
      maxLength: 40,
      maxLines: 1,
      initialValue: room.title,
    );
    if (!mounted || nextTitle == null || nextTitle == room.title.trim()) return;
    setState(() => _isUpdatingTitle = true);
    try {
      await _snackChatService.updateSnackChatTitle(room.id, nextTitle);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '스낵챗 이름을 변경했습니다.' : 'Snack Chat renamed.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '이름을 변경하지 못했습니다.' : 'Could not rename the Snack Chat.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isUpdatingTitle = false);
    }
  }

  Future<void> _createAnnouncement(SnackChat room) async {
    if (_isSendingAnnouncement || _uid != room.creatorId) return;
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final body = await _showCreatorTextDialog(
      title: isKo ? '공지 등록' : 'Post announcement',
      hintText: isKo ? '멤버에게 알릴 내용을 입력해 주세요.' : 'Write an announcement.',
      actionLabel: isKo ? '등록' : 'Post',
      maxLength: 500,
      maxLines: 6,
    );
    if (!mounted || body == null) return;
    final normalizedBody = body.trim();
    final reusableEventId = _pendingAnnouncementBody == normalizedBody
        ? _pendingAnnouncementEventId
        : null;
    final eventId =
        reusableEventId ?? _snackChatService.createAnnouncementEventId(room.id);
    // Preserve this pair across an error or a lost callable response. A
    // manual retry of the same body then targets the deterministic server
    // document instead of appending a duplicate announcement.
    _pendingAnnouncementBody = normalizedBody;
    _pendingAnnouncementEventId = eventId;
    setState(() => _isSendingAnnouncement = true);
    try {
      await _snackChatService.createAnnouncement(
        snackChatId: room.id,
        text: normalizedBody,
        eventId: eventId,
      );
      if (_pendingAnnouncementBody == normalizedBody &&
          _pendingAnnouncementEventId == eventId) {
        _pendingAnnouncementBody = null;
        _pendingAnnouncementEventId = null;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '공지를 등록했습니다.' : 'Announcement posted.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isKo ? '공지를 등록하지 못했습니다.' : 'Could not post announcement.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSendingAnnouncement = false);
    }
  }

  Future<void> _leaveRoom() async {
    final dialogRoute = DialogRoute<bool>(
      context: context,
      barrierColor: const Color(0x99000000),
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      builder: (dialogContext) {
        final dialogIsKo =
            Localizations.localeOf(dialogContext).languageCode == 'ko';
        return Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          insetPadding: EdgeInsets.symmetric(
            horizontal: context.rs(28).clamp(20, 36).toDouble(),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  context.rs(22).clamp(20, 24).toDouble(),
                  context.rs(22).clamp(20, 24).toDouble(),
                  context.rs(16).clamp(12, 18).toDouble(),
                  context.rs(12).clamp(10, 14).toDouble(),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dialogIsKo ? '채팅방 나가기' : 'Leave Chat Room',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(17).clamp(16, 18).toDouble(),
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: const Color(0xFF111827),
                      ),
                    ),
                    SizedBox(height: context.rs(8).clamp(6, 10).toDouble()),
                    Text(
                      dialogIsKo
                          ? '채팅방에서 나가면 목록과 대화를 볼 수 없으며, 다시 참여하려면 초대를 받아야 합니다.'
                          : 'After leaving, this room and its messages will no longer be available. You will need another invitation to rejoin.',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(13.5).clamp(13, 14.5).toDouble(),
                        fontWeight: FontWeight.w400,
                        height: 1.5,
                        color: const Color(0xFF667085),
                      ),
                    ),
                    SizedBox(height: context.rs(14).clamp(12, 18).toDouble()),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 2,
                        runSpacing: 2,
                        alignment: WrapAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF667085),
                              minimumSize: const Size(64, 40),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              dialogIsKo ? '취소' : 'Cancel',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFB42318),
                              minimumSize: const Size(64, 40),
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              dialogIsKo ? '나가기' : 'Leave',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    final confirm = await Navigator.of(
      context,
      rootNavigator: true,
    ).push<bool>(dialogRoute);
    if (confirm != true) return;
    // DialogRoute.popped는 reverse transition이 끝나기 전에 완료된다.
    // overlay가 완전히 제거된 다음 정보 화면을 닫아 연속 route teardown을
    // 만들지 않는다.
    await dialogRoute.completed;
    if (!mounted) return;
    // 서버 응답을 기다리며 정보 화면과 채팅 화면의 StreamBuilder를 동시에
    // 해제하면 라우트 teardown과 참여자 변경 이벤트가 경합할 수 있다.
    // 정보 화면은 결과만 반환하고, 완전히 닫힌 뒤 부모 채팅 화면이 실제
    // 나가기 요청과 자신의 라우트 종료를 한 곳에서 처리한다.
    Navigator.of(context).pop(true);
  }

  Widget _buildRoomSummary(
    BuildContext context,
    SnackChat room,
    AppLocalizations l10n, {
    required int participantCount,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: context.rs(16).clamp(14, 18).toDouble(),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox.square(
            dimension: context.ri(36).clamp(34, 38).toDouble(),
            child: Center(
              child: Icon(
                Icons.forum_outlined,
                size: context.ri(22).clamp(20, 23).toDouble(),
                color: const Color(0xFF475467),
              ),
            ),
          ),
          SizedBox(width: context.rs(10).clamp(8, 12).toDouble()),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  room.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(16).clamp(15, 17).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                    height: 1.25,
                  ),
                ),
                SizedBox(height: context.rs(6).clamp(4, 7).toDouble()),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      l10n.snackChatParticipantCount(participantCount),
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF667085),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          room.hasNoExpiration
                              ? Icons.all_inclusive_rounded
                              : Icons.schedule_rounded,
                          size: context.ri(14).clamp(13, 15).toDouble(),
                          color: const Color(0xFF667085),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          room.hasNoExpiration
                              ? l10n.snackChatDurationNoEnd
                              : l10n.snackChatDuration24Hours,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize:
                                context.rf(12.5).clamp(12, 13.5).toDouble(),
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingRow({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Semantics(
      toggled: value,
      label: title,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 32,
              child: Center(
                child: Icon(
                  icon,
                  color: iconColor,
                  size: context.ri(19).clamp(18, 20).toDouble(),
                ),
              ),
            ),
            SizedBox(width: context.rs(8)),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(14.5).clamp(13.5, 15.5).toDouble(),
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF1F2937),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 46,
              height: 38,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: const Color(0xFF344054),
                  activeTrackColor: const Color(0xFFD0D5DD),
                  inactiveThumbColor: const Color(0xFF98A2B3),
                  inactiveTrackColor: const Color(0xFFEAECF0),
                  trackOutlineColor: const WidgetStatePropertyAll(
                    Colors.transparent,
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: true,
      child: StreamBuilder<SnackChat?>(
        stream: _roomStream,
        builder: (context, snap) {
          final incomingRoom = snap.data;
          if (incomingRoom != null) _lastRoom = incomingRoom;
          final room = incomingRoom ?? _lastRoom;
          if (room == null) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasError) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return Scaffold(
              appBar: AppBar(
                title: const Text(
                  'Snack Chat',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isKo
                          ? '채팅방 정보를 불러올 수 없습니다.'
                          : 'Unable to load chat room information.',
                    ),
                    if (snap.hasError) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _retryRoomStream,
                        icon: const Icon(Icons.refresh_rounded),
                        label: Text(isKo ? '다시 시도' : 'Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }
          _ensureParticipantsFuture(room);

          final isHost = _uid == room.creatorId;
          final canInviteMembers = room.canInviteMembers(_uid);
          final screenWidth = MediaQuery.sizeOf(context).width;
          final pagePadding = screenWidth < 360
              ? 16.0
              : screenWidth < 600
                  ? 20.0
                  : 24.0;
          return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 0,
              toolbarHeight: context.rh(54, min: 52, max: 58),
              leadingWidth: 48,
              leading: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: context.ri(22).clamp(21, 24).toDouble(),
                ),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              ),
              titleSpacing: 0,
              title: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.2,
                child: Text(
                  'Snack Chat',
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: context.rf(18).clamp(17, 19).toDouble(),
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
              ),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: FutureBuilder<List<UserProfile>>(
                  future: _participantsFuture,
                  builder: (context, usersSnap) {
                    final participants =
                        usersSnap.data ?? const <UserProfile>[];
                    return ListView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.fromLTRB(
                        pagePadding,
                        2,
                        pagePadding,
                        24 + MediaQuery.paddingOf(context).bottom,
                      ),
                      children: [
                        _buildRoomSummary(
                          context,
                          room,
                          l10n,
                          // 멤버 목록과 같은 활성 프로필 결과를
                          // 사용해 탈퇴 계정을 인원에 포함하지 않는다.
                          participantCount: usersSnap.hasData
                              ? participants.length
                              : room.participantCount,
                        ),
                        if (isHost)
                          Padding(
                            padding: EdgeInsets.only(
                              bottom: context.rs(10).clamp(8, 12).toDouble(),
                            ),
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: [
                                TextButton.icon(
                                  onPressed: _isUpdatingTitle
                                      ? null
                                      : () => _changeRoomTitle(room),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF475467),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 7,
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: _isUpdatingTitle
                                      ? const SizedBox.square(
                                          dimension: 15,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.8,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.edit_outlined,
                                          size: 17,
                                        ),
                                  label: Text(
                                    isKo ? '이름 변경' : 'Rename',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontFamilyFallback: const ['NotoSansKR'],
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: _isSendingAnnouncement
                                      ? null
                                      : () => _createAnnouncement(room),
                                  style: TextButton.styleFrom(
                                    foregroundColor: const Color(0xFF475467),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 7,
                                    ),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: _isSendingAnnouncement
                                      ? const SizedBox.square(
                                          dimension: 15,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.8,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.campaign_outlined,
                                          size: 18,
                                        ),
                                  label: Text(
                                    isKo ? '공지 등록' : 'Announcement',
                                    style: const TextStyle(
                                      fontFamily: 'Inter',
                                      fontFamilyFallback: const ['NotoSansKR'],
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        _buildSettingRow(
                          context: context,
                          icon: room.isFavoritedBy(_uid)
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          iconColor: const Color(0xFF667085),
                          title: isKo ? '채팅 즐겨찾기' : 'Favorite this chat',
                          value: room.isFavoritedBy(_uid),
                          onChanged: _isUpdatingFavorite
                              ? null
                              : (_) => _toggleFavorite(room),
                        ),
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        _buildSettingRow(
                          context: context,
                          icon: _isMuted
                              ? Icons.notifications_off_outlined
                              : Icons.notifications_none_rounded,
                          iconColor: const Color(0xFF667085),
                          title: isKo ? '알림' : 'Notifications',
                          value: !_isMuted,
                          onChanged:
                              _isUpdatingMute ? null : (_) => _toggleMute(),
                        ),
                        SizedBox(
                            height: context.rs(18).clamp(16, 22).toDouble()),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                isKo ? '참여 멤버' : 'MEMBERS',
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(13).clamp(12, 14).toDouble(),
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF667085),
                                  letterSpacing: isKo ? 0 : 0.7,
                                ),
                              ),
                            ),
                            if (canInviteMembers)
                              SizedBox.square(
                                dimension: 40,
                                child: IconButton(
                                  onPressed: _isInviting
                                      ? null
                                      : () => _openInviteSheet(room),
                                  padding: EdgeInsets.zero,
                                  style: IconButton.styleFrom(
                                    foregroundColor: const Color(0xFF475467),
                                    disabledForegroundColor:
                                        const Color(0xFF98A2B3),
                                  ),
                                  tooltip: isKo ? '멤버 초대' : 'Invite members',
                                  icon: _isInviting
                                      ? const SizedBox.square(
                                          dimension: 17,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          Icons.add_rounded,
                                          size: context
                                              .ri(26)
                                              .clamp(24, 28)
                                              .toDouble(),
                                          color: const Color(0xFF475467),
                                        ),
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: context.rs(4)),
                        if (usersSnap.connectionState ==
                                ConnectionState.waiting &&
                            participants.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 28),
                            child: Center(
                              child: SizedBox.square(
                                dimension: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        else if (participants.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Text(
                              isKo ? '표시할 멤버가 없습니다.' : 'No members to show.',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 13,
                                color: Color(0xFF98A2B3),
                              ),
                            ),
                          )
                        else
                          ...List.generate(
                            participants.length,
                            (index) => _MemberTile(
                              user: participants[index],
                              showDivider: index < participants.length - 1,
                            ),
                          ),
                        SizedBox(height: context.rs(14)),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _leaveRoom,
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF667085),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 8,
                              ),
                            ),
                            icon: const Icon(Icons.logout_rounded, size: 17),
                            label: Text(
                              isKo ? '채팅방 나가기' : 'Leave Room',
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CreatorTextDialog extends StatefulWidget {
  const _CreatorTextDialog({
    required this.title,
    required this.hintText,
    required this.actionLabel,
    required this.maxLength,
    required this.maxLines,
    required this.initialValue,
  });

  final String title;
  final String hintText;
  final String actionLabel;
  final int maxLength;
  final int maxLines;
  final String initialValue;

  @override
  State<_CreatorTextDialog> createState() => _CreatorTextDialogState();
}

class _CreatorTextDialogState extends State<_CreatorTextDialog> {
  late final TextEditingController _controller;
  late bool _canSubmit;
  bool _isClosing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _canSubmit = widget.initialValue.trim().isNotEmpty;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_isClosing) return;
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    _isClosing = true;
    Navigator.of(context).pop(value);
  }

  void _cancel() {
    if (_isClosing) return;
    _isClosing = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      scrollable: true,
      insetPadding: EdgeInsets.symmetric(
        horizontal: context.rs(24).clamp(18, 32).toDouble(),
      ),
      title: Text(
        widget.title,
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: context.rf(18).clamp(17, 19).toDouble(),
          fontWeight: FontWeight.w700,
          color: const Color(0xFF111827),
        ),
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: widget.maxLines == 1 ? 1 : 3,
          maxLines: widget.maxLines,
          maxLength: widget.maxLength,
          textInputAction: widget.maxLines == 1
              ? TextInputAction.done
              : TextInputAction.newline,
          onSubmitted:
              widget.maxLines == 1 && _canSubmit ? (_) => _submit() : null,
          onChanged: (value) {
            if (_isClosing) return;
            final next = value.trim().isNotEmpty;
            if (next != _canSubmit) setState(() => _canSubmit = next);
          },
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(15).clamp(14, 16).toDouble(),
            height: 1.45,
            color: const Color(0xFF111827),
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: const TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              color: Color(0xFF98A2B3),
            ),
            border: const UnderlineInputBorder(),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFD0D5DD)),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(
                color: Color(0xFF475467),
                width: 1.4,
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _cancel,
          child: Text(isKo ? '취소' : 'Cancel'),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

class _InviteParticipantTile extends StatelessWidget {
  final UserProfile friend;
  final bool selected;
  final VoidCallback onTap;

  const _InviteParticipantTile({
    required this.friend,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = friend.displayNameOrNickname;
    final fallback = name.trim().isEmpty
        ? '?'
        : String.fromCharCode(name.trim().runes.first);

    return Semantics(
      button: true,
      selected: selected,
      label: name,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: context.rh(58, min: 54, max: 62),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.rs(12).clamp(10, 14).toDouble(),
                vertical: context.rs(7).clamp(6, 8).toDouble(),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: context.ri(21).clamp(20, 22).toDouble(),
                    backgroundColor: const Color(0xFFF2F4F7),
                    backgroundImage: friend.hasProfileImage
                        ? NetworkImage(friend.photoURL!)
                        : null,
                    child: friend.hasProfileImage
                        ? null
                        : Text(
                            fallback.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontFamilyFallback: const ['NotoSansKR'],
                              fontSize: context.rf(14).clamp(13, 15).toDouble(),
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF475467),
                            ),
                          ),
                  ),
                  SizedBox(width: context.rs(12).clamp(10, 14).toDouble()),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(14.5).clamp(13.5, 15.5).toDouble(),
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF111827),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    width: context.ri(22).clamp(21, 23).toDouble(),
                    height: context.ri(22).clamp(21, 23).toDouble(),
                    decoration: BoxDecoration(
                      color:
                          selected ? AppColors.pointColor : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected
                            ? AppColors.pointColor
                            : const Color(0xFFB8C0CC),
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final UserProfile user;
  final bool showDivider;

  const _MemberTile({
    required this.user,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Semantics(
          button: true,
          label: user.displayNameOrNickname,
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FriendProfileScreen(
                    userId: user.uid,
                    nickname: user.displayNameOrNickname,
                    photoURL: user.photoURL,
                    email: user.email,
                    university: user.university,
                    allowNonFriendsPreview: true,
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: context.rs(2),
                  vertical: context.rs(7).clamp(6, 9).toDouble(),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: context.ri(19).clamp(18, 20).toDouble(),
                      backgroundColor: const Color(0xFFE5E7EB),
                      backgroundImage:
                          (user.photoURL != null && user.photoURL!.isNotEmpty)
                              ? NetworkImage(user.photoURL!)
                              : null,
                      child: (user.photoURL == null || user.photoURL!.isEmpty)
                          ? Text(
                              user.displayNameOrNickname.isEmpty
                                  ? '?'
                                  : user.displayNameOrNickname[0].toUpperCase(),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontFamilyFallback: const ['NotoSansKR'],
                                fontSize:
                                    context.rf(13).clamp(12, 14).toDouble(),
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF475467),
                              ),
                            )
                          : null,
                    ),
                    SizedBox(width: context.rs(10).clamp(8, 11).toDouble()),
                    Expanded(
                      child: Text(
                        user.displayNameOrNickname,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize:
                              context.rf(14.5).clamp(13.5, 15.5).toDouble(),
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF111827),
                        ),
                      ),
                    ),
                    if (user.nationality != null &&
                        user.nationality!.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        CountryFlagHelper.getFlagEmoji(user.nationality!),
                        style: TextStyle(
                          fontSize: context.rf(15).clamp(14, 16).toDouble(),
                          height: 1,
                        ),
                      ),
                    ],
                    const SizedBox(width: 10),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: const Color(0xFF98A2B3),
                      size: context.ri(18).clamp(17, 19).toDouble(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(
            height: 1,
            indent: 50,
            color: Color(0xFFEAECF0),
          ),
      ],
    );
  }
}
