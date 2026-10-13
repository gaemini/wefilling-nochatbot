// lib/screens/snapshot_activity_sheet.dart
// 작성자용 "내 스낵 활동" 시트: 본 사람 · 반응 · 받은 답장 + 받는 방식.
// 본 사람/반응은 기존 watchViewers(조회+반응 병합) 스트림을 그대로 쓰고,
// 관계 버튼은 RelationshipProvider 스트림 상태만 읽는다(행마다 서버 조회 없음).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/ui_locale.dart';
import '../models/relationship_status.dart';
import '../models/snapshot.dart';
import '../providers/relationship_provider.dart';
import '../services/dm_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_strings.dart';
import '../snapshot/snapshot_viewer_chrome.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/user_avatar.dart';
import 'dm_chat_screen.dart';
import 'notification_screen.dart';

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
    final subtitle =
        viewer.reaction.isEmpty ? time : '${viewer.reaction} · $time';
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

/// 3칸 세그먼트. 현재 값만 표시하는 읽기 전용이다(서버에 변경 호출이 없다).
class SnapshotReceiveModeSegments extends StatelessWidget {
  const SnapshotReceiveModeSegments({super.key, required this.mode});

  final SnapshotResponseMode mode;

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final items = <(SnapshotResponseMode, String)>[
      (SnapshotResponseMode.viewOnly, strings.receiveModeViewOnly),
      (SnapshotResponseMode.reactions, strings.receiveModeReactions),
      (SnapshotResponseMode.replies, strings.receiveModeReplies),
    ];
    final hint = switch (mode) {
      SnapshotResponseMode.viewOnly => strings.receiveModeViewOnlyHint,
      SnapshotResponseMode.reactions => strings.receiveModeReactionsHint,
      SnapshotResponseMode.replies => strings.receiveModeRepliesHint,
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          strings.receiveModeTitle,
          style: _style(context, 13, FontWeight.w600, Colors.black),
        ),
        const SizedBox(height: 8),
        Container(
          height: 36,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: Container(
                    key: ValueKey<String>('receive-mode-${item.$1.value}'),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: item.$1 == mode ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(
                        context,
                        13,
                        item.$1 == mode ? FontWeight.w700 : FontWeight.w500,
                        item.$1 == mode ? Colors.black : const Color(0xFF5F5F5F),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hint,
          style: _style(context, 12, FontWeight.w500, const Color(0xFF707070)),
        ),
      ],
    );
  }
}

class SnapshotActivitySheet extends StatefulWidget {
  const SnapshotActivitySheet({
    super.key,
    required this.snapshot,
    this.viewersStream,
  });

  final SnapshotItem snapshot;

  /// 테스트용. 없으면 `SnapshotService.watchViewers`.
  final Stream<List<SnapshotViewer>>? viewersStream;

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

class _SnapshotActivitySheetState extends State<SnapshotActivitySheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  late final Stream<List<SnapshotViewer>> _viewers =
      (widget.viewersStream ??
              SnapshotService.instance.watchViewers(widget.snapshot.id))
          .asBroadcastStream();
  final DMService _dm = DMService();
  final Set<String> _requesting = <String>{};

  @override
  void initState() {
    super.initState();
    // 이미 구독 중이면 아무 일도 하지 않는다(멱등).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        unawaited(context.read<RelationshipProvider>().ensureInitialized());
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
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

  Widget _empty(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: _style(context, 14, FontWeight.w500, const Color(0xFF707070)),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final height = MediaQuery.sizeOf(context).height;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
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
            final reacted =
                viewers.where((v) => v.reaction.isNotEmpty).toList();
            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD0D0D0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: TabBar(
                    controller: _tabs,
                    labelColor: Colors.black,
                    unselectedLabelColor: const Color(0xFF707070),
                    indicatorColor: Colors.black,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: const Color(0xFFEBEBEB),
                    labelStyle: _style(context, 14, FontWeight.w700, Colors.black),
                    unselectedLabelStyle:
                        _style(context, 14, FontWeight.w500, Colors.black),
                    tabs: [
                      Tab(text: strings.viewersTab(viewers.length)),
                      Tab(text: strings.reactionsTab(reacted.length)),
                      Tab(text: strings.repliesTabPlain),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _viewersTab(result, viewers, strings),
                      _reactionsTab(reacted, strings),
                      _repliesTab(strings),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Color(0xFFEBEBEB)),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: SnapshotReceiveModeSegments(
                    mode: widget.snapshot.responseMode,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _viewersTab(
    AsyncSnapshot<List<SnapshotViewer>> result,
    List<SnapshotViewer> viewers,
    SnapshotStrings strings,
  ) {
    if (result.hasError) return _empty(strings.viewersLoadFailed);
    if (!result.hasData) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (viewers.isEmpty) return _empty(strings.noViewers);
    final now = DateTime.now();
    return ListView.builder(
      itemCount: viewers.length,
      itemBuilder: (context, index) {
        final viewer = viewers[index];
        return Selector<RelationshipProvider, RelationshipStatus?>(
          selector: (_, provider) =>
              provider.feedRelationshipStatus(viewer.userId),
          builder: (context, status, _) => SnapshotActivityViewerRow(
            key: ValueKey<String>('viewer-${viewer.userId}'),
            viewer: viewer,
            status: status,
            now: now,
            onAddFriend: () => unawaited(_addFriend(viewer.userId)),
            onMessage: () => unawaited(_message(viewer.userId)),
          ),
        );
      },
    );
  }

  Widget _reactionsTab(List<SnapshotViewer> reacted, SnapshotStrings strings) {
    if (reacted.isEmpty) return _empty(strings.noReactionsYet);
    final grouped = <String, List<SnapshotViewer>>{};
    for (final viewer in reacted) {
      grouped.putIfAbsent(viewer.reaction, () => <SnapshotViewer>[]).add(viewer);
    }
    return ListView(
      children: [
        for (final entry in grouped.entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.key, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        strings.reactionPeople(entry.value.length),
                        style:
                            _style(context, 15, FontWeight.w600, Colors.black),
                      ),
                      Text(
                        entry.value
                            .map((v) => v.displayName.trim())
                            .where((n) => n.isNotEmpty)
                            .take(4)
                            .join(', '),
                        maxLines: 2,
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
              ],
            ),
          ),
      ],
    );
  }

  Widget _repliesTab(SnapshotStrings strings) {
    // 받은 답장은 알림으로만 열 수 있다(스낵별 목록을 읽는 경로가 없다).
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              strings.repliesInNotifications,
              textAlign: TextAlign.center,
              style: _style(context, 14, FontWeight.w500, Colors.black),
            ),
            const SizedBox(height: 6),
            Text(
              strings.repliesPrivateNote,
              textAlign: TextAlign.center,
              style: _style(
                context,
                12.5,
                FontWeight.w500,
                const Color(0xFF707070),
              ),
            ),
            const SizedBox(height: 14),
            TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
              ),
              child: Text(strings.openNotifications),
            ),
          ],
        ),
      ),
    );
  }
}
