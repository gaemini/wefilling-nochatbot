import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../utils/responsive_helper.dart';

Future<bool> showSnackChatImageConfirmationSheet(
  BuildContext context, {
  required File imageFile,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.white,
    barrierColor: Colors.black.withValues(alpha: 0.46),
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => _SnackChatImageConfirmationSheet(imageFile: imageFile),
  );
  return result ?? false;
}

class _SnackChatImageConfirmationSheet extends StatelessWidget {
  const _SnackChatImageConfirmationSheet({required this.imageFile});

  final File imageFile;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isKorean = Localizations.localeOf(context).languageCode == 'ko';
    final compact = media.size.width < 360 || media.size.height < 640;
    final horizontalPadding = media.size.width < 360 ? 16.0 : 20.0;
    final bottomInset = math.max(
      media.viewInsets.bottom,
      math.max(media.viewPadding.bottom, media.padding.bottom),
    );
    final maxSheetHeight = math.max(
      0.0,
      media.size.height - media.viewPadding.top - 12,
    );
    final previewHeight = math.min(
      media.size.width * (compact ? 0.52 : 0.64),
      media.size.height * (compact ? 0.30 : 0.38),
    );

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          10,
          horizontalPadding,
          bottomInset + (compact ? 8 : 12),
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
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
              Text(
                isKorean ? '이 사진을 보낼까요?' : 'Send this photo?',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(18).clamp(17, 20).toDouble(),
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                isKorean
                    ? '전송하기 전에 선택한 사진을 확인해 주세요.'
                    : 'Check the selected photo before sending.',
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF667085),
                  height: 1.4,
                ),
              ),
              SizedBox(height: compact ? 12 : 16),
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: previewHeight),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.file(
                      imageFile,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.broken_image_outlined,
                                size: 28,
                                color: Color(0xFF98A2B3),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isKorean
                                    ? '사진을 미리 볼 수 없습니다.'
                                    : 'Preview unavailable.',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: ['NotoSansKR'],
                                  fontSize: 13,
                                  color: Color(0xFF667085),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: compact ? 12 : 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: compact ? 44 : 48,
                      child: TextButton(
                        key: const ValueKey(
                          'snack_chat_image_confirmation_cancel',
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF667085),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          isKorean ? '취소' : 'Cancel',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: ['NotoSansKR'],
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: compact ? 44 : 48,
                      child: FilledButton(
                        key: const ValueKey(
                          'snack_chat_image_confirmation_send',
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.pointColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          isKorean ? '보내기' : 'Send',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontFamilyFallback: ['NotoSansKR'],
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
