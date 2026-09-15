import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';
import '../../l10n/ui_locale.dart';

enum SnackChatAttachmentAction { image, file, poll }

Future<SnackChatAttachmentAction?> showSnackChatAttachmentSheet(
  BuildContext context, {
  bool showPoll = true,
}) {
  final isKorean = Localizations.localeOf(context).languageCode == 'ko';
  return showModalBottomSheet<SnackChatAttachmentAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    requestFocus: false,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => SnackChatAttachmentSheet(
      isKorean: isKorean,
      showPoll: showPoll,
    ),
  );
}

class SnackChatAttachmentSheet extends StatelessWidget {
  const SnackChatAttachmentSheet({
    super.key,
    required this.isKorean,
    this.showPoll = true,
  });

  final bool isKorean;
  final bool showPoll;

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final isCompact = screenSize.width < 360 || screenSize.height < 640;
    final horizontalPadding = screenSize.width < 360 ? 16.0 : 20.0;
    final navigationBarInset = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.padding.bottom,
    );
    final availableHeight = math.max(
      0.0,
      screenSize.height - mediaQuery.viewPadding.top - 8,
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: availableHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          0,
          horizontalPadding,
          navigationBarInset + (isCompact ? 8 : 12),
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: SingleChildScrollView(
            primary: false,
            padding: EdgeInsets.zero,
            child: Column(
              key: const ValueKey('snack_chat_attachment_safe_content'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: isCompact ? 10 : 12,
                    bottom: isCompact ? 8 : 10,
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 36,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xFFD0D5DD),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    2,
                    isCompact ? 2 : 4,
                    2,
                    isCompact ? 4 : 6,
                  ),
                  child: Text(
                    (isChineseUi(context)
                        ? '发送'
                        : isKorean
                            ? '보낼 항목'
                            : 'Send'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(17).clamp(16, 18).toDouble(),
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ),
                _AttachmentActionRow(
                  icon: Icons.image_outlined,
                  title: (isChineseUi(context)
                      ? '图片'
                      : isKorean
                          ? '이미지'
                          : 'Image'),
                  description: (isChineseUi(context)
                      ? '选择要发送到群聊的照片'
                      : isKorean
                          ? '사진을 선택해 대화에 보내기'
                          : 'Choose a photo to send in this chat'),
                  compact: isCompact,
                  onTap: () => Navigator.of(context).pop(
                    SnackChatAttachmentAction.image,
                  ),
                ),
                _AttachmentActionRow(
                  icon: Icons.attach_file_rounded,
                  title: (isChineseUi(context)
                      ? '文件'
                      : isKorean
                          ? '파일'
                          : 'File'),
                  description: (isChineseUi(context)
                      ? '选择要发送到群聊的文档'
                      : isKorean
                          ? '문서 파일을 선택해 대화에 보내기'
                          : 'Choose documents to send in this chat'),
                  compact: isCompact,
                  onTap: () => Navigator.of(context).pop(
                    SnackChatAttachmentAction.file,
                  ),
                ),
                if (showPoll)
                  _AttachmentActionRow(
                    icon: Icons.poll_outlined,
                    title: (isChineseUi(context)
                        ? '投票'
                        : isKorean
                            ? '투표'
                            : 'Poll'),
                    description: (isChineseUi(context)
                        ? '向群友提问并收集意见'
                        : isKorean
                            ? '대화 참여자에게 질문하고 의견 모으기'
                            : 'Ask the chat and collect responses'),
                    compact: isCompact,
                    onTap: () => Navigator.of(context).pop(
                      SnackChatAttachmentAction.poll,
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

class _AttachmentActionRow extends StatelessWidget {
  const _AttachmentActionRow({
    required this.icon,
    required this.title,
    required this.description,
    required this.compact,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: compact ? 64 : 70),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 2,
              vertical: compact ? 7 : 9,
            ),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: compact ? 38 : 42,
                  child: Center(
                    child: Icon(
                      icon,
                      size: context.ri(23).clamp(21, 25).toDouble(),
                      color: const Color(0xFF475467),
                    ),
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(15.5).clamp(14.5, 16).toDouble(),
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF111827),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: uiFontFamily(context, 'Inter'),
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(12.5).clamp(12, 13.5).toDouble(),
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: const Color(0xFF667085),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: context.ri(20).clamp(19, 22).toDouble(),
                  color: const Color(0xFF98A2B3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
