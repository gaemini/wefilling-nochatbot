// lib/ui/widgets/chat_video_tile.dart
// 스낵챗·DM 영상 메시지 말풍선. 메시지에 실린 작은 JPEG 썸네일(data URL)과
// 길이를 보여주고, 탭하면 전체 화면 재생으로 넘긴다. 영상 자체는 재생 화면이
// 열릴 때 한 번만 내려받는다(피드와 달리 자동 재생하지 않아 비용을 아낀다).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

class ChatVideoTile extends StatelessWidget {
  const ChatVideoTile({
    super.key,
    required this.thumbnailDataUrl,
    this.thumbnailFile,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.onTap,
    this.statusText,
    this.progress,
    this.expired = false,
    this.failed = false,
    this.maxWidth = 240,
    this.maxHeight = 320,
  });

  final String? thumbnailDataUrl;

  /// 아직 업로드 전인 로컬 썸네일(작성 화면). data URL보다 우선한다.
  final File? thumbnailFile;
  final int durationMs;
  final int width;
  final int height;
  final VoidCallback? onTap;

  /// 업로드/다운로드 상태 문구. null이면 표시하지 않는다.
  final String? statusText;
  final double? progress;
  final bool expired;
  final bool failed;
  final double maxWidth;

  /// 세로 영상 타일의 최대 높이(대화방은 더 크게 넘긴다).
  final double maxHeight;

  static Uint8List? decodeThumbnail(String? dataUrl) {
    if (dataUrl == null || !dataUrl.startsWith('data:image/jpeg;base64,')) {
      return null;
    }
    try {
      return base64Decode(dataUrl.substring('data:image/jpeg;base64,'.length));
    } catch (_) {
      return null;
    }
  }

  static String formatDuration(int durationMs) {
    final total = (durationMs / 1000).round();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final seconds = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final bytes = decodeThumbnail(thumbnailDataUrl);
    final ratio = width > 0 && height > 0
        ? (width / height).clamp(0.6, 1.8).toDouble()
        : 16 / 9;
    final tileWidth = maxWidth;
    final tileHeight =
        (tileWidth / ratio).clamp(120.0, maxHeight).toDouble();
    final dimmed = expired || failed;
    return Semantics(
      button: onTap != null,
      label: 'video ${formatDuration(durationMs)}',
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: tileWidth,
            height: tileHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (thumbnailFile != null)
                  Image.file(
                    thumbnailFile!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) =>
                        const ColoredBox(color: Color(0xFF1F2937)),
                  )
                else if (bytes != null)
                  Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  )
                else
                  const ColoredBox(color: Color(0xFF1F2937)),
                if (dimmed)
                  const ColoredBox(color: Color(0x88000000))
                else
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0x66000000)],
                      ),
                    ),
                  ),
                Center(
                  child: progress != null && progress! > 0 && progress! < 1
                      ? SizedBox(
                          width: 44,
                          height: 44,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 3,
                            color: Colors.white,
                            backgroundColor: Colors.white24,
                          ),
                        )
                      : Icon(
                          failed
                              ? Icons.refresh_rounded
                              : expired
                                  ? Icons.timer_off_outlined
                                  : Icons.play_circle_fill_rounded,
                          color: Colors.white.withValues(alpha: 0.92),
                          size: 48,
                        ),
                ),
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xAA000000),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.videocam_rounded,
                              size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            formatDuration(durationMs),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (statusText != null && statusText!.isNotEmpty)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xAA000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Text(
                          statusText!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
