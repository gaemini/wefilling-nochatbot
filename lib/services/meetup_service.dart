// lib/services/meetup_service.dart
// 모임 관련 CRUD 작업 처리
// 모임 생성, 참여, 취소 기능
// 날짜별 모임 조회 및 필터링
// 날짜 관련 유틸리티 함수 제공

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/meetup.dart';
import '../models/meetup_participant.dart';
import '../constants/app_constants.dart';
import 'notification_service.dart';
import 'content_filter_service.dart';
import 'dart:io';

class MeetupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();
  
  // Firestore 인스턴스 getter 추가
  FirebaseFirestore get firestore => _firestore;

  // 현재 주의 월요일부터 일요일까지 날짜 계산
  List<DateTime> getWeekDates() {
    final DateTime now = DateTime.now();
    
    // 현재 주의 월요일 찾기 (월요일=1, 일요일=7)
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final DateTime startOfWeekDay = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    
    final List<DateTime> weekDates = [];
    
    // 월요일부터 일요일까지 7일 생성
    for (int i = 0; i < 7; i++) {
      weekDates.add(startOfWeekDay.add(Duration(days: i)));
    }

    return weekDates;
  }

  // 날짜 포맷 문자열 반환 (요일도 포함)
  String getFormattedDate(DateTime date) {
    final List<String> weekdayNames = ['M', 'Tu', 'W', 'Th', 'F', 'Sa', 'Su'];
    final int weekdayIndex = date.weekday - 1; // 0: 월요일, 6: 일요일
    return '${date.month}월 ${date.day}일 (${weekdayNames[weekdayIndex]})';
  }

  // 모임 생성
  Future<bool> createMeetup({
    required String title,
    required String description,
    required String location,
    required String time,
    required int maxParticipants,
    required DateTime date,
    String category = '기타', // 카테고리 매개변수 추가
    String thumbnailContent = '', // 썸네일 텍스트 컨텐츠 추가
    File? thumbnailImage, // 썸네일 이미지 파일 추가
    String visibility = 'public', // 공개 범위
    List<String> visibleToCategoryIds = const [], // 특정 카테고리에만 공개
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // 사용자 데이터 가져오기
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final userData = userDoc.data();
      final nickname = userData?['nickname'] ?? '익명';
      final nationality = userData?['nationality'] ?? ''; // 국적 가져오기
      final photoURL = userData?['photoURL'] ?? user.photoURL ?? ''; // 프로필 사진 URL 가져오기

      // 모임 생성 시간
      final now = FieldValue.serverTimestamp();

      // 모임 데이터 생성
      final meetupData = {
        'userId': user.uid,
        'hostNickname': nickname,
        'hostPhotoURL': photoURL, // 주최자 프로필 사진 URL 추가
        'title': title,
        'description': description,
        'location': location,
        'time': time,
        'maxParticipants': maxParticipants,
        'currentParticipants': 1, // 주최자 포함
        'participants': [user.uid], // 주최자 ID
        'date': date,
        'createdAt': now,
        'updatedAt': now,
        'category': category, // 카테고리 필드 추가
        'hostNationality': nationality, // 주최자 국적 추가
        'thumbnailContent': thumbnailContent, // 썸네일 텍스트 컨텐츠 추가
        'visibility': visibility, // 공개 범위 추가
        'visibleToCategoryIds': visibleToCategoryIds, // 특정 카테고리 공개 추가
      };

      // Firestore에 저장
      final docRef = await _firestore.collection('meetups').add(meetupData);

      // 이미지 업로드 처리
      if (thumbnailImage != null) {
        try {
          final storage = FirebaseStorage.instance;
          final Reference storageRef = storage.ref().child(
            'meetup_thumbnails/${docRef.id}',
          );

          await storageRef.putFile(thumbnailImage);
          final imageUrl = await storageRef.getDownloadURL();

          // 이미지 URL 업데이트
          await docRef.update({'thumbnailImageUrl': imageUrl});
        } catch (e) {
          print('썸네일 이미지 업로드 오류: $e');
        }
      }

      return true;
    } catch (e) {
      print('모임 생성 오류: $e');
      return false;
    }
  }

  // 요일별 모임 가져오기 - 모든 모임 표시
  Stream<List<Meetup>> getMeetupsByDay(int dayIndex) {
    // 해당 요일의 날짜 계산 (현재 날짜 기준)
    final List<DateTime> weekDates = getWeekDates();
    final DateTime targetDate = weekDates[dayIndex];

    // 날짜 범위 설정 (해당 날짜의 00:00:00부터 23:59:59까지)
    final startOfDay = DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
    );
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));

    return _firestore
        .collection('meetups')
        .where('date', isGreaterThanOrEqualTo: startOfDay)
        .where('date', isLessThanOrEqualTo: endOfDay)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) {
            final data = doc.data();

            // Timestamp에서 DateTime으로 변환
            DateTime meetupDate;
            if (data['date'] is Timestamp) {
              meetupDate = (data['date'] as Timestamp).toDate();
            } else {
              // 기본값으로 현재 날짜 사용
              meetupDate = startOfDay;
            }

            return Meetup(
              id: doc.id, // ID를 문자열로 직접 사용
              title: data['title'] ?? '',
              description: data['description'] ?? '',
              location: data['location'] ?? '',
              time: data['time'] ?? '',
              maxParticipants: data['maxParticipants'] ?? 0,
              currentParticipants: data['currentParticipants'] ?? 1,
              host: data['hostNickname'] ?? '익명',
              hostNationality:
                  data['hostNickname'] == 'dev99'
                      ? '한국'
                      : (data['hostNationality'] ??
                          ''), // 테스트 목적으로 dev99인 경우 한국으로 설정
              hostPhotoURL: data['hostPhotoURL'] ?? '', // 주최자 프로필 사진 추가
              imageUrl:
                  data['thumbnailImageUrl'] ?? AppConstants.DEFAULT_IMAGE_URL,
              thumbnailContent: data['thumbnailContent'] ?? '',
              thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
              date: meetupDate,
              category: data['category'] ?? '기타', // 카테고리 필드 추가
              userId: data['userId'], // 모임 주최자 ID 추가
              hostNickname: data['hostNickname'], // 주최자 닉네임 추가
              visibility: data['visibility'] ?? 'public', // 공개 범위 추가
              visibleToCategoryIds: List<String>.from(data['visibleToCategoryIds'] ?? []), // 특정 카테고리 공개 추가
            );
          }).toList();
        });
  }

  // 카테고리별 모임 가져오기 (새로운 메서드)
  Stream<List<Meetup>> getMeetupsByCategory(String category) {
    // 현재 날짜 이후의 모임만 가져오기
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 모든 모임 가져오기인 경우
    if (category == '전체') {
      return _firestore
          .collection('meetups')
          .where('date', isGreaterThanOrEqualTo: today)
          .orderBy('date', descending: false)
          .snapshots()
          .asyncMap((snapshot) async {
            final meetups = _convertToMeetups(snapshot);
            return await ContentFilterService.filterMeetups(meetups);
          });
    }

    // 특정 카테고리 모임 가져오기
    return _firestore
        .collection('meetups')
        .where('category', isEqualTo: category)
        .where('date', isGreaterThanOrEqualTo: today)
        .orderBy('date', descending: false)
        .snapshots()
        .asyncMap((snapshot) async {
          final meetups = _convertToMeetups(snapshot);
          return await ContentFilterService.filterMeetups(meetups);
        });
  }

  // 오늘의 모임 가져오기
  Stream<List<Meetup>> getTodayMeetups() {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));

    return _firestore
        .collection('meetups')
        .where('date', isGreaterThanOrEqualTo: startOfDay)
        .where('date', isLessThanOrEqualTo: endOfDay)
        .snapshots()
        .asyncMap((snapshot) async {
          final meetups = _convertToMeetups(snapshot);
          return await ContentFilterService.filterMeetups(meetups);
        });
  }

  // Firestore 문서를 Meetup 객체 리스트로 변환하는 헬퍼 메서드
  List<Meetup> _convertToMeetups(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;

      // Timestamp에서 DateTime으로 변환
      DateTime meetupDate;
      if (data['date'] is Timestamp) {
        meetupDate = (data['date'] as Timestamp).toDate();
      } else {
        meetupDate = DateTime.now();
      }

      return Meetup(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        location: data['location'] ?? '',
        time: data['time'] ?? '',
        maxParticipants: data['maxParticipants'] ?? 0,
        currentParticipants: data['currentParticipants'] ?? 1,
        host: data['hostNickname'] ?? '익명',
        hostNationality:
            data['hostNickname'] == 'dev99'
                ? '한국'
                : (data['hostNationality'] ?? ''), // 테스트 목적으로 dev99인 경우 한국으로 설정
        imageUrl: data['thumbnailImageUrl'] ?? AppConstants.DEFAULT_IMAGE_URL,
        thumbnailContent: data['thumbnailContent'] ?? '',
        thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
        date: meetupDate,
        category: data['category'] ?? '기타',
        userId: data['userId'], // 모임 주최자 ID 추가
        hostNickname: data['hostNickname'], // 주최자 닉네임 추가
      );
    }).toList();
  }

  // 특정 ID의 모임 가져오기
  Future<Meetup?> getMeetupById(String meetupId) async {
    try {
      final doc = await _firestore.collection('meetups').doc(meetupId).get();

      if (!doc.exists || doc.data() == null) {
        return null;
      }

      final data = doc.data()!;

      // Timestamp에서 DateTime으로 변환
      DateTime meetupDate;
      if (data['date'] is Timestamp) {
        meetupDate = (data['date'] as Timestamp).toDate();
      } else {
        // 기본값으로 현재 날짜 사용
        meetupDate = DateTime.now();
      }

      return Meetup(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        location: data['location'] ?? '',
        time: data['time'] ?? '',
        maxParticipants: data['maxParticipants'] ?? 0,
        currentParticipants: data['currentParticipants'] ?? 1,
        host: data['hostNickname'] ?? '익명',
        hostNationality:
            data['hostNickname'] == 'dev99'
                ? '한국'
                : (data['hostNationality'] ?? ''), // 테스트 목적으로 dev99인 경우 한국으로 설정
        imageUrl: data['thumbnailImageUrl'] ?? AppConstants.DEFAULT_IMAGE_URL,
        thumbnailContent: data['thumbnailContent'] ?? '',
        thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
        date: meetupDate,
        category: data['category'] ?? '기타', // 카테고리 필드 추가
        userId: data['userId'], // 모임 주최자 ID 추가
        hostNickname: data['hostNickname'], // 주최자 닉네임 추가
      );
    } catch (e) {
      print('모임 정보 불러오기 오류: $e');
      return null;
    }
  }

  // 모임 목록 가져오기 (메모리 기반) - 예시 모임 데이터 제거
  List<List<Meetup>> getMeetupsByDayFromMemory() {
    // 현재 날짜 기준 일주일 날짜 계산
    // final List<DateTime> weekDates = getWeekDates();

    // 예시 데이터를 제거하고 빈 목록 반환 (실제 데이터는 Firebase에서 가져옴)
    return List.generate(7, (dayIndex) {
      // final DateTime dayDate = weekDates[dayIndex];
      return []; // 빈 배열 반환 (예시 데이터 삭제)
    });
  }

  // 모임 검색 메서드 추가
  Stream<List<Meetup>> searchMeetups(String query) {
    if (query.isEmpty) {
      // 빈 검색어인 경우 모든 모임 반환
      return getMeetupsByCategory('전체');
    }

    // 소문자로 변환하여 대소문자 구분 없이 검색
    final lowercaseQuery = query.toLowerCase();

    // 현재 날짜 이후의 모임 중에서 검색
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    return _firestore
        .collection('meetups')
        .where('date', isGreaterThanOrEqualTo: today)
        .orderBy('date', descending: false)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) {
                final data = doc.data();

                // 검색어와 일치하는지 확인 (제목, 내용, 위치, 호스트 닉네임)
                final title = (data['title'] as String? ?? '').toLowerCase();
                final description =
                    (data['description'] as String? ?? '').toLowerCase();
                final location =
                    (data['location'] as String? ?? '').toLowerCase();
                final hostNickname = (data['hostNickname'] as String? ?? '').toLowerCase();

                // 제목, 내용, 위치, 호스트 닉네임에서 검색
                if (title.contains(lowercaseQuery) ||
                    description.contains(lowercaseQuery) ||
                    location.contains(lowercaseQuery) ||
                    hostNickname.contains(lowercaseQuery)) {
                  // Timestamp에서 DateTime으로 변환
                  DateTime meetupDate;
                  if (data['date'] is Timestamp) {
                    meetupDate = (data['date'] as Timestamp).toDate();
                  } else {
                    meetupDate = DateTime.now();
                  }

                  return Meetup(
                    id: doc.id,
                    title: data['title'] ?? '',
                    description: data['description'] ?? '',
                    location: data['location'] ?? '',
                    time: data['time'] ?? '',
                    maxParticipants: data['maxParticipants'] ?? 0,
                    currentParticipants: data['currentParticipants'] ?? 1,
                    host: data['hostNickname'] ?? '익명',
                    hostNationality:
                        data['hostNickname'] == 'dev99'
                            ? '한국'
                            : (data['hostNationality'] ??
                                ''), // 테스트 목적으로 dev99인 경우 한국으로 설정
                    imageUrl:
                        data['thumbnailImageUrl'] ??
                        AppConstants.DEFAULT_IMAGE_URL,
                    thumbnailContent: data['thumbnailContent'] ?? '',
                    thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
                    date: meetupDate,
                    category: data['category'] ?? '기타',
                    userId: data['userId'], // 모임 주최자 ID 추가
                    hostNickname: data['hostNickname'], // 주최자 닉네임 추가
                  );
                } else {
                  return null; // 검색 조건에 맞지 않으면 null 반환
                }
              })
              .whereType<Meetup>() // null이 아닌 항목만 필터링
              .toList();
        });
  }

  // 모임 검색 (Future 버전 - SearchResultPage용)
  Future<List<Meetup>> searchMeetupsAsync(String query) async {
    try {
      if (query.isEmpty) return [];

      final lowercaseQuery = query.toLowerCase();
      
      // 현재 날짜 이후의 모임 중에서 검색
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final snapshot = await _firestore
          .collection('meetups')
          .where('date', isGreaterThanOrEqualTo: today)
          .orderBy('date', descending: false)
          .get();

      return snapshot.docs
          .map((doc) {
            try {
              final data = doc.data();

              // 검색어와 일치하는지 확인 (제목, 설명, 위치, 호스트 닉네임)
              final title = (data['title'] as String? ?? '').toLowerCase();
              final description = (data['description'] as String? ?? '').toLowerCase();
              final location = (data['location'] as String? ?? '').toLowerCase();
              final hostNickname = (data['hostNickname'] as String? ?? '').toLowerCase();

              if (title.contains(lowercaseQuery) ||
                  description.contains(lowercaseQuery) ||
                  location.contains(lowercaseQuery) ||
                  hostNickname.contains(lowercaseQuery)) {
                
                // Timestamp에서 DateTime으로 변환
                DateTime meetupDate;
                if (data['date'] is Timestamp) {
                  meetupDate = (data['date'] as Timestamp).toDate();
                } else {
                  meetupDate = DateTime.now();
                }

                return Meetup(
                  id: doc.id,
                  title: data['title'] ?? '',
                  description: data['description'] ?? '',
                  location: data['location'] ?? '',
                  time: data['time'] ?? '',
                  maxParticipants: data['maxParticipants'] ?? 0,
                  currentParticipants: data['currentParticipants'] ?? 1,
                  host: data['hostNickname'] ?? '익명',
                  hostNationality: data['hostNationality'] ?? '',
                  imageUrl: data['thumbnailImageUrl'] ?? AppConstants.DEFAULT_IMAGE_URL,
                  thumbnailContent: data['thumbnailContent'] ?? '',
                  thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
                  date: meetupDate,
                  category: data['category'] ?? '기타',
                  userId: data['userId'], // 모임 주최자 ID 추가
                  hostNickname: data['hostNickname'], // 주최자 닉네임 추가
                );
              }
              return null;
            } catch (e) {
              print('모임 검색 파싱 오류: $e');
              return null;
            }
          })
          .where((meetup) => meetup != null)
          .cast<Meetup>()
          .toList();
    } catch (e) {
      print('모임 검색 오류: $e');
      return [];
    }
  }

  // 특정 요일에 해당하는 날짜 계산
  DateTime getDayDate(int dayIndex) {
    final List<DateTime> weekDates = getWeekDates();
    return weekDates[dayIndex];
  }

  // 모임 참여 (알림 기능 추가)
  Future<bool> joinMeetup(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final meetupRef = _firestore.collection('meetups').doc(meetupId);

      // 트랜잭션 전에 모임 정보 미리 가져오기
      final meetupDoc = await meetupRef.get();
      if (!meetupDoc.exists) {
        print('모임 문서가 존재하지 않음: $meetupId');
        return false;
      }

      final data = meetupDoc.data()!;
      final hostId = data['userId'];
      final meetupTitle = data['title'];
      final maxParticipants = data['maxParticipants'] ?? 1;

      // bool 타입 반환하는 트랜잭션 실행
      bool success = await _firestore.runTransaction<bool>((transaction) async {
        // 트랜잭션 내부에서 다시 문서 가져오기 (최신 데이터 확보)
        final updatedDoc = await transaction.get(meetupRef);
        if (!updatedDoc.exists) return false;

        final updatedData = updatedDoc.data()!;
        final List<dynamic> participants = List.from(
          updatedData['participants'] ?? [],
        );

        // 이미 참여 중인지 확인
        if (participants.contains(user.uid)) {
          print('이미 참여 중인 모임: $meetupId');
          return false;
        }

        // 정원 초과 확인
        final currentParticipants = updatedData['currentParticipants'] ?? 1;
        if (currentParticipants >= maxParticipants) {
          print('모임 정원 초과: $meetupId');
          return false;
        }

        // 참여자 추가
        participants.add(user.uid);

        // 참여자 수 업데이트
        final newParticipantCount = currentParticipants + 1;

        transaction.update(meetupRef, {
          'participants': participants,
          'currentParticipants': newParticipantCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return true; // 트랜잭션 성공
      });

      // 트랜잭션 성공 및 정원이 다 찬 경우 알림 발송
      if (success) {
        // 현재 참여자 수 확인을 위해 다시 문서 조회
        final updatedDoc = await meetupRef.get();
        final currentParticipants =
            updatedDoc.data()?['currentParticipants'] ?? 1;

        if (currentParticipants >= maxParticipants) {
          // 모임 객체 생성
          final meetup = Meetup(
            id: meetupId,
            title: meetupTitle ?? '',
            description: '', // 알림에 사용되지 않음
            location: '', // 알림에 사용되지 않음
            time: '', // 알림에 사용되지 않음
            maxParticipants: maxParticipants,
            currentParticipants: currentParticipants,
            host: '', // 알림에 사용되지 않음
            imageUrl: '', // 알림에 사용되지 않음
            date: DateTime.now(), // 알림에 사용되지 않음
          );

          // 모임 주최자에게 알림 전송
          await _notificationService.sendMeetupFullNotification(meetup, hostId);
        }
      }

      return success;
    } catch (e) {
      print('모임 참여 오류: $e');
      return false;
    }
  }

  // 모임 참여 취소 (participants 배열에서 제거)
  Future<bool> leaveMeetup(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final meetupRef = _firestore.collection('meetups').doc(meetupId);

      // 트랜잭션으로 안전하게 참여자 제거
      bool success = await _firestore.runTransaction<bool>((transaction) async {
        final meetupDoc = await transaction.get(meetupRef);
        if (!meetupDoc.exists) return false;

        final data = meetupDoc.data()!;
        final List<dynamic> participants = List.from(data['participants'] ?? []);

        // 참여하지 않은 상태인지 확인
        if (!participants.contains(user.uid)) {
          print('참여하지 않은 모임: $meetupId');
          return false;
        }

        // 참여자에서 제거
        participants.remove(user.uid);

        // 참여자 수 업데이트 (주최자는 제외하고 계산)
        final currentParticipants = data['currentParticipants'] ?? 1;
        final newParticipantCount = currentParticipants > 1 ? currentParticipants - 1 : 1;

        transaction.update(meetupRef, {
          'participants': participants,
          'currentParticipants': newParticipantCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return true;
      });

      if (success) {
        print('✅ 모임 참여 취소 성공: $meetupId');
      }

      return success;
    } catch (e) {
      print('❌ 모임 참여 취소 실패: $e');
      return false;
    }
  }

  //모임 삭제
  Future<bool> deleteMeetup(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        print('❌ 모임 삭제 실패: 로그인되지 않은 사용자');
        return false;
      }

      print('🗑️ 모임 삭제 시작: meetupId=$meetupId, currentUser=${user.uid}');

      // 모임 문서 가져오기
      final meetupDoc =
          await _firestore.collection('meetups').doc(meetupId).get();

      // 문서가 없는 경우
      if (!meetupDoc.exists) {
        print('❌ 모임 삭제 실패: 모임 문서가 존재하지 않음');
        return false;
      }

      final data = meetupDoc.data()!;
      print('📄 모임 데이터: userId=${data['userId']}, hostNickname=${data['hostNickname']}, host=${data['host']}');

      // 권한 체크: userId가 있으면 userId로, 없으면 hostNickname/host로 비교
      bool isOwner = false;
      
      if (data['userId'] != null && data['userId'].toString().isNotEmpty) {
        // 새로운 데이터: userId로 비교
        isOwner = data['userId'] == user.uid;
        print('🔍 userId 기반 권한 체크: ${data['userId']} == ${user.uid} → $isOwner');
      } else {
        // 기존 데이터: 현재 사용자 닉네임과 비교
        final hostToCheck = data['hostNickname'] ?? data['host'];
        if (hostToCheck != null && hostToCheck.toString().isNotEmpty) {
          // 현재 사용자 닉네임 가져오기
          final userDoc = await _firestore.collection('users').doc(user.uid).get();
          if (userDoc.exists) {
            final userData = userDoc.data();
            final currentUserNickname = userData?['nickname'] as String?;
            
            if (currentUserNickname != null && currentUserNickname.isNotEmpty) {
              isOwner = hostToCheck.toString().trim() == currentUserNickname.trim();
              print('🔍 닉네임 기반 권한 체크: "$hostToCheck" == "$currentUserNickname" → $isOwner');
            }
          }
        }
      }

      if (!isOwner) {
        print('❌ 모임 삭제 실패: 권한 없음 (현재 사용자가 주최자가 아님)');
        return false;
      }

      // 모임 삭제
      await _firestore.collection('meetups').doc(meetupId).delete();
      print('✅ 모임 삭제 성공: meetupId=$meetupId');
      return true;
    } catch (e) {
      print('❌ 모임 삭제 오류: $e');
      return false;
    }
  }

  // 사용자가 모임 주최자인지 확인
  Future<bool> isUserHostOfMeetup(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final meetupDoc =
          await _firestore.collection('meetups').doc(meetupId).get();
      if (!meetupDoc.exists) return false;

      final data = meetupDoc.data()!;
      return data['userId'] == user.uid;
    } catch (e) {
      print('주최자 확인 오류: $e');
      return false;
    }
  }

  // === 참여자 관리 기능 ===

  /// 모임 참여자 목록 조회
  Future<List<MeetupParticipant>> getMeetupParticipants(String meetupId) async {
    try {
      final querySnapshot = await _firestore
          .collection('meetup_participants')
          .where('meetupId', isEqualTo: meetupId)
          .orderBy('joinedAt', descending: false)
          .get();

      return querySnapshot.docs
          .map((doc) => MeetupParticipant.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('참여자 목록 조회 오류: $e');
      return [];
    }
  }

  /// 특정 상태의 참여자만 조회
  Future<List<MeetupParticipant>> getMeetupParticipantsByStatus(
    String meetupId, 
    String status,
  ) async {
    try {
      final querySnapshot = await _firestore
          .collection('meetup_participants')
          .where('meetupId', isEqualTo: meetupId)
          .where('status', isEqualTo: status)
          .orderBy('joinedAt', descending: false)
          .get();

      return querySnapshot.docs
          .map((doc) => MeetupParticipant.fromJson(doc.data()))
          .toList();
    } catch (e) {
      print('참여자 목록 조회 오류: $e');
      return [];
    }
  }

  /// 참여자 상태 업데이트 (승인/거절)
  Future<bool> updateParticipantStatus(
    String participantId, 
    String newStatus,
  ) async {
    try {
      await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .update({'status': newStatus});

      print('✅ 참여자 상태 업데이트 성공: $participantId -> $newStatus');
      return true;
    } catch (e) {
      print('❌ 참여자 상태 업데이트 실패: $e');
      return false;
    }
  }

  /// 참여자 승인
  Future<bool> approveParticipant(String participantId) async {
    return await updateParticipantStatus(participantId, ParticipantStatus.approved);
  }

  /// 참여자 거절
  Future<bool> rejectParticipant(String participantId) async {
    return await updateParticipantStatus(participantId, ParticipantStatus.rejected);
  }

  /// 참여자 제거 (모임에서 완전히 제거)
  Future<bool> removeParticipant(String participantId) async {
    try {
      await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .delete();

      print('✅ 참여자 제거 성공: $participantId');
      return true;
    } catch (e) {
      print('❌ 참여자 제거 실패: $e');
      return false;
    }
  }

  /// 모임 참여 신청 (메시지 포함)
  Future<bool> applyToMeetup(String meetupId, String? message) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // 사용자 정보 가져오기
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      if (!userDoc.exists) return false;

      final userData = userDoc.data()!;
      final participantId = '${meetupId}_${user.uid}';

      final participant = MeetupParticipant(
        id: participantId,
        meetupId: meetupId,
        userId: user.uid,
        userName: userData['displayName'] ?? user.displayName ?? '익명',
        userEmail: user.email ?? '',
        userProfileImage: userData['profileImageUrl'],
        joinedAt: DateTime.now(),
        status: ParticipantStatus.pending,
        message: message,
      );

      await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .set(participant.toJson());

      print('✅ 모임 참여 신청 성공: $meetupId');
      return true;
    } catch (e) {
      print('❌ 모임 참여 신청 실패: $e');
      return false;
    }
  }

  /// 사용자의 모임 참여 상태 확인
  Future<MeetupParticipant?> getUserParticipationStatus(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return null;

      final participantId = '${meetupId}_${user.uid}';
      final doc = await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .get();

      if (doc.exists) {
        return MeetupParticipant.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      print('참여 상태 확인 오류: $e');
      return null;
    }
  }

  /// 모임 참여 취소
  Future<bool> cancelMeetupParticipation(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final participantId = '${meetupId}_${user.uid}';
      await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .delete();

      print('✅ 모임 참여 취소 성공: $meetupId');
      return true;
    } catch (e) {
      print('❌ 모임 참여 취소 실패: $e');
      return false;
    }
  }

  // 친구 그룹별 모임 필터링 (새로운 메서드)
  Future<List<Meetup>> getFilteredMeetupsByFriendCategories({
    List<String>? categoryIds, // null이면 모든 친구의 모임, 빈 리스트면 전체 공개만
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];

      // 디버그: print('🔍 모임 필터링 시작: categoryIds = $categoryIds');

      // 1. 전체 모임 가져오기 (현재 날짜 이후만)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final snapshot = await _firestore
          .collection('meetups')
          .where('date', isGreaterThanOrEqualTo: today)
          .orderBy('date', descending: false)
          .get();

      final allMeetups = snapshot.docs.map((doc) {
        final data = doc.data();
        
        // 날짜 처리
        DateTime meetupDate;
        if (data['date'] is Timestamp) {
          meetupDate = (data['date'] as Timestamp).toDate();
        } else {
          final now = DateTime.now();
          meetupDate = DateTime(now.year, now.month, now.day);
        }

        final meetup = Meetup(
          id: doc.id,
          title: data['title'] ?? '',
          description: data['description'] ?? '',
          location: data['location'] ?? '',
          time: data['time'] ?? '',
          maxParticipants: data['maxParticipants'] ?? 0,
          currentParticipants: data['currentParticipants'] ?? 1,
          host: data['hostNickname'] ?? '익명',
          hostNationality: data['hostNationality'] ?? '',
          imageUrl: data['thumbnailImageUrl'] ?? AppConstants.DEFAULT_IMAGE_URL,
          thumbnailContent: data['thumbnailContent'] ?? '',
          thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
          date: meetupDate,
          category: data['category'] ?? '기타',
          userId: data['userId'],
          hostNickname: data['hostNickname'],
          visibility: data['visibility'] ?? 'public',
          visibleToCategoryIds: List<String>.from(data['visibleToCategoryIds'] ?? []),
        );
        
        // 디버그: print('📄 모임 로드: ${meetup.title}');
        return meetup;
      }).toList();

      // 2. 친구 관계 가져오기
      final friendsSnapshot = await _firestore
          .collection('relationships')
          .where('userId', isEqualTo: user.uid)
          .where('status', isEqualTo: 'accepted')
          .get();

      final friendIds = friendsSnapshot.docs.map((doc) => doc.data()['friendId'] as String).toSet();

      // 3. 친구 카테고리 가져오기 (categoryIds가 지정된 경우)
      Set<String> targetFriendIds = {};
      if (categoryIds != null && categoryIds.isNotEmpty) {
        final categoriesSnapshot = await _firestore
            .collection('friend_categories')
            .where('userId', isEqualTo: user.uid)
            .where(FieldPath.documentId, whereIn: categoryIds)
            .get();

        for (final categoryDoc in categoriesSnapshot.docs) {
          final categoryData = categoryDoc.data();
          final categoryFriendIds = List<String>.from(categoryData['friendIds'] ?? []);
          targetFriendIds.addAll(categoryFriendIds);
        }
      } else if (categoryIds == null) {
        // 모든 친구
        targetFriendIds = friendIds;
      }
      // categoryIds가 빈 리스트면 targetFriendIds도 빈 상태 유지 (전체 공개만)

      // 4. 모든 사용자 카테고리 정보 미리 가져오기 (성능 최적화)
      final userCategoriesSnapshot = await _firestore
          .collection('friend_categories')
          .where('friendIds', arrayContains: user.uid)
          .get();
      
      final userCategoryIds = userCategoriesSnapshot.docs.map((doc) => doc.id).toSet();

      // 5. 모임 필터링
      final filteredMeetups = <Meetup>[];
      for (final meetup in allMeetups) {
        // 내 모임은 항상 표시
        if (meetup.userId == user.uid) {
          filteredMeetups.add(meetup);
          continue;
        }

        // 공개 범위에 따른 필터링
        switch (meetup.visibility) {
          case 'public':
            filteredMeetups.add(meetup); // 전체 공개는 항상 표시
            break;

          case 'friends':
            // 친구에게만 공개 - 모임 주최자가 내 친구인지 확인
            if (friendIds.contains(meetup.userId)) {
              filteredMeetups.add(meetup);
            }
            break;

          case 'category':
            // 특정 카테고리에만 공개
            bool shouldShow = false;
            
            if (categoryIds == null) {
              // 모든 친구 보기 모드: 내가 해당 카테고리에 속해있는지 확인
              for (final categoryId in meetup.visibleToCategoryIds) {
                if (userCategoryIds.contains(categoryId)) {
                  shouldShow = true;
                  break;
                }
              }
            } else {
              // 특정 카테고리 필터링 모드: 모임이 선택된 카테고리에 공개되는지 확인
              shouldShow = meetup.visibleToCategoryIds.any((visibleCategoryId) => 
                categoryIds.contains(visibleCategoryId));
            }
            
            if (shouldShow) {
              filteredMeetups.add(meetup);
            }
            break;
        }
      }

      return filteredMeetups;
    } catch (e) {
      print('❌ 친구 그룹별 모임 필터링 오류: $e');
      return [];
    }
  }
}
