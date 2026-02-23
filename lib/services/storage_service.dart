import 'dart:io';
import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../utils/logger.dart';

/// 프로필 이미지 업로드 결과
/// - downloadUrl: 액세스 토큰 포함 URL
/// - path: Storage object path (profile_images/{uid}/{file}.jpg)
typedef ProfileUploadResult = ({String downloadUrl, String path});

class StorageService {
  // 일반 이미지(posts/dm)는 기본 Storage 설정을 사용
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ✅ 프로필 사진은 지정 버킷에만 저장/사용
  // - Firebase 옵션(storageBucket)과 동일한 "버킷 이름"을 사용한다. (gs:// prefix 불필요)
  // - iOS에서 gs:// prefix 사용 시 resumable 업로드가 불안정한 케이스가 있어 통일한다.
  static const String _profileBucket = 'flutterproject3-af322.firebasestorage.app';
  final FirebaseStorage _profileStorage = FirebaseStorage.instanceFor(bucket: _profileBucket);
  final Uuid _uuid = const Uuid();

  // 이미지 파일을 Firebase Storage에 업로드하고 다운로드 URL을 반환
  Future<String?> uploadImage(File imageFile) async {
    try {
      // 이미지 압축
      final compressedFile = await _compressImage(imageFile);
      if (compressedFile == null) {
        Logger.error('이미지 압축 실패');
        return null;
      }

      // 고유한 파일 이름 생성
      final String fileName = '${_uuid.v4()}.jpg';
      final String folderPath = 'posts';
      final String fullPath = '$folderPath/$fileName';

      Logger.log('이미지 업로드 시작: $fullPath');
      Logger.log('Firebase Storage 버킷: ${_storage.bucket}');

      // 이미지 파일 경로 설정 (posts 폴더 아래에 저장)
      final Reference ref = _storage.ref().child(folderPath).child(fileName);

      // 이미지 파일 업로드 및 진행 상태 모니터링
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

      // 업로드 진행 상태 모니터링 (선택사항)
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        Logger.log('업로드 진행률: ${(progress * 100).toStringAsFixed(2)}%');
      });

      // 타임아웃 처리 개선 - 타임아웃 시 업로드 작업 취소
      TaskSnapshot taskSnapshot;
      try {
        taskSnapshot = await uploadTask.timeout(
          const Duration(seconds: 180),
          onTimeout: () {
            // 타임아웃 발생 시 업로드 작업 취소
            uploadTask.cancel();
            throw TimeoutException('이미지 업로드 타임아웃', const Duration(seconds: 180));
          },
        );
        Logger.log('업로드 완료: $fullPath');
      } on TimeoutException catch (e) {
        Logger.error('업로드 타임아웃', e);
        return null;
      }

      // 이미지 URL 반환 - Firebase가 자동으로 생성하는 다운로드 URL 사용
      final String downloadUrl = await taskSnapshot.ref.getDownloadURL();
      Logger.log('다운로드 URL 획득: $downloadUrl');

      // 임시 파일 삭제
      if (compressedFile.path != imageFile.path) {
        try {
          await compressedFile.delete();
        } catch (e) {
          Logger.error('임시 파일 삭제 실패: $e');
        }
      }

      return downloadUrl;
    } catch (e) {
      Logger.error('이미지 업로드 오류: $e');

      // 오류 상세 정보 수집
      String errorDetails = '';
      if (e is FirebaseException) {
        errorDetails = '코드: ${e.code}, 메시지: ${e.message}';
      }
      Logger.error('Firebase 오류 상세: $errorDetails');

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
      compressedFile = await _compressImage(imageFile);
      if (compressedFile == null) {
        Logger.error('프로필 이미지 압축 실패');
        return null;
      }

      final String fileName = '${_uuid.v4()}.jpg';
      final String folderPath = 'profile_images/$userId';
      fullPath = '$folderPath/$fileName';

      Logger.log('프로필 이미지 업로드 시작: $fullPath');
      Logger.log('Firebase Storage 버킷(프로필): ${_profileStorage.bucket}');

      ref = _profileStorage.ref().child(folderPath).child(fileName);

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
          throw TimeoutException('프로필 이미지 업로드 타임아웃', const Duration(seconds: 180));
        },
      );

      Logger.log('프로필 이미지 업로드 완료: $fullPath');

      final String downloadUrl = await taskSnapshot.ref.getDownloadURL();
      Logger.log('프로필 이미지 다운로드 URL 획득: $downloadUrl');
      return (downloadUrl: downloadUrl, path: fullPath);
    } on TimeoutException catch (e) {
      Logger.error('프로필 이미지 업로드 타임아웃', e);
      return null;
    } catch (e) {
      Logger.error('프로필 이미지 업로드 오류: $e');
      String errorDetails = '';
      String message = '';
      if (e is FirebaseException) {
        errorDetails = '코드: ${e.code}, 메시지: ${e.message}';
        message = (e.message ?? '');
      }
      Logger.error('Firebase 오류 상세: $errorDetails');

      // ✅ iOS 간헐 이슈 방어:
      // - 업로드가 서버에서 이미 finalize 된 후, SDK 내부 cancelFetcher가 뒤늦게 실행되며
      //   HTTP 400이 발생할 수 있음. (finalized 문구가 SDK 에러 메시지에 포함되지 않는 경우도 있음)
      // - 이 경우 객체는 실제로 업로드되어 있을 가능성이 있으므로 download URL 복구를 재시도한다.
      final isHttp400 = message.contains('HTTPStatus error 400') || message.contains('Code=400');
      if (isHttp400 && ref != null && fullPath != null) {
        for (var attempt = 0; attempt < 3; attempt++) {
          try {
            // 짧은 지연 후 재시도 (resumable finalize/메타데이터 반영 경합 완화)
            await Future.delayed(Duration(milliseconds: 220 * (attempt + 1)));
            final recovered = await ref.getDownloadURL();
            Logger.log('✅ HTTP 400 복구 성공: downloadURL 획득 ($fullPath, attempt=${attempt + 1})');
            return (downloadUrl: recovered, path: fullPath);
          } catch (recoveryError) {
            Logger.error('⚠️ HTTP 400 복구 재시도 실패(attempt=${attempt + 1}): $recoveryError');
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
  }) async {
    try {
      final compressedFile = await _compressImage(imageFile);
      if (compressedFile == null) {
        Logger.error('DM 이미지 압축 실패');
        return null;
      }

      final String fileName = '${_uuid.v4()}.jpg';
      final String folderPath = 'dm_images/$userId/$conversationId';
      final String fullPath = '$folderPath/$fileName';

      Logger.log('DM 이미지 업로드 시작: $fullPath');
      Logger.log('Firebase Storage 버킷: ${_storage.bucket}');

      final Reference ref = _storage.ref().child(folderPath).child(fileName);

      final UploadTask uploadTask = ref.putFile(
        compressedFile,
        SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {
            'fileName': fileName,
            'conversationId': conversationId,
            'uploaded': DateTime.now().toString(),
          },
        ),
      );

      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final total = snapshot.totalBytes;
        final progress = total > 0 ? (snapshot.bytesTransferred / total) : 0.0;
        Logger.log('DM 이미지 업로드 진행률: ${(progress * 100).toStringAsFixed(2)}%');
        if (onProgress != null) onProgress(progress.clamp(0.0, 1.0));
      });

      TaskSnapshot taskSnapshot;
      try {
        taskSnapshot = await uploadTask.timeout(
          const Duration(seconds: 180),
          onTimeout: () {
            uploadTask.cancel();
            throw TimeoutException('DM 이미지 업로드 타임아웃', const Duration(seconds: 180));
          },
        );
        Logger.log('DM 이미지 업로드 완료: $fullPath');
      } on TimeoutException catch (e) {
        Logger.error('DM 이미지 업로드 타임아웃', e);
        return null;
      }

      final String downloadUrl = await taskSnapshot.ref.getDownloadURL();
      Logger.log('DM 이미지 다운로드 URL 획득: $downloadUrl');

      if (compressedFile.path != imageFile.path) {
        try {
          await compressedFile.delete();
        } catch (e) {
          Logger.error('DM 임시 파일 삭제 실패: $e');
        }
      }

      return downloadUrl;
    } catch (e) {
      Logger.error('DM 이미지 업로드 오류: $e');

      String errorDetails = '';
      if (e is FirebaseException) {
        errorDetails = '코드: ${e.code}, 메시지: ${e.message}';
      }
      Logger.error('Firebase 오류 상세: $errorDetails');

      return null;
    }
  }

  // 이미지 압축 메서드
  Future<File?> _compressImage(File file) async {
    try {
      // 이미지 정보 확인
      final fileSize = await file.length();
      Logger.log('원본 이미지 크기: ${(fileSize / 1024).round()}KB');

      // 파일 확장자 확인
      final ext = path.extension(file.path).toLowerCase();

      // 임시 디렉토리 가져오기
      final tempDir = await getTemporaryDirectory();
      final targetPath = '${tempDir.path}/${_uuid.v4()}$ext';

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
        format: ext == '.png' ? CompressFormat.png : CompressFormat.jpeg,
      );

      if (result == null) {
        Logger.error('이미지 압축 실패, 원본 사용');
        return file;
      }

      final compressedSize = await File(result.path).length();
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
    Logger.log('🔧 URL 수정 시작: $imageUrl');

    // 이미 올바른 Firebase Storage URL이면 그대로 반환
    if (imageUrl.contains('firebasestorage.googleapis.com') &&
        imageUrl.contains('alt=media') &&
        imageUrl.contains('token=')) {
      Logger.log('✅ 이미 올바른 URL 형식, 변경 없음');
      return imageUrl;
    }

    String correctedUrl = imageUrl;

    // 잘못된 URL 형식들을 올바른 형식으로 변경 (이 부분은 실제로 잘못된 URL일 때만)
    if (imageUrl.contains('storage.googleapis.com/firebasestorage/')) {
      correctedUrl = imageUrl.replaceAll(
        'storage.googleapis.com/firebasestorage/',
        'firebasestorage.googleapis.com/',
      );
      Logger.log('🔧 URL 형식 수정됨 (storage->firebasestorage): $correctedUrl');
    }

    // 잘못된 .firebase.app을 올바른 .firebasestorage.app으로 변경
    if (correctedUrl.contains('.firebase.app') &&
        !correctedUrl.contains('.firebasestorage.app')) {
      correctedUrl = correctedUrl.replaceAll(
        '.firebase.app',
        '.firebasestorage.app',
      );
      Logger.log(
        '🔧 URL 도메인 수정됨 (.firebase.app -> .firebasestorage.app): $correctedUrl',
      );
    }

    // alt=media가 없으면 추가
    if (!correctedUrl.contains('alt=media')) {
      if (correctedUrl.contains('?')) {
        correctedUrl = '$correctedUrl&alt=media';
      } else {
        correctedUrl = '$correctedUrl?alt=media';
      }
      Logger.log('🔧 alt=media 파라미터 추가: $correctedUrl');
    }

    Logger.log('✅ URL 수정 완료: $correctedUrl');
    return correctedUrl;
  }

  // URL로 이미지 삭제
  Future<bool> deleteImage(String imageUrl) async {
    try {
      // download URL에서 query(alt=media 등)를 정리하되,
      // token 파라미터는 유지하여 URL 형식이 깨지지 않게 한다.
      String cleanUrl = imageUrl;
      final uri = Uri.tryParse(imageUrl);
      if (uri != null) {
        final qp = Map<String, String>.from(uri.queryParameters);
        qp.remove('alt'); // alt=media 제거 (선택)
        cleanUrl = uri.replace(queryParameters: qp.isEmpty ? null : qp).toString();
      }

      Logger.log('이미지 삭제 - 정제된 URL: $cleanUrl');
      final Reference ref = _storage.refFromURL(cleanUrl);

      // 이미지 삭제
      await ref.delete();
      return true;
    } on FirebaseException catch (e) {
      // 업로드 도중 취소/실패 등으로 객체가 존재하지 않을 수 있음 → 정상 케이스로 취급
      if (e.code == 'object-not-found' || e.code == 'not-found') {
        Logger.log('이미지 삭제 스킵(이미 없음): ${e.code}');
        return true;
      }
      Logger.error('이미지 삭제 Firebase 오류: code=${e.code}, message=${e.message}');
      return false;
    } catch (e) {
      Logger.error('이미지 삭제 오류: $e');
      return false;
    }
  }
}
