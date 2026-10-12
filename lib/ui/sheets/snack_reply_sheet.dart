// lib/ui/sheets/snack_reply_sheet.dart
// 스낵 답장 시트. 친구와 비친구에게 다른 문구와 행동을 보인다.
//
// - 친구: 3~5초 영상 촬영 / 사진 촬영 / 앨범 선택 → DM으로 바로 전달
// - 비친구: 스낵 답장은 친구끼리만 가능. 친구 요청으로 안내
// - 친구 요청 보냄: 수락 뒤 스낵 답장이 가능하다는 안내

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../l10n/relationship_strings.dart';
import '../../l10n/ui_locale.dart';
import '../../models/relationship_orbit_state.dart';
import '../../utils/logger.dart';
import '../snackbar/app_snackbar.dart';

enum SnackReplyAction {
  recordVideo,
  takePhoto,
  pickFromGallery,
  friendRequest,
}

/// 스낵 답장으로 보낼 미디어.
class SnackReplyMedia {
  const SnackReplyMedia({required this.file, required this.isVideo});

  final File file;
  final bool isVideo;
}

/// 스낵 답장 영상 길이 정책(3~5초). 녹화 종료 지연을 고려해 여유를 둔다.
class SnackReplyVideoPolicy {
  const SnackReplyVideoPolicy._();

  static const Duration minimum = Duration(seconds: 3);
  static const Duration maximum = Duration(seconds: 5);
  static const Duration tolerance = Duration(milliseconds: 600);

  /// null이면 통과, 아니면 실패 사유('short' | 'long').
  static String? validate(Duration duration) {
    if (duration + tolerance < minimum) return 'short';
    if (duration > maximum + tolerance) return 'long';
    return null;
  }
}

Future<SnackReplyAction?> showSnackReplySheet(
  BuildContext context, {
  required OrbitRelationshipState relationship,
  required bool friendRequestPending,
}) {
  return showModalBottomSheet<SnackReplyAction>(
    context: context,
    // 낮은 화면에서도 선택지가 잘리지 않도록 내용 높이만큼 열고 스크롤한다.
    isScrollControlled: true,
    backgroundColor: Colors.white,
    showDragHandle: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) {
      final strings = RelationshipStrings.of(sheetContext);
      final isFriend = relationship == OrbitRelationshipState.friend;
      final titleStyle = TextStyle(
        fontFamily: uiFontFamily(sheetContext, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF101828),
      );
      final bodyStyle = TextStyle(
        fontFamily: uiFontFamily(sheetContext, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: 14.5,
        color: const Color(0xFF475467),
        height: 1.4,
      );
      void pop(SnackReplyAction action) =>
          Navigator.of(sheetContext).pop(action);

      Widget option(IconData icon, String label, SnackReplyAction action) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minVerticalPadding: 10,
          leading: Icon(icon, color: const Color(0xFF344054)),
          title: Text(
            label,
            style: TextStyle(
              fontFamily: uiFontFamily(sheetContext, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF101828),
            ),
          ),
          onTap: () => pop(action),
        );
      }

      return SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(strings.snackReply, style: titleStyle),
            const SizedBox(height: 8),
            Text(
              isFriend
                  ? strings.snackReplyFriendBody
                  : friendRequestPending
                      ? strings.snackReplyPendingBody
                      : strings.snackReplyNonFriendBody,
              style: bodyStyle,
            ),
            const SizedBox(height: 10),
            if (isFriend) ...[
              option(Icons.videocam_outlined, strings.recordVideo,
                  SnackReplyAction.recordVideo),
              option(Icons.photo_camera_outlined, strings.takePhoto,
                  SnackReplyAction.takePhoto),
              option(Icons.photo_library_outlined, strings.pickFromGallery,
                  SnackReplyAction.pickFromGallery),
            ] else ...[
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: friendRequestPending
                    ? null
                    : () => pop(SnackReplyAction.friendRequest),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: Icon(friendRequestPending
                    ? Icons.schedule_rounded
                    : Icons.person_add_alt_1_outlined),
                label: Text(friendRequestPending
                    ? strings.friendRequestSentShort
                    : strings.sendFriendRequest),
              ),
            ],
          ],
        ),
        ),
      );
    },
  );
}

/// 선택한 행동에 맞게 카메라/앨범을 열고 3~5초 정책을 검사한다.
/// 실패 사유는 짧은 안내로 보이고 null을 돌려준다.
Future<SnackReplyMedia?> pickSnackReplyMedia(
  BuildContext context,
  SnackReplyAction action, {
  ImagePicker? picker,
}) async {
  final strings = RelationshipStrings.of(context);
  final imagePicker = picker ?? ImagePicker();
  XFile? picked;
  try {
    switch (action) {
      case SnackReplyAction.recordVideo:
        picked = await imagePicker.pickVideo(
          source: ImageSource.camera,
          maxDuration: SnackReplyVideoPolicy.maximum,
        );
      case SnackReplyAction.takePhoto:
        picked = await imagePicker.pickImage(
          source: ImageSource.camera,
          imageQuality: 88,
        );
      case SnackReplyAction.pickFromGallery:
        picked = await imagePicker.pickMedia(imageQuality: 88);
      case SnackReplyAction.friendRequest:
        return null;
    }
  } catch (error) {
    Logger.error('스낵 답장 미디어 선택 실패: $error');
    if (context.mounted) {
      AppSnackBar.show(
        context,
        message: action == SnackReplyAction.pickFromGallery
            ? strings.mediaFailed
            : strings.cameraUnavailable,
        type: AppSnackBarType.error,
      );
    }
    return null;
  }
  if (picked == null) return null;
  final file = File(picked.path);
  final isVideo = action == SnackReplyAction.recordVideo ||
      _looksLikeVideo(picked);
  if (!isVideo) return SnackReplyMedia(file: file, isVideo: false);

  final duration = await _videoDuration(file);
  if (!context.mounted) return null;
  if (duration == null) {
    AppSnackBar.show(context,
        message: strings.mediaFailed, type: AppSnackBarType.error);
    return null;
  }
  final problem = SnackReplyVideoPolicy.validate(duration);
  if (problem != null) {
    AppSnackBar.show(
      context,
      message: problem == 'short' ? strings.videoTooShort : strings.videoTooLong,
      type: AppSnackBarType.warning,
    );
    return null;
  }
  return SnackReplyMedia(file: file, isVideo: true);
}

bool _looksLikeVideo(XFile file) {
  final mime = (file.mimeType ?? '').toLowerCase();
  if (mime.startsWith('video/')) return true;
  if (mime.startsWith('image/')) return false;
  final name = (file.name.isNotEmpty ? file.name : file.path).toLowerCase();
  return const <String>['.mp4', '.mov', '.m4v', '.3gp', '.webm', '.avi']
      .any(name.endsWith);
}

Future<Duration?> _videoDuration(File file) async {
  final controller = VideoPlayerController.file(file);
  try {
    await controller.initialize().timeout(const Duration(seconds: 10));
    return controller.value.duration;
  } catch (error) {
    Logger.error('스낵 답장 영상 길이 확인 실패: $error');
    return null;
  } finally {
    await controller.dispose();
  }
}
