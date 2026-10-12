import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import '../config/app_backend.dart';
import 'package:path/path.dart' as path;
import '../utils/logger.dart';
import 'media/video_upload_policy.dart';
import 'media/video_prepare_service.dart';
import 'snack_chat_media_cache_service.dart';

/// 프로필 이미지 업로드 결과
/// - downloadUrl: 액세스 토큰 포함 URL
/// - path: Storage object path (profile_images/{uid}/{file}.jpg)
typedef ProfileUploadResult = ({String downloadUrl, String path});
typedef SnackChatImageUploadResult = ({
  String storagePath,
  String storageBucket,
  String? imageUrl,
  int? imageWidth,
  int? imageHeight,
});
typedef DmFileUploadResult = ({String storagePath, String storageBucket});

/// A chat image that is already compressed and measured, so the upload step
/// only has to push bytes. Built with [StorageService.prepareChatImage] while
/// the user is still looking at the confirmation sheet.
class PreparedChatImage {
  const PreparedChatImage({
    required this.bytes,
    required this.sourcePath,
    this.tempPath,
    this.width,
    this.height,
  });

  /// Final JPEG bytes to upload.
  final Uint8List bytes;
  /// Path the user picked (kept for retries / local preview).
  final String sourcePath;
  /// Compressed temp file to delete after use, if compression produced one.
  final String? tempPath;
  final int? width;
  final int? height;

  Future<void> dispose() async {
    final temp = tempPath;
    if (temp == null || temp == sourcePath) return;
    try {
      await File(temp).delete();
    } catch (_) {}
  }
}
typedef _ChatImageUploadResult = ({
  String storagePath,
  String? downloadUrl,
  int? imageWidth,
  int? imageHeight,
});

class StorageService {
  // 모든 신규 업로드는 설정된 업로드 버킷(AppStorage.uploads)으로 간다.
  // 기존 객체는 문서에 기록된 storageBucket으로 열고, 없으면 레거시 버킷이다.
  // - 버킷은 "버킷 이름"으로 지정한다. (gs:// prefix 불필요)
  // - iOS에서 gs:// prefix 사용 시 resumable 업로드가 불안정한 케이스가 있어 통일한다.
  FirebaseStorage get _uploads => AppStorage.uploads;
  final Uuid _uuid = const Uuid();
  final Map<String, UploadTask> _dmFileUploads = <String, UploadTask>{};

  String _sanitizedStorageTarget(String storagePath) {
    final normalized = storagePath.split('?').first.trim();
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    if (segments.isEmpty) return 'unknown';
    final root = segments.first.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
    final extension = path.extension(segments.last).toLowerCase();
    return segments.length == 1
        ? '$root/*$extension'
        : '$root/<redacted>/*$extension (${segments.length} segments)';
  }

  void _logStorageFailure({
    required String operation,
    required String storagePath,
    required Object error,
    required StackTrace stackTrace,
    String? expectedOwnerUid,
  }) {
    final authUid = FirebaseAuth.instance.currentUser?.uid;
    final code =
        error is FirebaseException ? error.code : error.runtimeType.toString();
    final accessState = authUid == null
        ? 'signed-out'
        : expectedOwnerUid == null
            ? 'signed-in'
            : authUid == expectedOwnerUid
                ? 'owner-match'
                : 'owner-mismatch';
    Logger.error(
      'Firebase Storage 작업 실패 '
      '(operation=$operation, target=${_sanitizedStorageTarget(storagePath)}, '
      'access=$accessState, code=$code)',
      error,
      stackTrace,
    );
  }

  // 이미지 파일을 Firebase Storage에 업로드하고 다운로드 URL을 반환
  /// 게시글 영상과 썸네일을 post_videos/{uid}/{postId}/ 아래에 올린다.
  /// 길이·크기 검증과 다운로드 URL 발급은 createPostSecure가 한다. 게시글
  /// 생성이 실패하면 [deletePostVideo]로 업로더가 직접 지울 수 있다(문서가
  /// 없을 때만 규칙이 허용).
  Future<PostVideoUpload> uploadPostVideo(
    PreparedVideo prepared, {
    required String ownerUid,
    required String postId,
    void Function(double progress)? onProgress,
  }) async {
    final folder = 'post_videos/$ownerUid/$postId';
    final videoRef = _uploads.ref().child('$folder/video.mp4');
    final thumbnailRef = _uploads.ref().child('$folder/thumbnail.jpg');
    final metadata = <String, String>{'ownerUid': ownerUid, 'postId': postId};
    final videoTask = videoRef.putFile(
      prepared.file,
      SettableMetadata(
        contentType: VideoUploadPolicy.contentType,
        cacheControl: 'public,max-age=31536000,immutable',
        customMetadata: metadata,
      ),
    );
    if (onProgress != null) {
      videoTask.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }
      }, onError: (_) {});
    }
    await videoTask.timeout(const Duration(minutes: 6));
    await thumbnailRef
        .putFile(
          prepared.thumbnail,
          SettableMetadata(
            contentType: VideoUploadPolicy.thumbnailContentType,
            cacheControl: 'public,max-age=31536000,immutable',
            customMetadata: metadata,
          ),
        )
        .timeout(const Duration(seconds: 90));
    return PostVideoUpload(
      storagePath: videoRef.fullPath,
      thumbnailPath: thumbnailRef.fullPath,
      storageBucket: AppStorage.uploadBucketName,
    );
  }

  /// 생성 실패 롤백. 게시글 문서가 없을 때만 규칙이 허용한다.
  Future<void> deletePostVideo(PostVideoUpload upload) async {
    for (final path in [upload.storagePath, upload.thumbnailPath]) {
      try {
        await AppStorage.ref(path, storageBucket: upload.storageBucket)
            .delete()
            .timeout(const Duration(seconds: 15));
      } catch (error) {
        if (Logger.isVerboseEnabled) Logger.warning('포스트 영상 롤백 삭제 실패: $error');
      }
    }
  }

  Future<String?> uploadImage(
    File imageFile, {
    bool forceJpeg = false,
  }) async {
    String storagePath = 'posts/<pending>';
    try {
      // 이미지 압축
      final compressedFile = await _compressImage(
        imageFile,
        forceJpeg: forceJpeg,
      );
      if (compressedFile == null) {
        Logger.error('이미지 압축 실패');
        return null;
      }

      // 고유한 파일 이름 생성
      final String fileName = '${_uuid.v4()}.jpg';
      const String folderPath = 'posts';
      final String fullPath = '$folderPath/$fileName';
      storagePath = fullPath;

      if (Logger.isVerboseEnabled) Logger.log('이미지 업로드 시작: $fullPath');
      if (Logger.isVerboseEnabled)
        Logger.log('Firebase Storage 버킷: ${_uploads.bucket}');

      // 이미지 파일 경로 설정 (posts 폴더 아래에 저장)
      final Reference ref = _uploads.ref().child(folderPath).child(fileName);

      // 이미지 파일 업로드 및 진행 상태 모니터링
      final UploadTask uploadTask = ref.putFile(
        compressedFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          // 게시글 이미지는 UUID 경로에 한 번 업로드된 뒤 덮어쓰지 않는다.
          // Firebase 기본 7일 유효기간에 의존하면 파일이 디스크에 있어도
          // 주기적으로 재검증되므로 immutable 캐시 정책을 명시한다.
          // 공개 범위가 제한된 포스트도 있으므로 shared proxy/CDN 캐시는
          // 허용하지 않고 사용자 기기의 private cache만 장기 재사용한다.
          cacheControl: 'private,max-age=31536000,immutable',
          customMetadata: {
            'fileName': fileName,
            'uploaded': DateTime.now().toString(),
          },
        ),
      );

      // 타임아웃 처리 개선 - 타임아웃 시 업로드 작업 취소
      TaskSnapshot taskSnapshot;
      try {
        taskSnapshot = await uploadTask.timeout(
          const Duration(seconds: 180),
          onTimeout: () {
            // 타임아웃 발생 시 업로드 작업 취소
            uploadTask.cancel();
            throw TimeoutException(
                '이미지 업로드 타임아웃', const Duration(seconds: 180));
          },
        );
        if (Logger.isVerboseEnabled) Logger.log('업로드 완료: $fullPath');
      } on TimeoutException catch (e) {
        Logger.error('업로드 타임아웃', e);
        return null;
      }

      // 이미지 URL 반환 - Firebase가 자동으로 생성하는 다운로드 URL 사용
      final String downloadUrl = await taskSnapshot.ref.getDownloadURL();
      if (Logger.isVerboseEnabled) Logger.log('다운로드 URL 획득 완료');

      // 임시 파일 삭제
      if (compressedFile.path != imageFile.path) {
        try {
          await compressedFile.delete();
        } catch (e) {
          Logger.error('임시 파일 삭제 실패: $e');
        }
      }

      return downloadUrl;
    } catch (e, stackTrace) {
      _logStorageFailure(
        operation: 'upload-post-image',
        storagePath: storagePath,
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  /// 프로필 이미지 파일을 Firebase Storage에 업로드하고 다운로드 URL(+경로)을 반환
  /// - 경로: profile_images/{userId}/{uuid}.jpg (변경 이력 보존)
  /// - 파일은 항상 지정 버킷에만 존재하도록 강제
  /// - 매 업로드마다 download token을 새로 발급(=downloadUrl 토큰이 바뀜)
  Future<ProfileUploadResult?> uploadProfileImage(
    File imageFile, {
    required String userId,
  }) async {
    File? compressedFile;
    Reference? ref;
    String? fullPath;

    try {
      compressedFile = await _compressImage(imageFile, forceJpeg: true);
      if (compressedFile == null) {
        Logger.error('프로필 이미지 압축 실패');
        return null;
      }

      final String fileName = '${_uuid.v4()}.jpg';
      final String folderPath = 'profile_images/$userId';
      fullPath = '$folderPath/$fileName';

      if (Logger.isVerboseEnabled) Logger.log('프로필 이미지 업로드 시작: $fullPath');
      if (Logger.isVerboseEnabled)
        Logger.log('Firebase Storage 버킷(프로필): ${_uploads.bucket}');

      ref = _uploads.ref().child(folderPath).child(fileName);

      final UploadTask uploadTask = ref.putFile(
        compressedFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'fileName': fileName,
            'uploaded': DateTime.now().toString(),
          },
        ),
      );

      final TaskSnapshot taskSnapshot = await uploadTask.timeout(
        const Duration(seconds: 180),
        onTimeout: () {
          uploadTask.cancel();
          throw TimeoutException(
              '프로필 이미지 업로드 타임아웃', const Duration(seconds: 180));
        },
      );

      if (Logger.isVerboseEnabled) Logger.log('프로필 이미지 업로드 완료: $fullPath');

      final String downloadUrl = await taskSnapshot.ref.getDownloadURL();
      if (Logger.isVerboseEnabled) Logger.log('프로필 이미지 다운로드 URL 획득 완료');
      return (downloadUrl: downloadUrl, path: fullPath);
    } on TimeoutException catch (e) {
      Logger.error('프로필 이미지 업로드 타임아웃', e);
      return null;
    } catch (e, stackTrace) {
      _logStorageFailure(
        operation: 'upload-profile-image',
        storagePath: fullPath ?? 'profile_images/<pending>',
        error: e,
        stackTrace: stackTrace,
        expectedOwnerUid: userId,
      );
      String message = '';
      if (e is FirebaseException) {
        message = (e.message ?? '');
      }

      // ✅ iOS 간헐 이슈 방어:
      // - 업로드가 서버에서 이미 finalize 된 후, SDK 내부 cancelFetcher가 뒤늦게 실행되며
      //   HTTP 400이 발생할 수 있음. (finalized 문구가 SDK 에러 메시지에 포함되지 않는 경우도 있음)
      // - 이 경우 객체는 실제로 업로드되어 있을 가능성이 있으므로 download URL 복구를 재시도한다.
      final isHttp400 = message.contains('HTTPStatus error 400') ||
          message.contains('Code=400');
      if (isHttp400 && ref != null && fullPath != null) {
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            // 짧은 지연 후 재시도 (resumable finalize/메타데이터 반영 경합 완화)
            await Future.delayed(Duration(milliseconds: 220 * (attempt + 1)));
            final recovered = await ref.getDownloadURL();
            if (Logger.isVerboseEnabled)
              Logger.log(
                  '✅ HTTP 400 복구 성공: downloadURL 획득 ($fullPath, attempt=${attempt + 1})');
            return (downloadUrl: recovered, path: fullPath);
          } catch (recoveryError) {
            Logger.error(
                '⚠️ HTTP 400 복구 재시도 실패(attempt=${attempt + 1}): $recoveryError');
          }
        }
      }

      return null;
    } finally {
      // 임시 파일 삭제 (best-effort)
      if (compressedFile != null && compressedFile.path != imageFile.path) {
        try {
          await compressedFile.delete();
        } catch (e) {
          Logger.error('프로필 임시 파일 삭제 실패: $e');
        }
      }
    }
  }

  /// DM 이미지 파일을 Firebase Storage에 업로드하고 다운로드 URL을 반환
  /// - 경로: dm_images/{userId}/{conversationId}/{uuid}.jpg
  Future<String?> uploadDmImage(
    File imageFile, {
    required String userId,
    required String conversationId,
    void Function(double progress)? onProgress, // 0.0 ~ 1.0
    PreparedChatImage? prepared,
  }) async {
    final result = await _uploadChatImage(
      imageFile,
      userId: userId,
      entityId: conversationId,
      folderName: 'dm_images',
      entityMetadataKey: 'conversationId',
      logLabel: 'DM',
      onProgress: onProgress,
      createDownloadUrl: true,
      prepared: prepared,
    );
    return result?.downloadUrl;
  }

  /// Uploads one immutable DM document using a deterministic message path.
  /// A retry first verifies an existing object, so a lost acknowledgement does
  /// not create a duplicate or overwrite bytes that were already delivered.
  Future<DmFileUploadResult?> uploadDmFile(
    File file, {
    required String userId,
    required String conversationId,
    required String messageId,
    required String fileName,
    required String fileExtension,
    required String mimeType,
    required int fileSize,
    void Function(double progress)? onProgress,
  }) async {
    final normalizedExtension = fileExtension.toLowerCase().trim();
    final storagePath =
        'dm_files/$userId/$conversationId/$messageId/file.$normalizedExtension';
    final storageBucket = AppStorage.uploadBucketName;
    final reference = _uploads.ref(storagePath);

    bool isExpected(FullMetadata metadata) {
      final custom = metadata.customMetadata ?? const <String, String>{};
      return metadata.size == fileSize &&
          metadata.contentType == mimeType &&
          custom['ownerUid'] == userId &&
          custom['conversationId'] == conversationId &&
          custom['messageId'] == messageId &&
          custom['fileName'] == fileName &&
          custom['fileExtension'] == normalizedExtension;
    }

    Future<DmFileUploadResult?> recoverExisting() async {
      try {
        final metadata = await reference.getMetadata();
        return isExpected(metadata)
            ? (storagePath: storagePath, storageBucket: storageBucket)
            : null;
      } on FirebaseException catch (error) {
        if (error.code == 'object-not-found') return null;
        rethrow;
      }
    }

    try {
      final existing = await recoverExisting();
      if (existing != null) {
        onProgress?.call(1);
        return existing;
      }

      final upload = reference.putFile(
        file,
        SettableMetadata(
          contentType: mimeType,
          cacheControl: 'private,max-age=31536000,immutable',
          customMetadata: <String, String>{
            'ownerUid': userId,
            'conversationId': conversationId,
            'messageId': messageId,
            'fileName': fileName,
            'fileExtension': normalizedExtension,
            'fileSize': fileSize.toString(),
          },
        ),
      );
      _dmFileUploads[storagePath] = upload;
      final subscription = upload.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes <= 0) return;
        onProgress?.call(
          (snapshot.bytesTransferred / snapshot.totalBytes).clamp(0.0, 1.0),
        );
      });
      try {
        await upload.timeout(
          const Duration(minutes: 3),
          onTimeout: () {
            upload.cancel();
            throw TimeoutException(
              'DM file upload timeout',
              const Duration(minutes: 3),
            );
          },
        );
      } finally {
        if (identical(_dmFileUploads[storagePath], upload)) {
          _dmFileUploads.remove(storagePath);
        }
        await subscription.cancel();
      }
      onProgress?.call(1);
      return (storagePath: storagePath, storageBucket: storageBucket);
    } catch (error, stackTrace) {
      // The upload may have committed before a timeout/disconnect. Confirm the
      // immutable object before reporting failure and keep the local outbox.
      try {
        final recovered = await recoverExisting();
        if (recovered != null) return recovered;
      } catch (_) {}
      _logStorageFailure(
        operation: 'upload-dm-file',
        storagePath: storagePath,
        error: error,
        stackTrace: stackTrace,
        expectedOwnerUid: userId,
      );
      return null;
    }
  }

  /// Cancels only the current in-process upload. A finalized Storage object is
  /// never deleted here because a delayed message commit may already refer to
  /// it. The caller keeps/removes its own outbox packet separately.
  Future<bool> cancelDmFileUpload({
    required String userId,
    required String conversationId,
    required String messageId,
    required String fileExtension,
  }) async {
    final extension = fileExtension.toLowerCase().trim();
    final storagePath =
        'dm_files/$userId/$conversationId/$messageId/file.$extension';
    final upload = _dmFileUploads[storagePath];
    if (upload == null) return false;
    return upload.cancel();
  }

  /// Returns an account-scoped local copy and only downloads when necessary.
  Future<File> downloadDmFile({
    required String ownerUid,
    required String conversationId,
    required String messageId,
    required String storagePath,
    String? storageBucket,
    required String fileName,
    required int fileSize,
    void Function(double progress)? onProgress,
  }) async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}/dm_file_cache/${Uri.encodeComponent(ownerUid)}/'
      '${Uri.encodeComponent(conversationId)}',
    );
    await directory.create(recursive: true);
    final target = File(
      '${directory.path}/${Uri.encodeComponent(messageId)}_'
      '${Uri.encodeComponent(fileName)}',
    );
    if (await target.exists()) {
      final length = await target.length();
      if (fileSize <= 0 || length == fileSize) {
        onProgress?.call(1);
        return target;
      }
      await target.delete();
    }

    final temp = File('${target.path}.part');
    if (await temp.exists()) await temp.delete();
    final download = AppStorage.ref(storagePath, storageBucket: storageBucket)
        .writeToFile(temp);
    final subscription = download.snapshotEvents.listen((snapshot) {
      if (snapshot.totalBytes <= 0) return;
      onProgress?.call(
        (snapshot.bytesTransferred / snapshot.totalBytes).clamp(0.0, 1.0),
      );
    });
    try {
      await download.timeout(const Duration(minutes: 3));
      if (await target.exists()) await target.delete();
      await temp.rename(target.path);
      onProgress?.call(1);
      return target;
    } catch (error, stackTrace) {
      if (await temp.exists()) await temp.delete();
      _logStorageFailure(
        operation: 'download-dm-file',
        storagePath: storagePath,
        error: error,
        stackTrace: stackTrace,
        expectedOwnerUid: ownerUid,
      );
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      await subscription.cancel();
    }
  }

  /// Snack Chat 이미지 업로드.
  /// - 경로: snack_chat_images/{userId}/{snackChatId}/{uuid}.jpg
  Future<String?> uploadSnackChatImage(
    File imageFile, {
    required String userId,
    required String snackChatId,
    void Function(double progress)? onProgress,
  }) async {
    final result = await _uploadChatImage(
      imageFile,
      userId: userId,
      entityId: snackChatId,
      folderName: 'snack_chat_images',
      entityMetadataKey: 'snackChatId',
      logLabel: 'Snack Chat',
      onProgress: onProgress,
      createDownloadUrl: true,
    );
    return result?.downloadUrl;
  }

  /// Authenticated-path upload for new Snack Chat messages. It deliberately
  /// skips getDownloadURL so a bearer token is not created or persisted.
  Future<SnackChatImageUploadResult?> uploadPrivateSnackChatImage(
    File imageFile, {
    required String userId,
    required String snackChatId,
    void Function(double progress)? onProgress,
    PreparedChatImage? prepared,
  }) async {
    final result = await _uploadChatImage(
      imageFile,
      userId: userId,
      entityId: snackChatId,
      folderName: 'snack_chat_images',
      entityMetadataKey: 'snackChatId',
      logLabel: 'Snack Chat',
      onProgress: onProgress,
      createDownloadUrl: false,
      prepared: prepared,
    );
    if (result == null) return null;
    return (
      storagePath: result.storagePath,
      storageBucket: AppStorage.uploadBucketName,
      imageUrl: result.downloadUrl,
      imageWidth: result.imageWidth,
      imageHeight: result.imageHeight,
    );
  }

  /// Removes only an upload owned by the signed-in sender and scoped to the
  /// current Snack Chat. Callers must first confirm that no message document
  /// exists on the server, otherwise a late Firestore commit could leave a
  /// valid message pointing at a deleted object.
  Future<void> deletePrivateSnackChatImage(
    String storagePath, {
    required String userId,
    required String snackChatId,
    String? storageBucket,
  }) async {
    final normalized = storagePath.trim();
    final expectedPrefix = 'snack_chat_images/$userId/$snackChatId/';
    if (!normalized.startsWith(expectedPrefix) ||
        normalized.length <= expectedPrefix.length ||
        normalized.contains('..')) {
      throw ArgumentError.value(
        storagePath,
        'storagePath',
        '현재 사용자와 스낵챗 범위의 이미지 경로가 아닙니다.',
      );
    }
    try {
      await AppStorage.ref(normalized, storageBucket: storageBucket)
          .delete()
          .timeout(const Duration(seconds: 10));
    } on FirebaseException catch (error, stackTrace) {
      if (error.code != 'object-not-found') {
        _logStorageFailure(
          operation: 'delete-snack-chat-image',
          storagePath: normalized,
          error: error,
          stackTrace: stackTrace,
          expectedOwnerUid: userId,
        );
        rethrow;
      }
    }
  }

  /// Returns the authenticated Storage object path for a Firebase download
  /// URL. New Snack Chat messages persist this path as the durable identifier;
  /// legacy clients can continue using the URL fallback.
  String? storagePathFromDownloadUrl(String downloadUrl) {
    final normalized = downloadUrl.trim();
    if (normalized.isEmpty) return null;
    try {
      final path = AppStorage.refFromUrl(normalized).fullPath.trim();
      return path.isEmpty ? null : path;
    } catch (error) {
      if (Logger.isVerboseEnabled)
        Logger.warning('Storage URL 경로 변환 실패: $error');
      return null;
    }
  }

  /// Compresses (only when worthwhile) and measures a picked chat image.
  ///
  /// The gallery picker already re-encodes to JPEG at ~88 quality and at most
  /// 1800 px, so re-compressing every image cost 300–800 ms of CPU and a second
  /// decode without saving bandwidth. Files that are already small JPEGs are
  /// uploaded as-is; larger or non-JPEG inputs go through [_compressImage].
  /// Dimensions come from the encoded header, not a full pixel decode.
  Future<PreparedChatImage?> prepareChatImage(File imageFile) async {
    try {
      final sourceExt = path.extension(imageFile.path).toLowerCase();
      final sourceSize = await imageFile.length();
      final alreadySmallJpeg = (sourceExt == '.jpg' || sourceExt == '.jpeg') &&
          sourceSize > 0 &&
          sourceSize <= _directUploadMaxBytes;
      File encoded = imageFile;
      if (!alreadySmallJpeg) {
        final compressed = await _compressImage(imageFile, forceJpeg: true);
        if (compressed == null) return null;
        encoded = compressed;
      }
      final bytes = await encoded.readAsBytes();
      if (bytes.isEmpty) return null;
      final size = await _encodedImageSize(bytes);
      return PreparedChatImage(
        bytes: bytes,
        sourcePath: imageFile.path,
        tempPath: encoded.path == imageFile.path ? null : encoded.path,
        width: size?.width,
        height: size?.height,
      );
    } catch (error) {
      Logger.error('채팅 이미지 준비 실패: $error');
      return null;
    }
  }

  /// Picker output above this size still goes through compression.
  static const int _directUploadMaxBytes = 600 * 1024;

  Future<({int width, int height})?> _encodedImageSize(Uint8List bytes) async {
    ui.ImmutableBuffer? buffer;
    ui.ImageDescriptor? descriptor;
    try {
      buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width <= 0 || descriptor.height <= 0) return null;
      return (width: descriptor.width, height: descriptor.height);
    } catch (error) {
      if (Logger.isVerboseEnabled) {
        Logger.warning('채팅 이미지 크기 확인 실패: $error');
      }
      return null;
    } finally {
      descriptor?.dispose();
      buffer?.dispose();
    }
  }

  /// DM 이미지 파일을 Firebase Storage에 업로드하고 다운로드 URL을 반환
  /// - 경로: dm_images/{userId}/{conversationId}/{uuid}.jpg
  Future<_ChatImageUploadResult?> _uploadChatImage(
    File imageFile, {
    required String userId,
    required String entityId,
    required String folderName,
    required String entityMetadataKey,
    required String logLabel,
    void Function(double progress)? onProgress,
    required bool createDownloadUrl,
    PreparedChatImage? prepared,
  }) async {
    PreparedChatImage? image = prepared;
    final ownsPrepared = prepared == null;
    String storagePath = '$folderName/<pending>';
    try {
      image ??= await prepareChatImage(imageFile);
      if (image == null) {
        Logger.error('$logLabel 이미지 압축 실패');
        return null;
      }

      final String fileName = '${_uuid.v4()}.jpg';
      final String folderPath = '$folderName/$userId/$entityId';
      final String fullPath = '$folderPath/$fileName';
      storagePath = fullPath;

      if (Logger.isVerboseEnabled)
        Logger.log('$logLabel 이미지 업로드 시작: $fullPath '
            '(${(image.bytes.length / 1024).round()}KB)');
      if (Logger.isVerboseEnabled)
        Logger.log('Firebase Storage 버킷: ${_uploads.bucket}');

      final Reference ref = _uploads.ref().child(folderPath).child(fileName);

      // Bytes are already in memory from preparation; uploading them directly
      // avoids a second file read and lets the SDK pick the fastest transport.
      final UploadTask uploadTask = ref.putData(
        image.bytes,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'fileName': fileName,
            'ownerUid': userId,
            entityMetadataKey: entityId,
            'uploaded': DateTime.now().toString(),
          },
        ),
      );

      uploadTask.snapshotEvents.listen(
        (TaskSnapshot snapshot) {
          final total = snapshot.totalBytes;
          final progress =
              total > 0 ? (snapshot.bytesTransferred / total) : 0.0;
          if (onProgress != null) onProgress(progress.clamp(0.0, 1.0));
        },
        onError: (Object error, StackTrace stackTrace) {
          Logger.error(
            '$logLabel 이미지 업로드 상태 스트림 오류',
            error,
            stackTrace,
          );
        },
      );

      final taskSnapshot = await uploadTask.timeout(
        const Duration(seconds: 180),
        onTimeout: () {
          uploadTask.cancel();
          throw TimeoutException(
            '$logLabel 이미지 업로드 타임아웃',
            const Duration(seconds: 180),
          );
        },
      );
      if (Logger.isVerboseEnabled)
        Logger.log('$logLabel 이미지 업로드 완료: $fullPath');

      final String? downloadUrl =
          createDownloadUrl ? await taskSnapshot.ref.getDownloadURL() : null;
      if (downloadUrl != null) if (Logger.isVerboseEnabled)
        Logger.log('$logLabel 이미지 다운로드 URL 획득');

      if (!createDownloadUrl && folderName == 'snack_chat_images') {
        // The sender can render the finalized upload from the same
        // account/path-scoped cache as receivers. Cache persistence remains
        // best-effort and never changes a successful upload into a failure.
        unawaited(_cacheSnackChatImage(
          userId: userId,
          storagePath: fullPath,
          bytes: image.bytes,
        ));
      }

      return (
        storagePath: fullPath,
        downloadUrl: downloadUrl,
        imageWidth: image.width,
        imageHeight: image.height,
      );
    } on TimeoutException catch (e) {
      Logger.error('$logLabel 이미지 업로드 타임아웃', e);
      return null;
    } catch (e, stackTrace) {
      _logStorageFailure(
        operation: 'upload-${folderName.replaceAll('_', '-')}',
        storagePath: storagePath,
        error: e,
        stackTrace: stackTrace,
        expectedOwnerUid: userId,
      );
      return null;
    } finally {
      if (ownsPrepared) await image?.dispose();
    }
  }

  Future<void> _cacheSnackChatImage({
    required String userId,
    required String storagePath,
    required Uint8List bytes,
  }) async {
    try {
      await SnackChatMediaCacheService.instance.write(
        userId: userId,
        storagePath: storagePath,
        bytes: bytes,
      );
    } catch (error, stackTrace) {
      // The Storage upload already succeeded. A device-cache failure must not
      // turn that successful upload into a failed or duplicate chat message.
      Logger.error(
        'Snack Chat 발신 이미지 캐시 저장 실패',
        error,
        stackTrace,
      );
    }
  }

  // 이미지 압축 메서드
  Future<File?> _compressImage(File file, {bool forceJpeg = false}) async {
    try {
      // 이미지 정보 확인
      final fileSize = await file.length();
      if (Logger.isVerboseEnabled)
        Logger.log('원본 이미지 크기: ${(fileSize / 1024).round()}KB');

      // 파일 확장자 확인
      final sourceExt = path.extension(file.path).toLowerCase();
      final outputExt = forceJpeg ? '.jpg' : sourceExt;

      // 임시 디렉토리 가져오기
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/${_uuid.v4()}$outputExt';

      int quality = 85; // 기본 품질

      // 이미지 크기에 따라 압축 품질 조정
      if (fileSize > 10 * 1024 * 1024) {
        // 10MB 이상
        quality = 50;
      } else if (fileSize > 5 * 1024 * 1024) {
        // 5MB 이상
        quality = 60;
      } else if (fileSize > 2 * 1024 * 1024) {
        // 2MB 이상
        quality = 70;
      }

      // 이미지 압축
      var result = await FlutterImageCompress.compressAndGetFile(
        file.path,
        targetPath,
        quality: quality,
        minWidth: 1024,
        minHeight: 1024,
        format: forceJpeg || sourceExt != '.png'
            ? CompressFormat.jpeg
            : CompressFormat.png,
      );

      if (result == null) {
        Logger.error('이미지 압축 실패, 원본 사용');
        return file;
      }

      final compressedSize = await File(result.path).length();
      if (Logger.isVerboseEnabled)
        Logger.log('압축 후 이미지 크기: ${(compressedSize / 1024).round()}KB');

      // XFile을 File로 변환하여 반환
      return File(result.path);
    } catch (e) {
      Logger.error('이미지 압축 오류: $e');
      return file; // 압축 실패 시 원본 반환
    }
  }

  // Firebase Storage URL 형식을 올바르게 수정하는 정적 메서드
  static String correctFirebaseStorageUrl(String imageUrl) {
    if (Logger.isVerboseEnabled) Logger.log('Storage URL 형식 확인 시작');

    // 이미 올바른 Firebase Storage URL이면 그대로 반환
    if (imageUrl.contains('firebasestorage.googleapis.com') &&
        imageUrl.contains('alt=media') &&
        imageUrl.contains('token=')) {
      if (Logger.isVerboseEnabled) Logger.log('Storage URL 형식 변경 없음');
      return imageUrl;
    }

    String correctedUrl = imageUrl;

    // 잘못된 URL 형식들을 올바른 형식으로 변경 (이 부분은 실제로 잘못된 URL일 때만)
    if (imageUrl.contains('storage.googleapis.com/firebasestorage/')) {
      correctedUrl = imageUrl.replaceAll(
        'storage.googleapis.com/firebasestorage/',
        'firebasestorage.googleapis.com/',
      );
      if (Logger.isVerboseEnabled) Logger.log('Storage URL 호스트 형식 수정됨');
    }

    // 잘못된 .firebase.app을 올바른 .firebasestorage.app으로 변경
    if (correctedUrl.contains('.firebase.app') &&
        !correctedUrl.contains('.firebasestorage.app')) {
      correctedUrl = correctedUrl.replaceAll(
        '.firebase.app',
        '.firebasestorage.app',
      );
      if (Logger.isVerboseEnabled) Logger.log('Storage URL 버킷 도메인 형식 수정됨');
    }

    // alt=media가 없으면 추가
    if (!correctedUrl.contains('alt=media')) {
      if (correctedUrl.contains('?')) {
        correctedUrl = '$correctedUrl&alt=media';
      } else {
        correctedUrl = '$correctedUrl?alt=media';
      }
      if (Logger.isVerboseEnabled) Logger.log('Storage URL media 파라미터 추가됨');
    }

    if (Logger.isVerboseEnabled) Logger.log('Storage URL 형식 확인 완료');
    return correctedUrl;
  }

  // URL로 이미지 삭제
  Future<bool> deleteImage(String imageUrl) async {
    Reference? targetReference;
    try {
      // download URL에서 query(alt=media 등)를 정리하되,
      // token 파라미터는 유지하여 URL 형식이 깨지지 않게 한다.
      String cleanUrl = imageUrl;
      final uri = Uri.tryParse(imageUrl);
      if (uri != null) {
        final qp = Map<String, String>.from(uri.queryParameters);
        qp.remove('alt'); // alt=media 제거 (선택)
        cleanUrl =
            uri.replace(queryParameters: qp.isEmpty ? null : qp).toString();
      }

      final Reference ref = AppStorage.refFromUrl(cleanUrl);
      targetReference = ref;

      // 이미지 삭제
      await ref.delete();
      return true;
    } on FirebaseException catch (e, stackTrace) {
      // 업로드 도중 취소/실패 등으로 객체가 존재하지 않을 수 있음 → 정상 케이스로 취급
      if (e.code == 'object-not-found' || e.code == 'not-found') {
        if (Logger.isVerboseEnabled) Logger.log('이미지 삭제 스킵(이미 없음): ${e.code}');
        return true;
      }
      _logStorageFailure(
        operation: 'delete-image',
        storagePath: targetReference?.fullPath ?? 'unknown',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    } catch (e, stackTrace) {
      _logStorageFailure(
        operation: 'delete-image',
        storagePath: targetReference?.fullPath ?? 'unknown',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }
}

class PostVideoUpload {
  const PostVideoUpload({
    required this.storagePath,
    required this.thumbnailPath,
    required this.storageBucket,
  });

  final String storagePath;
  final String thumbnailPath;
  final String storageBucket;

  Map<String, dynamic> toPayload() => <String, dynamic>{
        'storagePath': storagePath,
        'thumbnailPath': thumbnailPath,
        'storageBucket': storageBucket,
      };
}
