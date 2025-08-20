// lib/services/post_service.dart
// 게시글 관련 CRUD 작업 처리
// Firestore와 통신하여 게시글 데이터 관리
// 좋아요 기능 구현
// 게시글 조회 및 필터링 기능

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import 'notification_service.dart';
import 'storage_service.dart';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();
  final StorageService _storageService = StorageService();

  // 이미지를 포함한 게시글 추가
  Future<bool> addPost(String title, String content, {List<File>? imageFiles}) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다');
      }

      // 사용자 데이터 가져오기
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final nickname = userData?['nickname'] ?? '익명';
      final nationality = userData?['nationality'] ?? ''; // 국적 정보 가져오기
      
      print("AddPost - 사용자 데이터: ${userData?.toString()} | 닉네임: $nickname | 국적: $nationality");
      
      // 게시글 작성 시간
      final now = FieldValue.serverTimestamp();
      
      // 이미지 파일이 있는 경우 업로드 (병렬 처리로 성능 향상)
      List<String> imageUrls = [];
      if (imageFiles != null && imageFiles.isNotEmpty) {
        print('이미지 업로드 시작: ${imageFiles.length}개 파일');
        
        // 파일 사이즈 로깅
        for (int i = 0; i < imageFiles.length; i++) {
          final fileSize = await imageFiles[i].length();
          print('이미지 #$i 크기: ${(fileSize / 1024).round()}KB');
        }
        
        // 한번에 하나씩 순차적으로 업로드하지 않고, 병렬로 처리
        final futures = imageFiles.map((imageFile) => _storageService.uploadImage(imageFile));
        
        try {
          // 모든 이미지 업로드 작업 동시 실행 후 결과 수집
          final results = await Future.wait(
            futures,
            eagerError: false, // 하나가 실패해도 다른 이미지 계속 업로드
          );
          
          // null이 아닌 URL만 추가
          imageUrls = results.where((url) => url != null).cast<String>().toList();
          
          print('이미지 업로드 완료: ${imageUrls.length}개 (요청: ${imageFiles.length}개)');
          // 성공한 URL 로깅
          for (int i = 0; i < imageUrls.length; i++) {
            print('이미지 URL #$i: ${imageUrls[i]}');
          }
          
          // 모든 이미지 업로드에 실패한 경우
          if (imageUrls.isEmpty && imageFiles.isNotEmpty) {
            print('모든 이미지 업로드 실패');
          }
        } catch (e) {
          print('이미지 병렬 업로드 중 오류: $e');
          // 오류가 발생해도 게시글은 계속 생성 (이미지 없이)
        }
      }

      // 게시글 데이터 생성
      final postData = {
        'userId': user.uid,
        'authorNickname': nickname,
        'authorNationality': nationality, // 작성자 국적 추가
        'title': title,
        'content': content,
        'imageUrls': imageUrls,
        'createdAt': now,
        'updatedAt': now,
        'likes': 0,
        'likedBy': [],
        'commentCount': 0,
      };
      
      // Firestore 데이터 저장 로깅
      print('게시글 저장: title=${title}, imageUrls=${imageUrls.length}개');

      // Firestore에 저장
      final docRef = await _firestore.collection('posts').add(postData);
      print('게시글 저장 완료: ${docRef.id}');
      
      return true;
    } catch (e) {
      print('게시글 작성 오류: $e');
      return false;
    }
  }

  // 모든 게시글 가져오기
  Stream<List<Post>> getAllPosts() {
    return _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return Post(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          author: data['authorNickname'] ?? '익명',
          authorNationality: data['authorNationality'] ?? '알 수 없음', 
          createdAt: data['createdAt'] != null
              ? (data['createdAt'] as Timestamp).toDate()
              : DateTime.now(),
          userId: data['userId'] ?? '',
          commentCount: data['commentCount'] ?? 0,
          likes: data['likes'] ?? 0,
          likedBy: List<String>.from(data['likedBy'] ?? []),
          imageUrls: List<String>.from(data['imageUrls'] ?? []),
        );
      }).toList();
    });
  }

  // 특정 게시글 가져오기
  Future<Post?> getPostById(String postId) async {
    try {
      final doc = await _firestore.collection('posts').doc(postId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      print("PostService.getPostById - 게시글 데이터: ${data['id']} | 작성자: ${data['authorNickname']} | 국적: ${data['authorNationality'] ?? '없음'}");
      
      return Post(
        id: doc.id,
        title: data['title'] ?? '',
        content: data['content'] ?? '',
        author: data['authorNickname'] ?? '익명',
        authorNationality: data['authorNationality'] ?? '알 수 없음', 
        createdAt: data['createdAt'] != null
            ? (data['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
        userId: data['userId'] ?? '',
        commentCount: data['commentCount'] ?? 0,
        likes: data['likes'] ?? 0,
        likedBy: List<String>.from(data['likedBy'] ?? []),
        imageUrls: List<String>.from(data['imageUrls'] ?? []),
      );
    } catch (e) {
      print('게시글 조회 오류: $e');
      return null;
    }
  }

  Future<bool> toggleLike(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('좋아요 실패: 로그인이 필요합니다.');
        return false;
      }

      // 트랜잭션 대신 더 간단한 접근 방식 사용
      // 게시글 문서 레퍼런스
      final postRef = _firestore.collection('posts').doc(postId);

      // 게시글 데이터 가져오기
      final postDoc = await postRef.get();
      if (!postDoc.exists) {
        print('게시글이 존재하지 않습니다: $postId');
        return false;
      }

      // 현재 좋아요 상태 파악
      final data = postDoc.data()!;
      List<dynamic> likedBy = List.from(data['likedBy'] ?? []);
      bool hasLiked = likedBy.contains(user.uid);

      final postTitle = data['title'] ?? '';
      final authorId = data['userId'];

      print('현재 좋아요 상태: $hasLiked, 사용자 ID: ${user.uid}, 게시글 ID: $postId');

      // 좋아요 토글
      if (hasLiked) {
        // 좋아요 취소
        likedBy.remove(user.uid);
        await postRef.update({
          'likedBy': likedBy,
          'likes': FieldValue.increment(-1),
        });
        print('좋아요 취소 완료');
      } else {
        // 좋아요 추가
        likedBy.add(user.uid);
        await postRef.update({
          'likedBy': likedBy,
          'likes': FieldValue.increment(1),
        });
        print('좋아요 추가 완료');

        // 좋아요 알림 전송 (자신의 게시글이 아닌 경우에만)
        if (authorId != null && authorId != user.uid) {
          // 사용자 정보 가져오기
          final userDoc = await _firestore.collection('users').doc(user.uid).get();
          final userData = userDoc.data();
          final nickname = userData?['nickname'] ?? '익명';

          // 좋아요 알림 전송
          await _notificationService.sendNewLikeNotification(
              postId,
              postTitle,
              authorId,
              nickname,
              user.uid
          );
        }
      }

      return true;
    } catch (e) {
      print('좋아요 기능 오류: $e');
      return false;
    }
  }

  // 현재 사용자가 좋아요를 눌렀는지 확인
  Future<bool> hasUserLikedPost(String postId) async {
    final user = _auth.currentUser;
    if (user == null) return false;

    try {
      final doc = await _firestore.collection('posts').doc(postId).get();
      if (!doc.exists) return false;

      final data = doc.data()!;
      List<dynamic> likedBy = List.from(data['likedBy'] ?? []);

      return likedBy.contains(user.uid);
    } catch (e) {
      print('좋아요 확인 오류: $e');
      return false;
    }
  }

  // 게시글 삭제
  Future<bool> deletePost(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('삭제 실패: 로그인이 필요합니다.');
        return false;
      }

      // 게시글 문서 가져오기
      final postDoc = await _firestore.collection('posts').doc(postId).get();

      // 문서가 없는 경우
      if (!postDoc.exists) {
        print('삭제 실패: 게시글이 존재하지 않습니다.');
        return false;
      }

      final data = postDoc.data()!;

      // 현재 사용자가 작성자인지 확인
      if (data['userId'] != user.uid) {
        print('삭제 실패: 게시글 작성자만 삭제할 수 있습니다.');
        return false;
      }

      // 게시글 삭제
      await _firestore.collection('posts').doc(postId).delete();

      // 이미지가 있으면 삭제
      if (data['imageUrls'] != null) {
        List<String> imageUrls = List<String>.from(data['imageUrls'] ?? []);
        for (final imageUrl in imageUrls) {
          await _storageService.deleteImage(imageUrl);
        }
      }

      print('게시글 삭제 성공: $postId');
      return true;
    } catch (e) {
      print('게시글 삭제 오류: $e');
      return false;
    }
  }

  // 현재 사용자가 게시글 작성자인지 확인
  Future<bool> isCurrentUserAuthor(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (!postDoc.exists) return false;

      final data = postDoc.data()!;
      return data['userId'] == user.uid;
    } catch (e) {
      print('작성자 확인 오류: $e');
      return false;
    }
  }
}