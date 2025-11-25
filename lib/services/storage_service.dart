import 'dart:io';
import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../utils/logger.dart';
import '../utils/logger.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
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
      String cleanUrl = imageUrl;

      // alt=media 파라미터 제거 (참조 추출에 문제가 될 수 있음)
      if (imageUrl.contains('?alt=media')) {
        cleanUrl = imageUrl.replaceAll('?alt=media', '');
      } else if (imageUrl.contains('&alt=media')) {
        cleanUrl = imageUrl.replaceAll('&alt=media', '');
      }

      Logger.log('이미지 삭제 - 정제된 URL: $cleanUrl');
      final Reference ref = _storage.refFromURL(cleanUrl);

      // 이미지 삭제
      await ref.delete();
      return true;
    } catch (e) {
      Logger.error('이미지 삭제 오류: $e');
      return false;
    }
  }
}
