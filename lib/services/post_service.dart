// lib/services/post_service.dart
// 게시글 관련 CRUD 작업 처리
// Firestore와 통신하여 게시글 데이터 관리
// 좋아요 기능 구현
// 게시글 조회 및 필터링 기능

import 'dart:io';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/post.dart';
import 'notification_service.dart';
import 'storage_service.dart';
import 'content_filter_service.dart';
import 'cache/post_cache_manager.dart';
import 'cache/cache_feature_flags.dart';
import '../utils/logger.dart';

class PostService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();
  final StorageService _storageService = StorageService();
  final PostCacheManager _cache = PostCacheManager();

  // 이미지를 포함한 게시글 추가
  Future<bool> addPost(
    String title,
    String content, {
    List<File>? imageFiles,
    String visibility = 'public', // 공개 범위
    bool isAnonymous = false, // 익명 여부
    List<String> visibleToCategoryIds = const [], // 공개할 카테고리 ID 목록
  }) async {
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
      final photoURL = userData?['photoURL'] ?? user.photoURL ?? ''; // 프로필 사진 URL 가져오기

      Logger.log(
        "AddPost - 사용자 데이터: ${userData?.toString()} | 닉네임: $nickname | 국적: $nationality | 프로필 사진: ${photoURL.isNotEmpty ? '있음' : '없음'}",
      );

      // 게시글 작성 시간
      final now = FieldValue.serverTimestamp();

      // 이미지 파일이 있는 경우 업로드 (병렬 처리로 성능 향상)
      List<String> imageUrls = [];
      if (imageFiles != null && imageFiles.isNotEmpty) {
        Logger.log('이미지 업로드 시작: ${imageFiles.length}개 파일');

        // 파일 사이즈 로깅
        for (int i = 0; i < imageFiles.length; i++) {
          final fileSize = await imageFiles[i].length();
          Logger.log('이미지 #$i 크기: ${(fileSize / 1024).round()}KB');
        }

        // 한번에 하나씩 순차적으로 업로드하지 않고, 병렬로 처리
        final futures = imageFiles.map(
          (imageFile) => _storageService.uploadImage(imageFile),
        );

        try {
          // 모든 이미지 업로드 작업 동시 실행 후 결과 수집
          final results = await Future.wait(
            futures,
            eagerError: false, // 하나가 실패해도 다른 이미지 계속 업로드
          );

          // null이 아닌 URL만 추가
          imageUrls =
              results.where((url) => url != null).cast<String>().toList();

          Logger.log('이미지 업로드 완료: ${imageUrls.length}개 (요청: ${imageFiles.length}개)');
          // 성공한 URL 로깅
          for (int i = 0; i < imageUrls.length; i++) {
            Logger.log('이미지 URL #$i: ${imageUrls[i]}');
          }

          // 모든 이미지 업로드에 실패한 경우
          if (imageUrls.isEmpty && imageFiles.isNotEmpty) {
            Logger.error('모든 이미지 업로드 실패');
          }
        } catch (e) {
          Logger.error('이미지 병렬 업로드 중 오류: $e');
          // 오류가 발생해도 게시글은 계속 생성 (이미지 없이)
        }
      }

      // 카테고리별 공개인 경우 allowedUserIds 계산
      List<String> allowedUserIds = [];
      if (visibility == 'category' && visibleToCategoryIds.isNotEmpty) {
        Logger.log('카테고리별 공개 게시글: 허용 사용자 ID 계산 중...');
        try {
          // 각 카테고리의 친구 ID들을 가져와서 합침
          final Set<String> uniqueFriendIds = {};
          for (final categoryId in visibleToCategoryIds) {
            final categoryDoc = await _firestore
                .collection('friend_categories')
                .doc(categoryId)
                .get();
            
            if (categoryDoc.exists) {
              final categoryData = categoryDoc.data();
              final friendIds = List<String>.from(categoryData?['friendIds'] ?? []);
              uniqueFriendIds.addAll(friendIds);
              Logger.log('카테고리 ${categoryId}: ${friendIds.length}명의 친구');
            }
          }
          
          // 작성자 본인도 포함
          uniqueFriendIds.add(user.uid);
          allowedUserIds = uniqueFriendIds.toList();
          Logger.log('총 ${allowedUserIds.length}명이 이 게시글을 볼 수 있습니다.');
        } catch (e) {
          Logger.error('allowedUserIds 계산 오류: $e');
          // 오류 발생 시 작성자만 볼 수 있도록 설정
          allowedUserIds = [user.uid];
        }
      }

      // 게시글 데이터 생성
      final postData = {
        'userId': user.uid,
        'authorNickname': nickname,
        'authorNationality': nationality, // 작성자 국적 추가
        'authorPhotoURL': photoURL, // 작성자 프로필 사진 URL 추가
        'title': title,
        'content': content,
        'imageUrls': imageUrls,
        'createdAt': now,
        'updatedAt': now,
        'visibility': visibility, // 공개 범위
        'isAnonymous': isAnonymous, // 익명 여부
        'visibleToCategoryIds': visibleToCategoryIds, // 공개할 카테고리 ID 목록
        'allowedUserIds': allowedUserIds, // 허용된 사용자 ID 목록
        'likes': 0,
        'likedBy': [],
        'commentCount': 0,
      };

      // Firestore 데이터 저장 로깅
      Logger.log('게시글 저장: title=${title}, imageUrls=${imageUrls.length}개');

      // Firestore에 저장
      final docRef = await _firestore.collection('posts').add(postData);
      Logger.log('게시글 저장 완료: ${docRef.id}');

      // 캐시 무효화 (새 게시글이 추가되었으므로 목록 캐시 삭제)
      if (CacheFeatureFlags.isPostCacheEnabled) {
        _cache.invalidate();
        Logger.log('💾 게시글 캐시 무효화 (새 게시글 추가)');
      }

      return true;
    } catch (e) {
      Logger.error('게시글 작성 오류: $e');
      return false;
    }
  }

  // 모든 게시글 가져오기
  Stream<List<Post>> getAllPosts() {
    final user = _auth.currentUser;
    
    return _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
          Logger.log('📊 Firestore에서 받은 게시글 수: ${snapshot.docs.length}');
          
          final posts = snapshot.docs.map((doc) {
            final data = doc.data();
            final post = Post(
              id: doc.id,
              title: data['title'] ?? '',
              content: data['content'] ?? '',
              author: data['authorNickname'] ?? '익명',
              authorNationality: data['authorNationality'] ?? '알 수 없음',
              authorPhotoURL: data['authorPhotoURL'] ?? '',
              createdAt:
                  data['createdAt'] != null
                      ? (data['createdAt'] as Timestamp).toDate()
                      : DateTime.now(),
              userId: data['userId'] ?? '',
              commentCount: data['commentCount'] ?? 0,
              likes: data['likes'] ?? 0,
              viewCount: data['viewCount'] ?? 0,
              likedBy: List<String>.from(data['likedBy'] ?? []),
              imageUrls: List<String>.from(data['imageUrls'] ?? []),
              visibility: data['visibility'] ?? 'public',
              isAnonymous: data['isAnonymous'] ?? false,
              visibleToCategoryIds: List<String>.from(data['visibleToCategoryIds'] ?? []),
              allowedUserIds: List<String>.from(data['allowedUserIds'] ?? []),
            );
            
            // 비공개 게시글 로그
            if (post.visibility == 'category') {
              Logger.log('🔒 비공개 게시글 발견: ${post.title}');
              Logger.log('   작성자: ${post.author} (${post.userId})');
              Logger.log('   현재 사용자: ${user?.uid ?? "로그인 안 함"}');
              Logger.log('   허용된 사용자: ${post.allowedUserIds}');
              Logger.log('   접근 가능: ${user != null && (post.userId == user.uid || post.allowedUserIds.contains(user.uid))}');
            }
            
            return post;
          }).toList();
          
          // 클라이언트 측 필수 필터링: 비공개 게시글 차단
          if (user != null) {
            final filteredPosts = posts.where((post) {
              // visibility 필드가 없으면 전체 공개로 간주
              final visibility = post.visibility;
              
              // 전체 공개 게시글은 모두 표시
              if (visibility == 'public' || visibility.isEmpty) {
                return true;
              }
              
              // 카테고리별 비공개 게시글 - 매우 엄격하게 필터링
              if (visibility == 'category') {
                // 1. 작성자 본인인 경우만 무조건 표시
                if (post.userId == user.uid) {
                  Logger.log('✅ 작성자 본인: ${post.title}');
                  return true;
                }
                
                // 2. allowedUserIds 배열이 없거나 비어있으면 차단
                if (post.allowedUserIds.isEmpty) {
                  Logger.log('❌ allowedUserIds 비어있음: ${post.title}');
                  return false;
                }
                
                // 3. allowedUserIds에 정확히 포함되어 있는지 확인
                final isAllowed = post.allowedUserIds.contains(user.uid);
                
                if (isAllowed) {
                  Logger.log('✅ 접근 허용: ${post.title}');
                  Logger.log('   - 현재 사용자: ${user.uid}');
                  Logger.log('   - 허용된 사용자: ${post.allowedUserIds}');
                } else {
                  Logger.log('❌ 접근 차단: ${post.title}');
                  Logger.log('   - 현재 사용자: ${user.uid}');
                  Logger.log('   - 허용된 사용자: ${post.allowedUserIds}');
                  Logger.log('   - 작성자: ${post.userId}');
                }
                
                return isAllowed;
              }
              
              // 알 수 없는 visibility 값은 차단
              Logger.log('⚠️  알 수 없는 visibility: ${visibility} - ${post.title}');
              return false;
            }).toList();
            
            Logger.log('✅ 필터링 후 게시글 수: ${filteredPosts.length} (전체: ${posts.length})');
            return filteredPosts;
          }
          
          // 로그인하지 않은 경우 전체 공개 게시글만 표시
          Logger.log('⚠️  로그인하지 않음 - 전체 공개만 표시');
          return posts.where((post) => post.visibility == 'public' || post.visibility.isEmpty).toList();
        });
  }

  // 특정 게시글 가져오기
  Future<Post?> getPostById(String postId) async {
    try {
      final doc = await _firestore.collection('posts').doc(postId).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      Logger.log(
        "PostService.getPostById - 게시글 데이터: ${data['id']} | 작성자: ${data['authorNickname']} | 국적: ${data['authorNationality'] ?? '없음'}",
      );

      return Post(
        id: doc.id,
        title: data['title'] ?? '',
        content: data['content'] ?? '',
        author: data['authorNickname'] ?? '익명',
        authorNationality: data['authorNationality'] ?? '알 수 없음',
        authorPhotoURL: data['authorPhotoURL'] ?? '',
        createdAt:
            data['createdAt'] != null
                ? (data['createdAt'] as Timestamp).toDate()
                : DateTime.now(),
        userId: data['userId'] ?? '',
        commentCount: data['commentCount'] ?? 0,
        likes: data['likes'] ?? 0,
        likedBy: List<String>.from(data['likedBy'] ?? []),
        imageUrls: List<String>.from(data['imageUrls'] ?? []),
        visibility: data['visibility'] ?? 'public',
        isAnonymous: data['isAnonymous'] ?? false,
        visibleToCategoryIds: List<String>.from(data['visibleToCategoryIds'] ?? []),
        allowedUserIds: List<String>.from(data['allowedUserIds'] ?? []),
      );
    } catch (e) {
      Logger.error('게시글 조회 오류: $e');
      return null;
    }
  }

  Future<bool> toggleLike(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('좋아요 실패: 로그인이 필요합니다.');
        return false;
      }

      // 트랜잭션 대신 더 간단한 접근 방식 사용
      // 게시글 문서 레퍼런스
      final postRef = _firestore.collection('posts').doc(postId);

      // 게시글 데이터 가져오기
      final postDoc = await postRef.get();
      if (!postDoc.exists) {
        Logger.log('게시글이 존재하지 않습니다: $postId');
        return false;
      }

      // 현재 좋아요 상태 파악
      final data = postDoc.data()!;
      List<dynamic> likedBy = List.from(data['likedBy'] ?? []);
      bool hasLiked = likedBy.contains(user.uid);

      final postTitle = data['title'] ?? '';
      final authorId = data['userId'];

      Logger.log('현재 좋아요 상태: $hasLiked, 사용자 ID: ${user.uid}, 게시글 ID: $postId');

      // 좋아요 토글
      if (hasLiked) {
        // 좋아요 취소
        likedBy.remove(user.uid);
        await postRef.update({
          'likedBy': likedBy,
          'likes': FieldValue.increment(-1),
        });
        Logger.log('좋아요 취소 완료');
      } else {
        // 좋아요 추가
        likedBy.add(user.uid);
        await postRef.update({
          'likedBy': likedBy,
          'likes': FieldValue.increment(1),
        });
        Logger.log('좋아요 추가 완료');

        Logger.log('❤️ 좋아요 추가 - 알림 전송 확인 중');
        Logger.log('   게시글 작성자: $authorId');
        Logger.log('   좋아요 누른 사람: ${user.uid}');
        Logger.log('   게시글 제목: $postTitle');

        // 좋아요 알림 전송 (자신의 게시글이 아닌 경우에만)
        if (authorId != null && authorId != user.uid) {
          // 사용자 정보 가져오기
          final userDoc =
              await _firestore.collection('users').doc(user.uid).get();
          final userData = userDoc.data();
          final nickname = userData?['nickname'] ?? '익명';

          Logger.log('🔔 알림 전송 시작...');
          // 좋아요 알림 전송
          final notificationSent = await _notificationService.sendNewLikeNotification(
            postId,
            postTitle,
            authorId,
            nickname,
            user.uid,
          );
          Logger.log(notificationSent ? '✅ 알림 전송 성공' : '❌ 알림 전송 실패');
        } else {
          Logger.log('⏭️ 알림 전송 건너뜀 (본인 게시글)');
        }
      }

      return true;
    } catch (e) {
      Logger.error('좋아요 기능 오류: $e');
      return false;
    }
  }

  // 현재 사용자가 좋아요를 눌렀는지 확인
  // 주의: 이 함수는 더 이상 사용되지 않습니다. Post 객체의 likedBy를 직접 사용하세요.
  @Deprecated('Post 객체의 likedBy 리스트를 직접 사용하세요')
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
      // 권한 오류는 정상 - 비공개 게시글에 접근할 수 없음
      return false;
    }
  }

  // 게시글 조회수 증가
  Future<void> incrementViewCount(String postId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        Logger.log('🔍 조회수 증가 실패: 로그인되지 않은 사용자');
        return;
      }

      // 게시글 정보 먼저 가져오기
      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (!postDoc.exists) {
        Logger.log('🔍 조회수 증가 실패: 게시글이 존재하지 않음 ($postId)');
        return;
      }

      final postData = postDoc.data()!;
      final authorId = postData['userId'] as String?;
      final currentUserId = user.uid;

      Logger.log('🔍 조회수 증가 시도:');
      Logger.log('   - 게시글 ID: $postId');
      Logger.log('   - 작성자 ID: $authorId');
      Logger.log('   - 현재 사용자 ID: $currentUserId');
      Logger.log('   - 자신의 글인가: ${authorId == currentUserId}');

      // 조회수 증가 (자신의 글이든 다른 사람의 글이든 모두 증가)
      final postRef = _firestore.collection('posts').doc(postId);
      await postRef.update({
        'viewCount': FieldValue.increment(1),
      });

      Logger.log('✅ 조회수 증가 완료: $postId');
    } catch (e) {
      Logger.error('❌ 조회수 증가 오류: $e');
      Logger.error('스택 트레이스: ${StackTrace.current}');
    }
  }

  // 게시글 삭제
  Future<bool> deletePost(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('삭제 실패: 로그인이 필요합니다.');
        return false;
      }

      // 게시글 문서 가져오기
      final postDoc = await _firestore.collection('posts').doc(postId).get();

      // 문서가 없는 경우
      if (!postDoc.exists) {
        Logger.error('삭제 실패: 게시글이 존재하지 않습니다.');
        return false;
      }

      final data = postDoc.data()!;

      // 현재 사용자가 작성자인지 확인
      if (data['userId'] != user.uid) {
        Logger.error('삭제 실패: 게시글 작성자만 삭제할 수 있습니다.');
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

      Logger.log('게시글 삭제 성공: $postId');
      
      // 캐시 무효화 (게시글이 삭제되었으므로 캐시 삭제)
      if (CacheFeatureFlags.isPostCacheEnabled) {
        _cache.invalidate(key: postId);
        Logger.log('💾 게시글 캐시 무효화 (게시글 삭제)');
      }
      
      return true;
    } catch (e) {
      Logger.error('게시글 삭제 오류: $e');
      return false;
    }
  }

  // 캐시된 게시글 가져오기 (초기 로딩용)
  /// 캐시에서 게시글 목록을 가져옵니다.
  /// 캐시가 없으면 빈 리스트를 반환합니다.
  /// UI는 이 데이터를 먼저 표시하고, Stream을 통해 최신 데이터로 업데이트합니다.
  Future<List<Post>> getCachedPosts({String visibility = 'public'}) async {
    if (!CacheFeatureFlags.isPostCacheEnabled) {
      return [];
    }
    
    try {
      return await _cache.getPosts(visibility: visibility);
    } catch (e) {
      Logger.error('캐시된 게시글 가져오기 실패: $e');
      return [];
    }
  }

  // 게시글 스트림 가져오기
  Stream<List<Post>> getPostsStream() {
    final user = _auth.currentUser;
    
    return _firestore
        .collection('posts')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
      Logger.log('📊 [getPostsStream] Firestore에서 받은 게시글 수: ${snapshot.docs.length}');
      
      final posts = snapshot.docs.map((doc) {
        try {
          final data = doc.data();
          final post = Post(
            id: doc.id,
            title: data['title'] ?? '제목 없음',
            content: data['content'] ?? '내용 없음',
            author: data['authorNickname'] ?? '알 수 없음',
            authorNationality: data['authorNationality'] ?? '',
            authorPhotoURL: data['authorPhotoURL'] ?? '',
            category: data['category'] ?? '일반',
            createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
            userId: data['userId'] ?? '',
            commentCount: data['commentCount'] ?? 0,
            likes: data['likes'] ?? 0,
            viewCount: data['viewCount'] ?? 0,
            likedBy: List<String>.from(data['likedBy'] ?? []),
            imageUrls: List<String>.from(data['imageUrls'] ?? []),
            visibility: data['visibility'] ?? 'public',
            isAnonymous: data['isAnonymous'] ?? false,
            visibleToCategoryIds: List<String>.from(data['visibleToCategoryIds'] ?? []),
            allowedUserIds: List<String>.from(data['allowedUserIds'] ?? []),
          );
          
          // 비공개 게시글 로그
          if (post.visibility == 'category') {
            Logger.log('🔒 비공개 게시글 발견: ${post.title}');
            Logger.log('   작성자: ${post.author} (${post.userId})');
            Logger.log('   현재 사용자: ${user?.uid ?? "로그인 안 함"}');
            Logger.log('   허용된 사용자: ${post.allowedUserIds}');
          }
          
          return post;
        } catch (e) {
          Logger.error('게시글 파싱 오류: $e');
          // 오류 발생 시 기본 Post 객체 반환
          return Post(
            id: doc.id,
            title: '제목 없음',
            content: '내용을 불러올 수 없습니다.',
            author: '알 수 없음',
            category: '일반',
            createdAt: DateTime.now(),
            userId: '',
            imageUrls: [],
            visibility: 'public',
            isAnonymous: false,
            visibleToCategoryIds: [],
            likes: 0,
          );
        }
      }).toList();

      // 1단계: 차단된 사용자의 게시물 필터링
      final nonBlockedPosts = await ContentFilterService.filterPosts(posts);
      
      // 2단계: 비공개 게시글 필터링 (매우 중요!)
      if (user != null) {
        final visiblePosts = nonBlockedPosts.where((post) {
          final visibility = post.visibility;
          
          // 전체 공개 게시글은 모두 표시
          if (visibility == 'public' || visibility.isEmpty) {
            return true;
          }
          
          // 카테고리별 비공개 게시글 - 엄격하게 필터링
          if (visibility == 'category') {
            // 1. 작성자 본인
            if (post.userId == user.uid) {
              Logger.log('✅ [getPostsStream] 작성자 본인: ${post.title}');
              return true;
            }
            
            // 2. allowedUserIds 비어있으면 차단
            if (post.allowedUserIds.isEmpty) {
              Logger.log('❌ [getPostsStream] allowedUserIds 비어있음: ${post.title}');
              return false;
            }
            
            // 3. allowedUserIds에 포함 여부 확인
            final isAllowed = post.allowedUserIds.contains(user.uid);
            
            if (isAllowed) {
              Logger.log('✅ [getPostsStream] 접근 허용: ${post.title}');
            } else {
              Logger.log('❌ [getPostsStream] 접근 차단: ${post.title}');
              Logger.log('   - 현재 사용자: ${user.uid}');
              Logger.log('   - 허용된 사용자: ${post.allowedUserIds}');
              Logger.log('   - 작성자: ${post.userId}');
            }
            
            return isAllowed;
          }
          
          // 알 수 없는 visibility는 차단
          Logger.log('⚠️  [getPostsStream] 알 수 없는 visibility: ${visibility}');
          return false;
        }).toList();
        
        Logger.log('✅ [getPostsStream] 필터링 후 게시글 수: ${visiblePosts.length} (전체: ${posts.length})');
        
        // 캐시 업데이트 (백그라운드, 실패해도 무시)
        if (CacheFeatureFlags.isPostCacheEnabled) {
          unawaited(_cache.savePosts(visiblePosts, visibility: 'public'));
        }
        
        return visiblePosts;
      }
      
      // 로그인하지 않은 경우 전체 공개만
      Logger.log('⚠️  [getPostsStream] 로그인하지 않음 - 전체 공개만 표시');
      final publicPosts = nonBlockedPosts.where((post) => post.visibility == 'public' || post.visibility.isEmpty).toList();
      
      // 캐시 업데이트 (백그라운드, 실패해도 무시)
      if (CacheFeatureFlags.isPostCacheEnabled) {
        unawaited(_cache.savePosts(publicPosts, visibility: 'public'));
      }
      
      return publicPosts;
    });
  }

  // 현재 사용자가 게시글 작성자인지 확인
  // 주의: 이 함수는 더 이상 사용되지 않습니다. Post 객체의 userId를 직접 사용하세요.
  @Deprecated('Post 객체의 userId를 직접 사용하세요')
  Future<bool> isCurrentUserAuthor(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final postDoc = await _firestore.collection('posts').doc(postId).get();
      if (!postDoc.exists) return false;

      final data = postDoc.data()!;
      return data['userId'] == user.uid;
    } catch (e) {
      // 권한 오류는 정상 - 비공개 게시글에 접근할 수 없음
      return false;
    }
  }

  // 게시글 검색 (카테고리별)
  Future<List<Post>> searchPosts(String query, {String? category}) async {
    try {
      if (query.isEmpty) return [];

      final lowercaseQuery = query.toLowerCase();
      
      // 기본 쿼리
      Query<Map<String, dynamic>> queryRef = _firestore
          .collection('posts')
          .orderBy('createdAt', descending: true);

      // 카테고리 필터 추가
      if (category != null && category.isNotEmpty) {
        queryRef = queryRef.where('category', isEqualTo: category);
      }

      final snapshot = await queryRef.get();
      
      return snapshot.docs
          .map((doc) {
            try {
              final data = doc.data();
              
              // 검색어와 일치하는지 확인
              final title = (data['title'] as String? ?? '').toLowerCase();
              final content = (data['content'] as String? ?? '').toLowerCase();
              final author = (data['authorNickname'] as String? ?? '').toLowerCase();
              
              if (title.contains(lowercaseQuery) ||
                  content.contains(lowercaseQuery) ||
                  author.contains(lowercaseQuery)) {
                return Post(
                  id: doc.id,
                  title: data['title'] ?? '제목 없음',
                  content: data['content'] ?? '내용 없음',
                  author: data['authorNickname'] ?? '알 수 없음',
                  authorNationality: data['authorNationality'] ?? '',
                  authorPhotoURL: data['authorPhotoURL'] ?? '',
                  category: data['category'] ?? '일반',
                  createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                  userId: data['userId'] ?? '',
                  commentCount: data['commentCount'] ?? 0,
                  likes: data['likes'] ?? 0,
                  likedBy: List<String>.from(data['likedBy'] ?? []),
                  imageUrls: List<String>.from(data['imageUrls'] ?? []),
                  visibility: data['visibility'] ?? 'public',
                  isAnonymous: data['isAnonymous'] ?? false,
                  visibleToCategoryIds: List<String>.from(data['visibleToCategoryIds'] ?? []),
                  allowedUserIds: List<String>.from(data['allowedUserIds'] ?? []),
                );
              }
              return null;
            } catch (e) {
              Logger.error('게시글 검색 파싱 오류: $e');
              return null;
            }
          })
          .where((post) => post != null)
          .cast<Post>()
          .toList();
    } catch (e) {
      Logger.error('게시글 검색 오류: $e');
      return [];
    }
  }

  // 게시글 저장 상태 확인
  Future<bool> isPostSaved(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final savedDoc = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('savedPosts')
          .doc(postId)
          .get();

      return savedDoc.exists;
    } catch (e) {
      Logger.error('게시글 저장 상태 확인 오류: $e');
      return false;
    }
  }

  // 게시글 저장/저장 취소 토글
  Future<bool> toggleSavePost(String postId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final savedPostRef = _firestore
          .collection('users')
          .doc(user.uid)
          .collection('savedPosts')
          .doc(postId);

      final savedDoc = await savedPostRef.get();

      if (savedDoc.exists) {
        // 이미 저장된 게시글이면 저장 취소
        await savedPostRef.delete();
        Logger.log('게시글 저장 취소: $postId');
        return false;
      } else {
        // 저장되지 않은 게시글이면 저장
        await savedPostRef.set({
          'postId': postId,
          'savedAt': FieldValue.serverTimestamp(),
        });
        Logger.log('게시글 저장: $postId');
        return true;
      }
    } catch (e) {
      Logger.error('게시글 저장 토글 오류: $e');
      return false;
    }
  }

  // 사용자가 저장한 게시글 목록 스트림
  Stream<List<Post>> getSavedPosts() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.value([]);
    }

    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('savedPosts')
        .orderBy('savedAt', descending: true)
        .snapshots()
        .asyncMap((savedSnapshot) async {
      List<Post> savedPosts = [];

      for (var savedDoc in savedSnapshot.docs) {
        try {
          final postId = savedDoc.data()['postId'] as String;
          final postDoc = await _firestore.collection('posts').doc(postId).get();

          if (postDoc.exists) {
            final data = postDoc.data()!;
            savedPosts.add(Post(
              id: postDoc.id,
              title: data['title'] ?? '제목 없음',
              content: data['content'] ?? '내용 없음',
              author: data['authorNickname'] ?? '알 수 없음',
              authorNationality: data['authorNationality'] ?? '',
              authorPhotoURL: data['authorPhotoURL'] ?? '',
              category: data['category'] ?? '일반',
              createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
              userId: data['userId'] ?? '',
              commentCount: data['commentCount'] ?? 0,
              likes: data['likes'] ?? 0,
              viewCount: data['viewCount'] ?? 0,
              likedBy: List<String>.from(data['likedBy'] ?? []),
              imageUrls: List<String>.from(data['imageUrls'] ?? []),
              visibility: data['visibility'] ?? 'public',
              isAnonymous: data['isAnonymous'] ?? false,
              visibleToCategoryIds: List<String>.from(data['visibleToCategoryIds'] ?? []),
              allowedUserIds: List<String>.from(data['allowedUserIds'] ?? []),
            ));
          }
        } catch (e) {
          Logger.error('저장된 게시글 로드 오류: $e');
        }
      }

      return savedPosts;
    });
  }

  // 사용자가 저장한 게시글 수 가져오기
  Future<int> getSavedPostCount() async {
    try {
      final user = _auth.currentUser;
      if (user == null) return 0;

      final snapshot = await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('savedPosts')
          .get();

      return snapshot.docs.length;
    } catch (e) {
      Logger.error('저장된 게시글 수 조회 오류: $e');
      return 0;
    }
  }

  /// 특정 사용자의 모든 게시물에서 작성자 정보 업데이트
  Future<bool> updateAuthorInfoInAllPosts(
    String userId,
    String newNickname,
    String? newPhotoUrl,
  ) async {
    try {
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.log('🔄 게시물 배치 업데이트 시작');
      Logger.log('   - userId: $userId');
      Logger.log('   - newNickname: $newNickname');
      Logger.log('   - newPhotoUrl: ${newPhotoUrl ?? "없음"}');

      // 1. 해당 사용자가 작성한 모든 게시물 조회
      final postsQuery = await _firestore
          .collection('posts')
          .where('userId', isEqualTo: userId)
          .get();

      Logger.log('   - 찾은 게시물: ${postsQuery.docs.length}개');

      if (postsQuery.docs.isEmpty) {
        Logger.log('   ⚠️  업데이트할 게시물이 없습니다.');
        return true;
      }

      // 2. 배치 작업 준비 (Firestore는 배치당 최대 500개)
      final batches = <WriteBatch>[];
      var currentBatch = _firestore.batch();
      var operationCount = 0;
      const maxOperationsPerBatch = 500;

      // 3. 각 게시물의 작성자 정보 업데이트
      for (final doc in postsQuery.docs) {
        if (operationCount >= maxOperationsPerBatch) {
          batches.add(currentBatch);
          currentBatch = _firestore.batch();
          operationCount = 0;
          Logger.log('   → 새 배치 생성 (배치 ${batches.length + 1})');
        }

        final postRef = _firestore.collection('posts').doc(doc.id);

        final updateData = <String, dynamic>{
          'authorNickname': newNickname,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        // photoURL이 있는 경우에만 추가
        if (newPhotoUrl != null && newPhotoUrl.isNotEmpty) {
          updateData['authorPhotoURL'] = newPhotoUrl;
        }

        currentBatch.update(postRef, updateData);
        operationCount++;
      }

      // 마지막 배치 추가
      if (operationCount > 0) {
        batches.add(currentBatch);
      }

      // 4. 모든 배치 실행
      Logger.log('   💾 총 ${batches.length}개의 배치 커밋 시작...');
      int successCount = 0;
      int failCount = 0;

      for (int i = 0; i < batches.length; i++) {
        try {
          await batches[i].commit();
          successCount++;
          Logger.log('   ✅ 배치 ${i + 1}/${batches.length} 커밋 완료');
        } catch (e) {
          failCount++;
          Logger.error('   ❌ 배치 ${i + 1}/${batches.length} 커밋 실패: $e');
        }
      }

      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.log('✅ 게시물 배치 업데이트 완료!');
      Logger.log('   - 총 게시물: ${postsQuery.docs.length}개');
      Logger.log('   - 성공한 배치: $successCount/${batches.length}');
      if (failCount > 0) {
        Logger.error('   ⚠️  실패한 배치: $failCount/${batches.length}');
      }
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

      return failCount == 0;
    } catch (e, stackTrace) {
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      Logger.error('❌ 게시물 배치 업데이트 실패!');
      Logger.error('   에러: $e');
      Logger.log('   스택 트레이스: $stackTrace');
      Logger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      return false;
    }
  }
}
