import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/snack_chat_file_policy.dart';
import '../../utils/responsive_helper.dart';

Future<List<SnackChatSelectedFile>?> showSnackChatFileConfirmationSheet(
  BuildContext context, {
  required List<SnackChatSelectedFile> files,
  required bool temporary24h,
}) {
  return showModalBottomSheet<List<SnackChatSelectedFile>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SnackChatFileConfirmationSheet(
      files: files,
      temporary24h: temporary24h,
    ),
  );
}

class _SnackChatFileConfirmationSheet extends StatefulWidget {
  const _SnackChatFileConfirmationSheet({
    required this.files,
    required this.temporary24h,
  });

  final List<SnackChatSelectedFile> files;
  final bool temporary24h;

  @override
  State<_SnackChatFileConfirmationSheet> createState() =>
      _SnackChatFileConfirmationSheetState();
}

class _SnackChatFileConfirmationSheetState
    extends State<_SnackChatFileConfirmationSheet> {
  late final List<SnackChatSelectedFile> _files = List.of(widget.files);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final compact = media.size.width < 360 || media.size.height < 640;
    final bottomInset = math.max(
      media.viewInsets.bottom,
      math.max(media.viewPadding.bottom, media.padding.bottom),
    );
    final maxHeight = media.size.height - media.viewPadding.top - 12;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.max(0, maxHeight)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 10, 20, bottomInset + 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD0D5DD),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            SizedBox(height: compact ? 14 : 18),
            Row(
              children: [
                Expanded(
                  child: Text(
                    isKorean ? '파일 보내기' : 'Send files',
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: context.rf(18).clamp(17, 20).toDouble(),
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                Text(
                  isKorean
                      ? '${_files.length}개 선택'
                      : '${_files.length} selected',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              widget.temporary24h
                  ? (isKorean
                      ? '이 파일은 전송 후 24시간 동안 확인할 수 있습니다.'
                      : 'These files remain available for 24 hours after sending.')
                  : (isKorean
                      ? '이 파일은 전송 후 30일 동안 확인할 수 있습니다.'
                      : 'These files remain available for 30 days after sending.'),
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 13,
                height: 1.4,
                color: Color(0xFF667085),
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: _files.length,
                itemBuilder: (context, index) {
                  final file = _files[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox.square(
                          dimension: 40,
                          child: Center(
                            child: Icon(
                              _iconFor(file.fileExtension),
                              size: 24,
                              color: const Color(0xFF475467),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                file.originalFileName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 1.25,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${file.fileExtension.toUpperCase()} · ${SnackChatFilePolicy.formatBytes(file.fileSize)}',
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 12,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: isKorean ? '제거' : 'Remove',
                          onPressed: () {
                            setState(() => _files.removeAt(index));
                            if (_files.isEmpty) Navigator.of(context).pop();
                          },
                          icon: const Icon(Icons.close_rounded),
                          color: const Color(0xFF667085),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: _files.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(List.of(_files)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF111827),
                  disabledBackgroundColor: const Color(0xFFE4E7EC),
                  shape: const StadiumBorder(),
                  elevation: 0,
                ),
                child: Text(
                  isKorean ? '전송' : 'Send',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String extension) {
    if (extension == 'pdf') return Icons.picture_as_pdf_outlined;
    if (<String>{'xls', 'xlsx', 'csv'}.contains(extension)) {
      return Icons.table_chart_outlined;
    }
    if (<String>{'ppt', 'pptx'}.contains(extension)) {
      return Icons.slideshow_outlined;
    }
    return Icons.description_outlined;
  }
}
