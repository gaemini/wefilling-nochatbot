import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../services/snapshot_archive_service.dart';
import '../snapshot/snapshot_storage_video.dart';
import '../snapshot/snapshot_strings.dart';
import '../ui/snackbar/app_snackbar.dart';

class SnapshotArchiveScreen extends StatefulWidget {
  const SnapshotArchiveScreen({super.key});

  @override
  State<SnapshotArchiveScreen> createState() => _SnapshotArchiveScreenState();
}

class _SnapshotArchiveScreenState extends State<SnapshotArchiveScreen> {
  final SnapshotArchiveService _service = SnapshotArchiveService.instance;
  late Future<List<SnapshotArchiveRecord>> _records;
  late Future<int> _storageBytes;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _records = _service.list();
    _storageBytes = _service.storageBytes();
  }

  Future<void> _delete(SnapshotArchiveRecord record) async {
    final strings = SnapshotStrings.of(context);
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(strings.deleteArchiveTitle),
            content: Text(strings.deleteArchiveBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(strings.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(strings.delete),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await _service.delete(record.snapshotId);
      if (!mounted) return;
      setState(_reload);
    } catch (_) {
      if (mounted) {
        AppSnackBar.show(
          context,
          message: strings.archiveDeleteFailed,
          type: AppSnackBarType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: Text(strings.archive),
      ),
      body: SafeArea(
        top: false,
        child: FutureBuilder<List<SnapshotArchiveRecord>>(
          future: _records,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Center(
                child: TextButton.icon(
                  onPressed: () => setState(_reload),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(strings.retry),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                  child: CircularProgressIndicator(strokeWidth: 2));
            }
            final records = snapshot.data!;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  strings.archiveDeviceNotice,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                FutureBuilder<int>(
                  future: _storageBytes,
                  builder: (context, size) => Text(
                    strings.archiveStorage(_formatBytes(size.data ?? 0)),
                    style: const TextStyle(
                      color: Color(0xFF344054),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (records.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 80),
                    child: Center(
                      child: Text(
                        strings.archiveEmpty,
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ),
                  )
                else
                  for (final record in records)
                    _ArchiveTile(
                      record: record,
                      onTap: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => SnapshotArchiveDetailScreen(
                            record: record,
                          ),
                        ),
                      ),
                      onDelete: () => _delete(record),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class SnapshotArchiveDetailScreen extends StatelessWidget {
  const SnapshotArchiveDetailScreen({super.key, required this.record});

  final SnapshotArchiveRecord record;

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final date = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .add_Hm()
        .format(record.createdAt.toLocal());
    final synced = DateFormat.yMMMd(Localizations.localeOf(context).toString())
        .add_Hm()
        .format(record.lastSyncedAt.toLocal());
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(strings.archiveReadOnly),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            AspectRatio(
              aspectRatio: record.aspectRatio.clamp(.4, 2.5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: ColoredBox(
                  color: Colors.black,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (record.isVideo)
                        _ArchiveVideo(file: File(record.mediaPath))
                      else
                        Image.file(File(record.mediaPath), fit: BoxFit.contain),
                      if (record.isVideo)
                        IgnorePointer(
                          child: SnapshotOverlayLayer(
                            overlays: record.overlays,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              date,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              strings.archiveSyncStatus(synced, record.isFinalSync),
              style: const TextStyle(
                color: Color(0xFFD0D5DD),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 18,
              runSpacing: 10,
              children: [
                _ArchiveMetric(
                  icon: Icons.chat_bubble_outline_rounded,
                  value: record.commentCount,
                  label: strings.comments,
                ),
                _ArchiveMetric(
                  icon: Icons.favorite_border_rounded,
                  value: record.reactionCount,
                  label: strings.likeReaction,
                ),
                _ArchiveMetric(
                  icon: Icons.visibility_outlined,
                  value: record.viewerCount,
                  label: strings.viewers,
                ),
              ],
            ),
            if (record.comments.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                strings.comments,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final comment in record.comments)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    comment.isReply ? 22 : 0,
                    7,
                    0,
                    7,
                  ),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(color: Colors.white, height: 1.35),
                      children: [
                        TextSpan(
                          text: '${comment.authorNickname}  ',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: comment.isDeleted
                              ? strings.deletedComment
                              : comment.content,
                          style: TextStyle(
                            color: comment.isDeleted
                                ? const Color(0xFF98A2B3)
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (record.viewers.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                strings.viewers,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              for (final viewer in record.viewers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF344054),
                    backgroundImage: viewer.photoUrl.isEmpty
                        ? null
                        : NetworkImage(viewer.photoUrl),
                    child: viewer.photoUrl.isEmpty
                        ? const Icon(Icons.person_outline_rounded,
                            color: Colors.white)
                        : null,
                  ),
                  title: Text(
                    viewer.displayName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  trailing: viewer.reaction.isEmpty
                      ? null
                      : Text(
                          viewer.reaction,
                          style: const TextStyle(fontSize: 20),
                        ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ArchiveTile extends StatelessWidget {
  const _ArchiveTile({
    required this.record,
    required this.onTap,
    required this.onDelete,
  });

  final SnapshotArchiveRecord record;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final preview = record.thumbnailPath.isNotEmpty
        ? record.thumbnailPath
        : record.mediaPath;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox.square(
          dimension: 54,
          child: Image.file(
            File(preview),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const ColoredBox(
              color: Color(0xFFF2F4F7),
              child: Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
      ),
      title:
          Text(DateFormat.yMMMd().add_Hm().format(record.createdAt.toLocal())),
      subtitle: Text(
        '${record.commentCount} · ${record.reactionCount} · ${record.viewerCount}',
      ),
      trailing: IconButton(
        onPressed: onDelete,
        tooltip: SnapshotStrings.of(context).delete,
        icon: const Icon(Icons.delete_outline_rounded),
      ),
    );
  }
}

class _ArchiveVideo extends StatefulWidget {
  const _ArchiveVideo({required this.file});

  final File file;

  @override
  State<_ArchiveVideo> createState() => _ArchiveVideoState();
}

class _ArchiveVideoState extends State<_ArchiveVideo> {
  late final VideoPlayerController _controller;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file);
    unawaited(
      _controller.initialize().timeout(const Duration(seconds: 30)).then((_) {
        if (!mounted) return;
        setState(() {});
      }).catchError((_) {
        if (mounted) setState(() => _failed = true);
      }),
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Text(
          SnapshotStrings.of(context).videoPlaybackFailed,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white),
        ),
      );
    }
    if (!_controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return GestureDetector(
      onTap: () {
        setState(() {
          if (_controller.value.isPlaying) {
            unawaited(_controller.pause());
          } else {
            unawaited(_controller.play());
          }
        });
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          VideoPlayer(_controller),
          if (!_controller.value.isPlaying)
            const Center(
              child: Icon(Icons.play_circle_fill_rounded,
                  size: 52, color: Colors.white),
            ),
        ],
      ),
    );
  }
}

class _ArchiveMetric extends StatelessWidget {
  const _ArchiveMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 21, color: Colors.white),
        const SizedBox(width: 6),
        Text(
          '$value $label',
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}
