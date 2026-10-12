// lib/ui/widgets/video_preparing_dialog.dart
// 영상 압축·썸네일 생성 동안 보여주는 작은 진행 다이얼로그와, 한도 초과 시
// 사용자에게 보여줄 문구. 스낵챗·DM·포스트가 함께 쓴다.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/ui_locale.dart';
import '../../services/media/video_prepare_service.dart';
import '../../services/media/video_upload_policy.dart';

/// [task]가 끝날 때까지 닫을 수 없는 진행 다이얼로그를 띄운다.
Future<T> runWithVideoPreparingDialog<T>(
  BuildContext context,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final isKo = Localizations.localeOf(context).languageCode == 'ko';
  final label = isChineseUi(context)
      ? '正在准备视频…'
      : isKo
          ? '영상을 준비하고 있어요…'
          : 'Preparing video…';
  var dialogOpen = true;
  unawaited(
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF344054),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ValueListenableBuilder<double?>(
                    valueListenable: VideoPrepareService.instance.progress,
                    builder: (context, value, _) {
                      final percent = value == null
                          ? null
                          : (value * 100).clamp(0, 100).round();
                      return Text(
                        percent == null ? label : '$label $percent%',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF111827),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).whenComplete(() => dialogOpen = false),
  );
  try {
    return await task();
  } finally {
    if (dialogOpen && navigator.mounted) navigator.pop();
  }
}

/// 거부 사유를 현재 언어 문구로 바꾼다.
String videoRejectionMessage(
  BuildContext context,
  VideoRejection rejection,
  VideoUploadLimits limits,
) {
  final isKo = Localizations.localeOf(context).languageCode == 'ko';
  final zh = isChineseUi(context);
  final seconds = limits.maxDurationSeconds;
  final mb = limits.maxUploadMegabytes;
  switch (rejection) {
    case VideoRejection.tooLong:
      return zh
          ? '视频最长 $seconds 秒'
          : isKo
              ? '영상은 최대 $seconds초까지 올릴 수 있어요'
              : 'Videos can be up to $seconds seconds long';
    case VideoRejection.tooLarge:
      return zh
          ? '压缩后仍超过 ${mb}MB，请选择更短的视频'
          : isKo
              ? '압축해도 ${mb}MB를 넘어요. 더 짧은 영상을 선택해 주세요'
              : 'Still over ${mb}MB after compression. Try a shorter video';
    case VideoRejection.sourceTooLarge:
      return zh
          ? '原始文件过大，无法处理'
          : isKo
              ? '원본 파일이 너무 커서 처리할 수 없어요'
              : 'The original file is too large to process';
    case VideoRejection.empty:
    case VideoRejection.unreadable:
      return zh
          ? '无法读取该视频'
          : isKo
              ? '영상을 읽을 수 없어요'
              : 'Could not read this video';
  }
}

String videoPrepareErrorMessage(
  BuildContext context,
  Object error,
  VideoUploadLimits limits,
) {
  if (error is VideoPrepareException) {
    return videoRejectionMessage(context, error.rejection, limits);
  }
  final isKo = Localizations.localeOf(context).languageCode == 'ko';
  return isChineseUi(context)
      ? '无法准备视频'
      : isKo
          ? '영상을 준비하지 못했어요'
          : 'Could not prepare the video';
}
