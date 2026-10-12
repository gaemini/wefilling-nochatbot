// lib/screens/first_response_requests_screen.dart
// 비친구가 번역으로 보낸 첫 응답 요청 인박스. DM 목록의 '요청' 탭 본문으로
// 쓰이며, 기존 익명 탭을 복제하지 않는 독립 상태/화면이다.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/relationship_strings.dart';
import '../l10n/ui_locale.dart';
import '../models/first_response_request.dart';
import '../models/snapshot.dart';
import '../services/first_response_request_service.dart';
import '../services/snapshot_service.dart';
import '../snapshot/snapshot_storage_image.dart';
import '../ui/dialogs/block_dialog.dart';
import '../ui/snackbar/app_snackbar.dart';
import '../ui/widgets/motion_press.dart';
import '../ui/widgets/user_avatar.dart';
import '../utils/responsive_helper.dart';
import '../utils/time_formatter.dart';
import 'dm_chat_screen.dart';

/// 독립 화면으로 열 때 사용한다.
class FirstResponseRequestsScreen extends StatelessWidget {
  const FirstResponseRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final strings = RelationshipStrings.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Text(strings.requestsTab),
      ),
      body: const FirstResponseInboxView(),
    );
  }
}

/// DM 목록 안에 끼워 넣는 인박스 본문.
class FirstResponseInboxView extends StatefulWidget {
  const FirstResponseInboxView({super.key, this.bottomPadding = 88});

  final double bottomPadding;

  @override
  State<FirstResponseInboxView> createState() => _FirstResponseInboxViewState();
}

class _FirstResponseInboxViewState extends State<FirstResponseInboxView> {
  late final Stream<List<FirstResponseRequest>> _stream;
  final Set<String> _busyIds = <String>{};

  @override
  void initState() {
    super.initState();
    FirstResponseRequestService.instance.ensureStarted();
    _stream = FirstResponseRequestService.instance.watchIncomingPending();
  }

  Future<void> _accept(FirstResponseRequest request) async {
    if (_busyIds.contains(request.id)) return;
    setState(() => _busyIds.add(request.id));
    final strings = RelationshipStrings.of(context);
    final conversationId =
        await FirstResponseRequestService.instance.accept(request);
    if (!mounted) return;
    setState(() => _busyIds.remove(request.id));
    if (conversationId == null) {
      AppSnackBar.show(context,
          message: strings.actionFailed, type: AppSnackBarType.error);
      return;
    }
    AppSnackBar.show(context,
        message: strings.accepted, type: AppSnackBarType.success);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => DMChatScreen(
          conversationId: conversationId,
          otherUserId: request.senderId,
        ),
      ),
    );
  }

  Future<void> _decline(FirstResponseRequest request) async {
    if (_busyIds.contains(request.id)) return;
    setState(() => _busyIds.add(request.id));
    final strings = RelationshipStrings.of(context);
    final ok = await FirstResponseRequestService.instance.decline(request);
    if (!mounted) return;
    setState(() => _busyIds.remove(request.id));
    AppSnackBar.show(
      context,
      message: ok ? strings.declined : strings.actionFailed,
      type: ok ? AppSnackBarType.info : AppSnackBarType.error,
    );
  }

  Future<void> _block(FirstResponseRequest request) async {
    if (_busyIds.contains(request.id)) return;
    final result = await showBlockUserDialog(
      context,
      userId: request.senderId,
      userName: request.senderName.isEmpty ? 'User' : request.senderName,
    );
    if (result == null || !mounted) return;
    setState(() => _busyIds.add(request.id));
    await FirstResponseRequestService.instance.markBlocked(request);
    if (mounted) setState(() => _busyIds.remove(request.id));
  }

  @override
  Widget build(BuildContext context) {
    final strings = RelationshipStrings.of(context);
    return StreamBuilder<List<FirstResponseRequest>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _InboxMessage(
            icon: Icons.error_outline_rounded,
            title: strings.requestsLoadFailed,
            body: '',
          );
        }
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2.2),
              ),
            ),
          );
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return _InboxMessage(
            icon: Icons.translate_rounded,
            title: strings.requestsEmptyTitle,
            body: strings.requestsEmptyBody,
          );
        }
        return ListView.separated(
          padding: EdgeInsets.fromLTRB(16, 12, 16, widget.bottomPadding),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final request = items[index];
            return _RequestCard(
              key: ValueKey<String>('first-response-${request.id}'),
              request: request,
              busy: _busyIds.contains(request.id),
              onAccept: () => _accept(request),
              onDecline: () => _decline(request),
              onBlock: () => _block(request),
            );
          },
        );
      },
    );
  }
}

class _RequestCard extends StatefulWidget {
  const _RequestCard({
    super.key,
    required this.request,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onBlock,
  });

  final FirstResponseRequest request;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onBlock;

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _showOriginal = false;

  @override
  Widget build(BuildContext context) {
    final strings = RelationshipStrings.of(context);
    final request = widget.request;
    final hasTranslation = request.hasTranslation;
    // 번역문이 있으면 번역문이 본문이다. 원문보다 작게 만들지 않는다.
    final mainText = hasTranslation && !_showOriginal
        ? request.translatedMessage
        : request.message;
    final nameStyle = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: context.rf(15).clamp(14, 16).toDouble(),
      fontWeight: FontWeight.w700,
      color: const Color(0xFF101828),
    );
    final metaStyle = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
      fontWeight: FontWeight.w500,
      color: const Color(0xFF667085),
    );
    final bodyStyle = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: context.rf(15).clamp(14, 16).toDouble(),
      fontWeight: FontWeight.w500,
      color: const Color(0xFF101828),
      height: isChineseUi(context) ? 1.45 : 1.35,
    );
    final createdAt = request.createdAt;
    final sourceLabel = request.sourceType == FirstResponseSourceType.post
        ? strings.fromPost
        : strings.fromSnack;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAECF0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              UserAvatar(
                uid: request.senderId,
                photoUrl: request.senderPhotoUrl,
                photoVersion: request.senderPhotoVersion,
                isAnonymous: false,
                size: 44,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      request.senderName.isEmpty ? 'User' : request.senderName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nameStyle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      createdAt == null
                          ? sourceLabel
                          : '$sourceLabel · ${TimeFormatter.formatConversationTime(context, createdAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _RequestSource(request: request),
          const SizedBox(height: 12),
          Text(mainText, style: bodyStyle),
          if (hasTranslation)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _showOriginal = !_showOriginal),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: const Size(44, 36),
                ),
                child: Text(
                  _showOriginal ? strings.showTranslation : strings.showOriginal,
                  style: metaStyle.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          const SizedBox(height: 6),
          Row(
            children: [
              TextButton(
                onPressed: widget.busy ? null : widget.onBlock,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF667085),
                  minimumSize: const Size(64, 44),
                ),
                child: Text(strings.block),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: widget.busy ? null : widget.onDecline,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(76, 44),
                  foregroundColor: const Color(0xFF344054),
                  side: const BorderSide(color: Color(0xFFD0D5DD)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(strings.decline),
              ),
              const SizedBox(width: 8),
              MotionPress(
                enabled: !widget.busy,
                child: FilledButton(
                  onPressed: widget.busy ? null : widget.onAccept,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(84, 44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: widget.busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(strings.accept),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RequestSource extends StatelessWidget {
  const _RequestSource({required this.request});

  final FirstResponseRequest request;

  @override
  Widget build(BuildContext context) {
    final preview = request.sourcePreview.trim();
    Widget thumbnail;
    if (request.sourceType == FirstResponseSourceType.snapshot) {
      thumbnail = _SnackThumbnail(snapshotId: request.sourceId);
    } else if (request.sourceImageUrl.trim().isNotEmpty) {
      thumbnail = CachedNetworkImage(
        imageUrl: request.sourceImageUrl,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => const ColoredBox(color: Color(0xFFE4E7EC)),
      );
    } else {
      thumbnail = const ColoredBox(
        color: Color(0xFFE4E7EC),
        child: Icon(Icons.notes_rounded, color: Color(0xFF98A2B3), size: 20),
      );
    }
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 44, height: 56, child: thumbnail),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            preview.isEmpty ? '…' : preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF475467),
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _SnackThumbnail extends StatefulWidget {
  const _SnackThumbnail({required this.snapshotId});

  final String snapshotId;

  @override
  State<_SnackThumbnail> createState() => _SnackThumbnailState();
}

class _SnackThumbnailState extends State<_SnackThumbnail> {
  late Future<SnapshotItem?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<SnapshotItem?> _load() async {
    try {
      return await SnapshotService.instance.getSnapshot(widget.snapshotId);
    } catch (_) {
      // 만료되었거나 접근할 수 없는 스낵은 자리 표시만 남긴다.
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SnapshotItem?>(
      future: _future,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) {
          return const ColoredBox(
            color: Color(0xFFE4E7EC),
            child: Icon(Icons.timelapse_rounded,
                color: Color(0xFF98A2B3), size: 20),
          );
        }
        return SnapshotStorageImage(snapshot: item, decodeWidth: 160);
      },
    );
  }
}

class _InboxMessage extends StatelessWidget {
  const _InboxMessage({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: const Color(0xFF98A2B3)),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF344054),
              ),
            ),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                body,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: uiFontFamily(context, 'Inter'),
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: 13.5,
                  color: const Color(0xFF667085),
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
