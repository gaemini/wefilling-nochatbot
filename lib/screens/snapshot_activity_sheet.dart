// lib/screens/snapshot_activity_sheet.dart
// 작성자용 활동 시트(스낵 v3): 필링 n · 본 사람 m, 서로 필링, 본 사람 목록.
// 필링은 서로 필링이 되기 전까지 누가 보냈는지 보이지 않으므로 본 사람 행에는
// 필링 여부를 표시하지 않는다. 관계 버튼은 RelationshipProvider 스트림 상태만
// 읽는다(행마다 서버 조회 없음).

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/ui_locale.dart';
import '../models/relationship_status.dart';
import '../models/snapshot.dart';
import '../models/snapshot_mutual_feel.dart';
import '../providers/relationship_provider.dart';
import '../services/dm_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snack_feel_icon.dart';
import '../snapshot/snapshot_strings.dart';
import '../snapshot/snapshot_viewer_chrome.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/user_avatar.dart';
import 'dm_chat_screen.dart';

/// 관계 상태에 따라 오른쪽 버튼이 달라지는 본 사람 한 줄.
class SnapshotActivityViewerRow extends StatelessWidget {
  const SnapshotActivityViewerRow({
    super.key,
    required this.viewer,
    required this.status,
    required this.now,
    required this.onAddFriend,
    required this.onMessage,
  });

  final SnapshotViewer viewer;

  /// 스트림이 아직 준비 전이면 null(버튼은 `메시지`로 둔다).
  final RelationshipStatus? status;
  final DateTime now;
  final VoidCallback onAddFriend;
  final VoidCallback onMessage;

  static String relativeTime(
    SnapshotStrings strings,
    DateTime viewedAt,
    DateTime now,
  ) {
    final minutes = now.difference(viewedAt).inMinutes;
    if (minutes < 1) return strings.viewedJustNow;
    if (minutes < 60) return strings.viewedMinutesAgo(minutes);
    return strings.viewedHoursAgo((minutes ~/ 60).clamp(1, 48));
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final name = viewer.displayName.trim().isEmpty
        ? strings.snapshot
        : viewer.displayName.trim();
    final time = relativeTime(strings, viewer.viewedAt, now);
    // 필링 여부는 표시하지 않는다.
    final subtitle = time;
    final isNone = status == RelationshipStatus.none;
    final isPendingOut = status == RelationshipStatus.pendingOut;
    final label = isNone
        ? strings.addFriendShort
        : isPendingOut
            ? strings.friendRequestedShort
            : strings.messageShort;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          UserAvatar(
            uid: viewer.userId,
            photoUrl: viewer.photoUrl,
            photoVersion: viewer.photoVersion,
            isAnonymous: false,
            size: 36,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(context, 15, FontWeight.w600, Colors.black),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(
                    context,
                    12.5,
                    FontWeight.w500,
                    const Color(0xFF707070),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 44,
            child: Center(
              child: Material(
                color: isNone ? snapshotAccent : const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: ValueKey<String>('viewer-action-${viewer.userId}'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: isPendingOut
                      ? null
                      : (isNone ? onAddFriend : onMessage),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 32),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        widthFactor: 1,
                        child: Text(
                          label,
                          maxLines: 1,
                          style: _style(
                            context,
                            13,
                            FontWeight.w600,
                            isNone
                                ? Colors.white
                                : (isPendingOut
                                    ? const Color(0xFF707070)
                                    : Colors.black),
                          ),
                        ),
                      ),
                    ),
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

TextStyle _style(
  BuildContext context,
  double size,
  FontWeight weight,
  Color color,
) =>
    TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: size,
      fontWeight: weight,
      color: color,
      height: isChineseUi(context) ? 1.35 : 1.2,
    );

class SnapshotActivitySheet extends StatefulWidget {
  const SnapshotActivitySheet({
    super.key,
    required this.snapshot,
    this.viewersStream,
    this.mutualFeelsLoader,
  });

  final SnapshotItem snapshot;

  /// 테스트용. 없으면 `SnapshotService.watchViewers`.
  final Stream<List<SnapshotViewer>>? viewersStream;

  /// 테스트용. 없으면 `SnapshotService.getMyMutualFeels(snapshotId:)`.
  final Future<List<SnapshotMutualFeel>> Function()? mutualFeelsLoader;

  static Future<void> show(BuildContext context, {required SnapshotItem snapshot}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SnapshotActivitySheet(snapshot: snapshot),
    );
  }

  @override
  State<SnapshotActivitySheet> createState() => _SnapshotActivitySheetState();
}

class _SnapshotActivitySheetState extends State<SnapshotActivitySheet> {
  late final Stream<List<SnapshotViewer>> _viewers =
      (widget.viewersStream ??
              SnapshotService.instance.watchViewers(widget.snapshot.id))
          .asBroadcastStream();
  late Future<List<SnapshotMutualFeel>> _mutuals;
  DMService? _dmService;
  DMService get _dm => _dmService ??= DMService();
  final Set<String> _requesting = <String>{};

  @override
  void initState() {
    super.initState();
    _mutuals = _loadMutuals();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        unawaited(
          context
              .read<RelationshipProvider>()
              .ensureInitialized()
              .catchError((Object _) {}),
        );
      } catch (_) {}
    });
  }

  Future<List<SnapshotMutualFeel>> _loadMutuals() async {
    try {
      final loader = widget.mutualFeelsLoader;
      if (loader != null) return await loader();
      return await SnapshotService.instance
          .getMyMutualFeels(snapshotId: widget.snapshot.id);
    } catch (_) {
      return const <SnapshotMutualFeel>[];
    }
  }

  Future<void> _addFriend(String uid) async {
    if (!_requesting.add(uid)) return;
    try {
      final provider = context.read<RelationshipProvider>();
      final ok = await provider.sendFriendRequest(uid, silent: true);
      if (!mounted) return;
      if (!ok) {
        AppSnackBar.show(
          context,
          message: SnapshotStrings.of(context).commentFailed,
          type: AppSnackBarType.error,
        );
      }
    } finally {
      _requesting.remove(uid);
    }
  }

  Future<void> _message(String uid) async {
    try {
      final room = await _dm.prepareConversationForOpen(uid);
      if (!mounted || room == null) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => DMChatScreen(conversationId: room, otherUserId: uid),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      AppSnackBar.show(
        context,
        message: SnapshotStrings.of(context).commentFailed,
        type: AppSnackBarType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final height = MediaQuery.sizeOf(context).height;
    final feels = widget.snapshot.reactionCounts.values
        .fold<int>(0, (sum, value) => sum + value);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Container(
        height: height * .72,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: StreamBuilder<List<SnapshotViewer>>(
          stream: _viewers,
          builder: (context, result) {
            final viewers = result.data ?? const <SnapshotViewer>[];
            final now = DateTime.now();
            return ListView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom + 16,
              ),
              children: [
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD0D0D0),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
                _header(strings, feels, viewers.length),
                FutureBuilder<List<SnapshotMutualFeel>>(
                  future: _mutuals,
                  builder: (context, mutual) {
                    final items = mutual.data ?? const <SnapshotMutualFeel>[];
                    if (items.isEmpty) return const SizedBox.shrink();
                    return _mutualSection(strings, items);
                  },
                ),
                const Divider(height: 24, thickness: 1, color: Color(0xFFEBEBEB)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    strings.viewersTab(viewers.length),
                    style: _style(
                      context,
                      12,
                      FontWeight.w600,
                      const Color(0xFF5F5F5F),
                    ),
                  ),
                ),
                if (result.hasError)
                  _note(strings.viewersLoadFailed)
                else if (!result.hasData)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox.square(
                        dimension: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (viewers.isEmpty)
                  _note(strings.noViewers)
                else
                  for (final viewer in viewers)
                    Selector<RelationshipProvider, RelationshipStatus?>(
                      key: ValueKey<String>('viewer-${viewer.userId}'),
                      selector: (_, provider) =>
                          provider.feedRelationshipStatus(viewer.userId),
                      builder: (context, status, _) => SnapshotActivityViewerRow(
                        viewer: viewer,
                        status: status,
                        now: now,
                        onAddFriend: () => unawaited(_addFriend(viewer.userId)),
                        onMessage: () => unawaited(_message(viewer.userId)),
                      ),
                    ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Text(
                    strings.viewersNoFeel,
                    key: const ValueKey('viewers_no_feel_note'),
                    style: _style(
                      context,
                      11,
                      FontWeight.w500,
                      const Color(0xFF707070),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _note(String text) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: _style(context, 14, FontWeight.w500, const Color(0xFF707070)),
          ),
        ),
      );

  Widget _header(SnapshotStrings strings, int feels, int viewers) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF4FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: SnackFeelIcon(
                    size: 26,
                    filled: true,
                    color: snapshotAccent,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      strings.feelCountLabel(feels),
                      key: const ValueKey('activity_feel_count'),
                      style: _style(context, 20, FontWeight.w700, Colors.black)
                          .copyWith(height: 26 / 20),
                    ),
                    Text(
                      strings.viewersTab(viewers),
                      style: _style(
                        context,
                        12,
                        FontWeight.w400,
                        const Color(0xFF707070),
                      ).copyWith(height: 17 / 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            strings.feelHiddenHint,
            style: _style(context, 12, FontWeight.w400, const Color(0xFF707070))
                .copyWith(height: 17 / 12),
          ),
        ],
      ),
    );
  }

  Widget _mutualSection(
    SnapshotStrings strings,
    List<SnapshotMutualFeel> items,
  ) {
    User? me;
    try {
      me = FirebaseAuth.instance.currentUser;
    } catch (_) {
      me = null;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.mutualFeelSection,
            style: _style(context, 12, FontWeight.w600, const Color(0xFF5F5F5F)),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Container(
              key: ValueKey<String>('mutual-${item.pairKey}'),
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7FD),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 36 + 24,
                    height: 36,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 0,
                          child: UserAvatar(
                            uid: me?.uid ?? '',
                            photoUrl: me?.photoURL ?? '',
                            photoVersion: 0,
                            isAnonymous: false,
                            size: 36,
                          ),
                        ),
                        Positioned(
                          left: 24,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 2),
                            ),
                            child: UserAvatar(
                              uid: item.otherUserId,
                              photoUrl: item.otherPhotoUrl,
                              photoVersion: item.otherPhotoVersion,
                              isAnonymous: false,
                              size: 36,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.otherName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: _style(
                            context,
                            14,
                            FontWeight.w600,
                            Colors.black,
                          ),
                        ),
                        Text(
                          strings.mutualFeelWithSnack,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: _style(
                            context,
                            12,
                            FontWeight.w400,
                            const Color(0xFF5F5F5F),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: snapshotAccent,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      key: ValueKey<String>('say-hi-${item.otherUserId}'),
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => unawaited(_message(item.otherUserId)),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 32,
                          minWidth: 44,
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Center(
                            widthFactor: 1,
                            child: Text(
                              strings.sayHi,
                              style: _style(
                                context,
                                13,
                                FontWeight.w600,
                                Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
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
