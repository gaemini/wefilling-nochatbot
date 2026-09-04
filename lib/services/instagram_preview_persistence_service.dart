import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import '../models/shared_link_preview.dart';
import '../utils/logger.dart';

class InstagramPreviewPersistenceResult {
  const InstagramPreviewPersistenceResult({
    required this.preview,
    this.createdStorageObject = false,
  });

  final SharedLinkPreview preview;
  final bool createdStorageObject;
}

class InstagramPreviewPersistenceService {
  InstagramPreviewPersistenceService._();

  static final InstagramPreviewPersistenceService instance =
      InstagramPreviewPersistenceService._();

  static const int _previewVersion = 4;
  static const int _maximumInputBytes = 20 * 1024 * 1024;
  static const int _maximumLongEdge = 1280;
  static const int _jpegQuality = 85;

  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<InstagramPreviewPersistenceResult> persist({
    required SharedLinkPreview preview,
    required String ownerUid,
    required String postId,
    File? localImageFile,
    String localImageSource = 'local_preview',
    String requestId = '',
  }) async {
    if (preview.provider != 'instagram') {
      return InstagramPreviewPersistenceResult(preview: preview);
    }
    if (preview.isPersistentThumbnail &&
        preview.thumbnailStoragePath.trim().isNotEmpty) {
      return InstagramPreviewPersistenceResult(preview: preview);
    }
    if (!RegExp(r'^[A-Za-z0-9]{20}$').hasMatch(postId) || ownerUid.isEmpty) {
      throw ArgumentError('Invalid Instagram preview owner or post id.');
    }

    final sourceFile = localImageFile;
    final hasSharedPayloadImage =
        sourceFile != null && localImageSource == 'share_payload';

    // Instagram이 실제 이미지 payload를 전달한 경우에만 해당 이미지를
    // 최우선으로 보존한다. 작성 화면 캐시에서 받은 일반 미리보기는 서버
    // resolver를 먼저 사용해 App Check/Storage 이중 요청을 피한다.
    if (hasSharedPayloadImage) {
      final localResult = await _tryPersistLocal(
        preview: preview,
        ownerUid: ownerUid,
        postId: postId,
        imageFile: sourceFile,
        source: 'share_payload',
        requestId: requestId,
      );
      if (localResult != null) return localResult;
    }

    final remoteResult = await _tryPersistRemote(
      preview: preview,
      postId: postId,
      requestId: requestId,
    );
    if (remoteResult != null) return remoteResult;

    // 서버가 일시적으로 원격 썸네일을 가져오지 못한 경우에만 작성 화면의
    // 캐시 이미지를 마지막 대안으로 사용한다.
    if (sourceFile != null && !hasSharedPayloadImage) {
      final localResult = await _tryPersistLocal(
        preview: preview,
        ownerUid: ownerUid,
        postId: postId,
        imageFile: sourceFile,
        source: 'local_preview',
        requestId: requestId,
      );
      if (localResult != null) return localResult;
    }

    return InstagramPreviewPersistenceResult(
      preview: preview.copyWith(
        thumbnailUrl: '',
        thumbnailStoragePath: '',
        thumbnailSource: '',
        thumbnailWidth: 0,
        thumbnailHeight: 0,
        previewMode: 'link',
        previewStatus: 'unavailable',
        previewVersion: _previewVersion,
      ),
    );
  }

  Future<void> deleteUnused(SharedLinkPreview preview) async {
    final path = preview.thumbnailStoragePath.trim();
    if (path.isEmpty || !path.startsWith('post_link_previews/')) return;
    try {
      await _storage.ref(path).delete().timeout(const Duration(seconds: 12));
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') rethrow;
    }
  }

  Future<InstagramPreviewPersistenceResult?> _tryPersistLocal({
    required SharedLinkPreview preview,
    required String ownerUid,
    required String postId,
    required File imageFile,
    required String source,
    required String requestId,
  }) async {
    final exists = await imageFile.exists();
    if (!exists) return null;

    try {
      final length = await imageFile.length();
      if (length <= 0 || length > _maximumInputBytes) return null;
      final bytes = await imageFile.readAsBytes();
      if (!_isSupportedImage(bytes)) return null;
      final originalSize = await _decodeSize(bytes);
      if (originalSize == null) return null;

      final scale = originalSize.longEdge > _maximumLongEdge
          ? _maximumLongEdge / originalSize.longEdge
          : 1.0;
      final targetWidth = (originalSize.width * scale).round().clamp(1, 10000);
      final targetHeight =
          (originalSize.height * scale).round().clamp(1, 10000);
      final compressed = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: targetWidth,
        minHeight: targetHeight,
        quality: _jpegQuality,
        format: CompressFormat.jpeg,
      );
      if (compressed.isEmpty) return null;
      final persistedSize = await _decodeSize(compressed);
      if (persistedSize == null) return null;

      final storagePath = 'post_link_previews/$ownerUid/$postId/instagram.jpg';
      final ref = _storage.ref(storagePath);
      final existing = await _existingLocalUpload(
        ref: ref,
        preview: preview,
        storagePath: storagePath,
        source: source,
      );
      if (existing != null) return existing;

      final snapshot = await ref
          .putData(
            Uint8List.fromList(compressed),
            SettableMetadata(
              contentType: 'image/jpeg',
              cacheControl: 'public,max-age=31536000,immutable',
              customMetadata: <String, String>{
                'provider': 'instagram',
                'postId': postId,
                'ownerUid': ownerUid,
                'source': source,
                'width': '${persistedSize.width}',
                'height': '${persistedSize.height}',
              },
            ),
          )
          .timeout(const Duration(seconds: 90));
      final downloadUrl = await snapshot.ref
          .getDownloadURL()
          .timeout(const Duration(seconds: 15));
      final persistedPreview = _persistedPreview(
        preview: preview,
        downloadUrl: downloadUrl,
        storagePath: storagePath,
        source: source,
        width: persistedSize.width,
        height: persistedSize.height,
      );
      return InstagramPreviewPersistenceResult(
        preview: persistedPreview,
        createdStorageObject: true,
      );
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning(
        '[InstagramPreview][local-image-decode-or-upload-failed] '
        'type=${error.runtimeType}',
      );
      return null;
    }
  }

  Future<InstagramPreviewPersistenceResult?> _existingLocalUpload({
    required Reference ref,
    required SharedLinkPreview preview,
    required String storagePath,
    required String source,
  }) async {
    try {
      final metadata = await ref.getMetadata().timeout(
            const Duration(seconds: 6),
          );
      final custom = metadata.customMetadata ?? const <String, String>{};
      if (metadata.size == null || metadata.size! <= 0) return null;
      final width = int.tryParse(custom['width'] ?? '') ?? 0;
      final height = int.tryParse(custom['height'] ?? '') ?? 0;
      if (width <= 0 || height <= 0) return null;
      final downloadUrl = await ref.getDownloadURL();
      return InstagramPreviewPersistenceResult(
        preview: _persistedPreview(
          preview: preview,
          downloadUrl: downloadUrl,
          storagePath: storagePath,
          source: custom['source'] ?? source,
          width: width,
          height: height,
        ),
      );
    } on FirebaseException catch (error) {
      if (error.code != 'object-not-found') {
        if (Logger.isVerboseEnabled) Logger.warning(
          '[InstagramPreview][existing-object-read] code=${error.code}',
        );
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<InstagramPreviewPersistenceResult?> _tryPersistRemote({
    required SharedLinkPreview preview,
    required String postId,
    required String requestId,
  }) async {
    final canonicalUrl = preview.canonicalUrl.trim();
    final shortcode = preview.shortcode.trim().isNotEmpty
        ? preview.shortcode.trim()
        : preview.contentId.trim();
    if (canonicalUrl.isEmpty || shortcode.isEmpty) return null;

    try {
      final response = await FirebaseFunctions.instance
          .httpsCallable('persistInstagramPreviewThumbnail')
          .call(<String, dynamic>{
        'postId': postId,
        'canonicalUrl': canonicalUrl,
        'shortcode': shortcode,
        'contentType': preview.contentType,
      }).timeout(const Duration(seconds: 30));
      if (response.data is! Map) return null;
      final data = Map<String, dynamic>.from(response.data as Map);
      final downloadUrl = (data['thumbnailUrl'] ?? '').toString();
      final storagePath = (data['thumbnailStoragePath'] ?? '').toString();
      final width = (data['width'] as num?)?.toInt() ?? 0;
      final height = (data['height'] as num?)?.toInt() ?? 0;
      if (downloadUrl.isEmpty ||
          storagePath.isEmpty ||
          width <= 0 ||
          height <= 0) {
        return null;
      }
      return InstagramPreviewPersistenceResult(
        preview: _persistedPreview(
          preview: preview,
          downloadUrl: downloadUrl,
          storagePath: storagePath,
          source: (data['thumbnailSource'] ?? 'remote_resolver').toString(),
          width: width,
          height: height,
        ),
        createdStorageObject: data['created'] != false,
      );
    } on FirebaseFunctionsException catch (error) {
      final reason = error.details is Map
          ? ((error.details as Map)['reason'] ?? '').toString()
          : '';
      if (Logger.isVerboseEnabled) Logger.warning(
        '[InstagramPreview][remote-fallback] '
        'code=${error.code} reason=$reason',
      );
      return null;
    } catch (error) {
      if (Logger.isVerboseEnabled) Logger.warning(
        '[InstagramPreview][remote-fallback] unavailable=${error.runtimeType}',
      );
      return null;
    }
  }

  SharedLinkPreview _persistedPreview({
    required SharedLinkPreview preview,
    required String downloadUrl,
    required String storagePath,
    required String source,
    required int width,
    required int height,
  }) {
    return preview.copyWith(
      thumbnailUrl: downloadUrl,
      thumbnailStoragePath: storagePath,
      thumbnailSource: source,
      thumbnailWidth: width,
      thumbnailHeight: height,
      aspectRatio: (width / height).clamp(0.5, 2.4),
      previewMode: 'image',
      previewStatus: 'ready',
      previewVersion: _previewVersion,
    );
  }

  bool _isSupportedImage(Uint8List bytes) {
    if (bytes.length < 12) return false;
    final isJpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    final isPng = bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final isWebp = String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP';
    return isJpeg || isPng || isWebp;
  }

  Future<_ImageSize?> _decodeSize(Uint8List bytes) async {
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final size = _ImageSize(frame.image.width, frame.image.height);
      frame.image.dispose();
      return size.width > 0 && size.height > 0 ? size : null;
    } catch (_) {
      return null;
    } finally {
      codec?.dispose();
    }
  }
}

class _ImageSize {
  const _ImageSize(this.width, this.height);

  final int width;
  final int height;

  int get longEdge => width > height ? width : height;
}
