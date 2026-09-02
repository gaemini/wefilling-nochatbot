// lib/services/meetup_service.dart
// 모임 관련 CRUD 작업 처리
// 모임 생성, 참여, 취소 기능
// 날짜별 모임 조회 및 필터링
// 날짜 관련 유틸리티 함수 제공

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/meetup.dart';
import '../models/meetup_participant.dart';
import '../constants/meetup_limits.dart';
import '../security/frozen_audience_policy.dart';
import 'notification_service.dart';
import 'content_filter_service.dart';
import 'view_history_service.dart';
import 'dart:async';
import 'dart:io';
import '../utils/logger.dart';
import 'participation_cache_service.dart';
import 'user_info_cache_service.dart';

class MeetupService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final NotificationService _notificationService = NotificationService();
  final ParticipationCacheService _cacheService = ParticipationCacheService();
  final ViewHistoryService _viewHistory = ViewHistoryService();
  final UserInfoCacheService _userInfoCache = UserInfoCacheService();

  Future<List<MeetupParticipant>> _resolveLatestParticipantProfiles(
    List<MeetupParticipant> participants,
  ) async {
    final userIds = participants
        .map((participant) => participant.userId.trim())
        .where((userId) => userId.isNotEmpty && userId != 'host')
        .toSet()
        .toList(growable: false);
    if (userIds.isEmpty) return participants;

    final profiles = await _userInfoCache.getUserInfoBatch(
      userIds,
      forceRefresh: true,
    );
    return participants.map((participant) {
      final profile = profiles[participant.userId];
      if (profile == null) return participant;
      if (profile.isDeletedAccount) {
        return participant.copyWith(
          userName: 'DELETED_ACCOUNT',
          userProfileImage: '',
          userCountry: '',
          isDeletedAccount: true,
        );
      }
      return participant.copyWith(
        userName: profile.nickname,
        userProfileImage: profile.photoURL,
        userCountry: profile.nationality,
        isDeletedAccount: false,
      );
    }).toList(growable: false);
  }

  // Firestore 인스턴스 getter 추가
  FirebaseFirestore get firestore => _firestore;

  static const String _kickedUserIdsField = 'kickedUserIds';
  static const String _participantEventCollection = 'meetup_participant_events';

  Future<bool> isUserKickedFromMeetup({
    required String meetupId,
    required String userId,
  }) async {
    try {
      final doc = await _firestore.collection('meetups').doc(meetupId).get();
      if (!doc.exists) return false;
      final data = doc.data();
      final kicked = List<String>.from(data?[_kickedUserIdsField] ?? const []);
      return kicked.contains(userId);
    } catch (_) {
      return false;
    }
  }

  Future<void> _logParticipantEvent({
    required String meetupId,
    required String meetupTitle,
    required String type, // join | leave | kick
    required String actorId,
    required String actorName,
    required String targetUserId,
    required String targetUserName,
  }) async {
    try {
      await _firestore.collection(_participantEventCollection).add({
        'meetupId': meetupId,
        'meetupTitle': meetupTitle,
        'type': type,
        'actorId': actorId,
        'actorName': actorName,
        'targetUserId': targetUserId,
        'targetUserName': targetUserName,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // 로그 실패는 UX 치명적이지 않으므로 무시
      Logger.error('❌ 참여자 이벤트 로그 기록 실패: $e');
    }
  }

  // 지정된 주차의 월요일부터 일요일까지 날짜 계산
  List<DateTime> getWeekDates({DateTime? weekAnchor}) {
    final DateTime baseDate = weekAnchor ?? DateTime.now();

    // 지정된 주차의 월요일 찾기 (월요일=1, 일요일=7)
    final startOfWeek = baseDate.subtract(Duration(days: baseDate.weekday - 1));
    final DateTime startOfWeekDay =
        DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);

    final List<DateTime> weekDates = [];

    // 월요일부터 일요일까지 7일 생성
    for (int i = 0; i < 7; i++) {
      weekDates.add(startOfWeekDay.add(Duration(days: i)));
    }

    return weekDates;
  }

  // 날짜 포맷 문자열 반환 (요일도 포함)
  String getFormattedDate(DateTime date) {
    final List<String> weekdayNames = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun'
    ];
    final int weekdayIndex = date.weekday - 1; // 0: 월요일, 6: 일요일
    return '${date.month}월 ${date.day}일 (${weekdayNames[weekdayIndex]})';
  }

  int _minutesFromMeetupTime(String raw) {
    // "14:00 ~ 16:00" / "14:00~16:00" / "미정" 등 방어적으로 파싱
    final t = raw.trim();
    if (t.isEmpty || t == '미정' || !t.contains(':')) return 24 * 60 + 1;
    final start = t.split('~').first.trim();
    final parts = start.split(':');
    if (parts.length < 2) return 24 * 60 + 1;
    final h = int.tryParse(parts[0].trim()) ?? 23;
    final m = int.tryParse(parts[1].trim()) ?? 59;
    return (h.clamp(0, 23) * 60) + m.clamp(0, 59);
  }

  DateTime _computeMeetupStartsAt(DateTime date, String rawTime) {
    final d = date.toLocal();
    final baseDay = DateTime(d.year, d.month, d.day);
    final t = rawTime.trim();
    if (t.isEmpty || t == '미정' || !t.contains(':')) {
      // 시간 미정: 일단 당일 시작(00:00)로 저장
      return baseDay;
    }
    final startStr = t.split('~').first.trim();
    final parts = startStr.split(':');
    if (parts.length < 2) return baseDay;
    final h = int.tryParse(parts[0].trim()) ?? 0;
    final m = int.tryParse(parts[1].trim()) ?? 0;
    return DateTime(baseDay.year, baseDay.month, baseDay.day, h.clamp(0, 23),
        m.clamp(0, 59));
  }

  DateTime _computeMeetupEndsAt(DateTime date, String rawTime) {
    final d = date.toLocal();
    final baseDay = DateTime(d.year, d.month, d.day);
    final t = rawTime.trim();
    if (t.isEmpty || t == '미정' || !t.contains(':')) {
      return DateTime(baseDay.year, baseDay.month, baseDay.day, 23, 59);
    }

    final startStr = t.split('~').first.trim();
    final startParts = startStr.split(':');
    if (startParts.length < 2) {
      return DateTime(baseDay.year, baseDay.month, baseDay.day, 23, 59);
    }

    final startHour = int.tryParse(startParts[0].trim()) ?? 0;
    final startMinute = int.tryParse(startParts[1].trim()) ?? 0;

    int endHour = startHour + 2;
    int endMinute = startMinute;

    if (t.contains('~')) {
      final endStr = t.split('~')[1].trim();
      final endParts = endStr.split(':');
      if (endParts.length >= 2) {
        endHour = int.tryParse(endParts[0].trim()) ?? endHour;
        endMinute = int.tryParse(endParts[1].trim()) ?? endMinute;
      }
    }

    return DateTime(
      baseDay.year,
      baseDay.month,
      baseDay.day,
      endHour.clamp(0, 23),
      endMinute.clamp(0, 59),
    );
  }

  bool _isMeetupExpiredFromMeetupDocData(
    Map<String, dynamic> meetupData, {
    DateTime? now,
  }) {
    final baseNow = (now ?? DateTime.now()).toLocal();

    // 우선 endsAt 필드가 있으면 그것을 사용(시간까지 정확).
    final rawEndsAt = meetupData['endsAt'];
    if (rawEndsAt is Timestamp) {
      return baseNow.isAfter(rawEndsAt.toDate().toLocal());
    }
    if (rawEndsAt is DateTime) {
      return baseNow.isAfter(rawEndsAt.toLocal());
    }

    // fallback: date + time으로 계산 (레거시 문서도 대응)
    final date = _parseMeetupDateFromFirestore(meetupData);
    final time = (meetupData['time'] ?? '').toString();
    final endsAt = _computeMeetupEndsAt(date, time);
    return baseNow.isAfter(endsAt);
  }

  String _pad2(int v) => v.toString().padLeft(2, '0');

  /// 날짜를 타임존과 무관한 "캘린더 날짜 키"로 정규화합니다.
  /// - 예: 2026-02-11
  String _dateKey(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${_pad2(local.month)}-${_pad2(local.day)}';
  }

  List<String> _legacyDateStringCandidates(DateTime d) {
    final local = d.toLocal();
    final y = local.year.toString();
    final m = _pad2(local.month);
    final day = _pad2(local.day);
    return <String>[
      '$y-$m-$day',
      '$y.$m.$day',
      '$y/$m/$day',
    ];
  }

  DateTime _parseMeetupDateFromFirestore(Map<String, dynamic> data) {
    final raw = data['date'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;

    // 일부 구버전 데이터에서 date가 문자열로 저장된 케이스 방어
    if (raw is String) {
      final s = raw.trim();
      if (s.isNotEmpty) {
        final normalized = s.replaceAll('.', '-').replaceAll('/', '-');
        // yyyy-MM-dd 또는 yyyy-MM-dd HH:mm:ss 형태 대응
        final datePart = normalized.split(' ').first;
        final parts = datePart.split('-');
        if (parts.length >= 3) {
          final y = int.tryParse(parts[0]);
          final m = int.tryParse(parts[1]);
          final d = int.tryParse(parts[2]);
          if (y != null && m != null && d != null) {
            return DateTime(y, m, d);
          }
        }
      }
    }

    return DateTime.now();
  }

  DateTime _parseCreatedAtFromFirestore(Map<String, dynamic> data) {
    final raw = data['createdAt'];
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    // serverTimestamp가 아직 반영되지 않았거나(로컬 null), 구버전/비정상 데이터 방어
    // - UX 상 "방금 만든 모임"이 하단으로 떨어지지 않도록 now를 사용
    return DateTime.now();
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month && x.day == y.day;
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
    String? thumbnailImageUrl, // 썸네일 이미지 URL(업로드 없이 사용)
    List<File>? images, // 추가 이미지 파일들(최대 3장)
    List<String>? imageUrls, // 추가 이미지 URL들(최대 3장)
    String visibility = 'public', // 공개 범위
    List<String> visibleToCategoryIds = const [], // 특정 카테고리에만 공개
    int? publicDurationHours, // null: 제한 없음, 그 외 1~12시간
    bool requiresHanyangVerification = false,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      if (!isValidMeetupParticipantLimit(maxParticipants)) {
        Logger.error(
          '밋업 최대 인원은 $minMeetupParticipants~$maxMeetupParticipants명이어야 합니다.',
        );
        return false;
      }

      if (!const {'public', 'friends', 'category'}.contains(visibility)) {
        Logger.error('지원하지 않는 밋업 공개 범위: $visibility');
        return false;
      }
      final normalizedCategoryIds = visibleToCategoryIds
          .map((id) => id.trim())
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (visibility == 'category' && normalizedCategoryIds.isEmpty) {
        Logger.error('그룹 공개 밋업에 선택된 그룹이 없습니다.');
        return false;
      }
      if (publicDurationHours != null &&
          (publicDurationHours < 1 || publicDurationHours > 12)) {
        Logger.error('밋업 공개 시간은 1~12시간이어야 합니다.');
        return false;
      }
      final startsAt = _computeMeetupStartsAt(date, time);
      final endsAt = _computeMeetupEndsAt(date, time);

      // ---- 이미지 입력 정규화 (최대 3장) ----
      final remoteUrls = <String>[];
      void addRemote(String? u) {
        final v = u?.trim();
        if (v == null || v.isEmpty) return;
        if (!remoteUrls.contains(v)) remoteUrls.add(v);
      }

      addRemote(thumbnailImageUrl);
      if (imageUrls != null) {
        for (final u in imageUrls) {
          addRemote(u);
        }
      }

      final localFiles = <File>[];
      if (thumbnailImage != null) localFiles.add(thumbnailImage);
      if (images != null) localFiles.addAll(images);

      // 최대 3장 제한(원격 우선)
      if (remoteUrls.length > 3) {
        remoteUrls.removeRange(3, remoteUrls.length);
      }
      final remainingForLocal = 3 - remoteUrls.length;
      final uploadFiles = remainingForLocal <= 0
          ? <File>[]
          : localFiles.take(remainingForLocal).toList();

      // 공개 대상 계산과 canonical 문서 생성은 서버에서 원자적으로 수행한다.
      // 클라이언트가 임의 UID 배열을 주입하지 못하며 재시도 시 같은 ID를 쓴다.
      final docRef = _firestore.collection('meetups').doc();
      try {
        await FirebaseFunctions.instance
            .httpsCallable('createMeetupSecure')
            .call(<String, dynamic>{
          'meetupId': docRef.id,
          'title': title,
          'description': description,
          'location': location,
          'time': time,
          'maxParticipants': maxParticipants,
          'dateMillis': date.millisecondsSinceEpoch,
          'startsAtMillis': startsAt.millisecondsSinceEpoch,
          'endsAtMillis': endsAt.millisecondsSinceEpoch,
          'dateKey': _dateKey(date),
          'category': category,
          'thumbnailContent': thumbnailContent,
          'imageUrls': remoteUrls,
          'visibility': visibility,
          'visibleToCategoryIds': normalizedCategoryIds,
          'publicDurationHours': publicDurationHours,
          'requiresHanyangVerification': requiresHanyangVerification,
        }).timeout(const Duration(seconds: 30));
      } catch (error) {
        // 서버가 생성한 뒤 응답만 유실된 경우를 실패/중복으로 처리하지 않는다.
        var created = false;
        try {
          final document =
              await docRef.get().timeout(const Duration(seconds: 5));
          final data = document.data();
          created = document.exists &&
              (data?['ownerId'] == user.uid || data?['userId'] == user.uid);
        } catch (_) {}
        if (!created) Error.throwWithStackTrace(error, StackTrace.current);
      }

      // 이미지 업로드 처리(최대 3장)
      if (uploadFiles.isNotEmpty) {
        try {
          final storage = FirebaseStorage.instance;
          final uploadedUrls = <String>[];

          for (var i = 0; i < uploadFiles.length; i++) {
            final file = uploadFiles[i];
            final ref = storage.ref().child('meetup_images/${docRef.id}/$i');
            await ref.putFile(file);
            final url = await ref.getDownloadURL();
            uploadedUrls.add(url);
          }

          final combined = <String>[...remoteUrls, ...uploadedUrls];
          if (combined.isNotEmpty) {
            await docRef.update({
              'imageUrls': combined,
              // remoteUrls가 없었으면 업로드 첫 장을 썸네일로
              if (remoteUrls.isEmpty) 'thumbnailImageUrl': combined.first,
            });
          }
        } catch (e) {
          Logger.error('모임 이미지 업로드 오류: $e');
        }
      }

      return true;
    } catch (e) {
      Logger.error('모임 생성 오류: $e');
      return false;
    }
  }

  Stream<List<Meetup>> _combineMeetupStreams(
    Stream<List<Meetup>> a,
    Stream<List<Meetup>> b,
  ) {
    late final StreamController<List<Meetup>> controller;
    StreamSubscription<List<Meetup>>? subA;
    StreamSubscription<List<Meetup>>? subB;

    List<Meetup> latestA = const [];
    List<Meetup> latestB = const [];
    var hasA = false;
    var hasB = false;

    void emit() {
      // 초기 구독에서 한쪽 쿼리의 빈 기본값을 완성된 결과처럼 먼저
      // 방출하면 목록이 잠깐 사라졌다 다시 나타난다. 양쪽 첫 결과가
      // 준비된 뒤부터 병합해 PageView의 불필요한 레이아웃 교체를 막는다.
      if (!hasA || !hasB) return;
      final byId = <String, Meetup>{};
      for (final m in latestA) {
        byId[m.id] = m;
      }
      for (final m in latestB) {
        byId[m.id] = m;
      }
      final merged = byId.values.toList();
      merged.sort((x, y) {
        final d = x.date.compareTo(y.date);
        if (d != 0) return d;
        return _minutesFromMeetupTime(x.time)
            .compareTo(_minutesFromMeetupTime(y.time));
      });
      controller.add(merged);
    }

    controller = StreamController<List<Meetup>>.broadcast(
      onListen: () {
        subA = a.listen((v) {
          latestA = v;
          hasA = true;
          emit();
        }, onError: (Object error, StackTrace stackTrace) {
          hasA = true;
          controller.addError(error, stackTrace);
          emit();
        });
        subB = b.listen((v) {
          latestB = v;
          hasB = true;
          emit();
        }, onError: (Object error, StackTrace stackTrace) {
          hasB = true;
          controller.addError(error, stackTrace);
          emit();
        });
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );

    return controller.stream;
  }

  Future<List<Meetup>> _filterVisibleAndBlocked(
    List<Meetup> meetups,
  ) async {
    final visible = await filterMeetupsForCurrentUser(meetups);
    return ContentFilterService.filterMeetups(visible);
  }

  /// Firestore 스냅샷이 새로 오지 않아도 가장 가까운 공개 만료 시각에 목록을
  /// 다시 방출한다. 따라서 화면 새로고침이나 1분 주기의 서버 정리 작업을
  /// 기다리지 않고 미확정 밋업이 정시에 사라진다.
  Stream<List<Meetup>> _hideExpiredMeetupsOverTime(
    Stream<List<Meetup>> source,
  ) {
    late final StreamController<List<Meetup>> controller;
    StreamSubscription<List<Meetup>>? subscription;
    Timer? expiryTimer;
    var latest = const <Meetup>[];

    void emit() {
      expiryTimer?.cancel();
      final now = DateTime.now();
      final visible =
          latest.where((meetup) => meetup.isPublishedAt(now)).toList(
                growable: false,
              );
      if (!controller.isClosed) controller.add(visible);

      DateTime? nearest;
      for (final meetup in visible) {
        final expiresAt = meetup.publicExpiresAt;
        if (!meetup.hasPublicTimeLimit || expiresAt == null) continue;
        if (nearest == null || expiresAt.isBefore(nearest)) nearest = expiresAt;
      }
      if (nearest == null) return;
      final delay = nearest.difference(now);
      expiryTimer = Timer(
        delay.isNegative
            ? Duration.zero
            : delay + const Duration(milliseconds: 50),
        emit,
      );
    }

    controller = StreamController<List<Meetup>>.broadcast(
      onListen: () {
        subscription = source.listen((meetups) {
          latest = meetups;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        expiryTimer?.cancel();
        await subscription?.cancel();
      },
    );
    return controller.stream;
  }

  /// Firestore Rules가 목록을 필터처럼 처리할 수 없으므로 공개/대상/주최 쿼리를
  /// 분리합니다. 이 경로를 통과한 문서만 기기로 내려오며, 마지막 검사는 문서에
  /// 저장된 frozen audience와 별도 차단 정책만 사용합니다.
  Stream<List<Meetup>> _watchAudienceScopedMeetupQuery(
    Query<Map<String, dynamic>> baseQuery,
  ) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const <Meetup>[]);

    Stream<List<Meetup>> watch(Query<Map<String, dynamic>> query) =>
        query.snapshots().map<List<Meetup>>(_convertToMeetups);

    final scoped = _mergeManyMeetupStreams(<Stream<List<Meetup>>>[
      watch(baseQuery.where('visibility', isEqualTo: 'public')),
      watch(baseQuery.where('allowedUserIds', arrayContains: user.uid)),
      // 레거시 비공개 문서에 allowedUserIds가 없어도 주최자는 복구할 수 있습니다.
      watch(baseQuery.where('userId', isEqualTo: user.uid)),
    ]);
    return _hideExpiredMeetupsOverTime(
      scoped.asyncMap(_filterVisibleAndBlocked),
    );
  }

  Future<List<Meetup>> _getAudienceScopedMeetupQuery(
    Query<Map<String, dynamic>> baseQuery,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return const <Meetup>[];

    final snapshots =
        await Future.wait(<Future<QuerySnapshot<Map<String, dynamic>>>>[
      baseQuery.where('visibility', isEqualTo: 'public').get(),
      baseQuery.where('allowedUserIds', arrayContains: user.uid).get(),
      baseQuery.where('userId', isEqualTo: user.uid).get(),
    ]);
    final byId = <String, Meetup>{};
    for (final snapshot in snapshots) {
      for (final meetup in _convertToMeetups(snapshot)) {
        byId[meetup.id] = meetup;
      }
    }
    return _filterVisibleAndBlocked(byId.values.toList());
  }

  // 요일별 모임 가져오기 - 모든 모임 표시
  Stream<List<Meetup>> getMeetupsByDay(int dayIndex, {DateTime? weekAnchor}) {
    // 해당 요일의 날짜 계산 (지정된 주차 기준 또는 현재 날짜 기준)
    final List<DateTime> weekDates = getWeekDates(weekAnchor: weekAnchor);
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

    final dateKey = _dateKey(startOfDay);
    final legacyCandidates = _legacyDateStringCandidates(startOfDay);

    final byDateKey = _watchAudienceScopedMeetupQuery(
        _firestore.collection('meetups').where('dateKey', isEqualTo: dateKey));

    final byTimestampRange = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isGreaterThanOrEqualTo: startOfDay)
        .where('date', isLessThanOrEqualTo: endOfDay));

    final byLegacyString1 = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isEqualTo: legacyCandidates[0]));
    final byLegacyString2 = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isEqualTo: legacyCandidates[1]));
    final byLegacyString3 = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isEqualTo: legacyCandidates[2]));

    final byLegacyStrings = _combineMeetupStreams(byLegacyString1,
        _combineMeetupStreams(byLegacyString2, byLegacyString3));

    return _combineMeetupStreams(
        byDateKey, _combineMeetupStreams(byTimestampRange, byLegacyStrings));
  }

  Stream<List<Meetup>> _mergeManyMeetupStreams(
      List<Stream<List<Meetup>>> streams) {
    if (streams.isEmpty) return Stream.value(const <Meetup>[]);
    return streams.skip(1).fold<Stream<List<Meetup>>>(
          streams.first,
          (acc, s) => _combineMeetupStreams(acc, s),
        );
  }

  DateTime _monthStart(DateTime d) {
    final local = d.toLocal();
    return DateTime(local.year, local.month, 1);
  }

  DateTime _monthEnd(DateTime d) {
    final local = d.toLocal();
    return DateTime(local.year, local.month + 1, 0, 23, 59, 59, 999);
  }

  bool _isSameMonth(DateTime a, DateTime b) {
    final x = a.toLocal();
    final y = b.toLocal();
    return x.year == y.year && x.month == y.month;
  }

  /// 밋업 탭(월간 달력)에서 사용할 "해당 월의 모임" 스트림.
  /// - dateKey range + Timestamp range를 병합(중복 제거)합니다.
  /// - 공개범위(친구/카테고리) 필터 + 차단 필터를 적용합니다.
  Stream<List<Meetup>> watchVisibleMeetupsForMonth(DateTime focusedMonth) {
    return watchVisibleMeetupsForMonthRange(
      firstMonth: focusedMonth,
      lastMonth: focusedMonth,
    );
  }

  /// 날짜 PageView가 월 경계를 넘을 때 목록 스트림을 즉시 교체하지 않도록
  /// 인접한 여러 달을 하나의 제한된 실시간 범위로 조회합니다.
  Stream<List<Meetup>> watchVisibleMeetupsForMonthRange({
    required DateTime firstMonth,
    required DateTime lastMonth,
  }) {
    final rangeStart = _monthStart(firstMonth);
    final rangeEnd = _monthEnd(lastMonth);
    final startKey = _dateKey(rangeStart);
    final endKey = _dateKey(rangeEnd);

    final byDateKeyRange = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('dateKey', isGreaterThanOrEqualTo: startKey)
        .where('dateKey', isLessThanOrEqualTo: endKey)
        .orderBy('dateKey', descending: false));

    final byTimestampRange = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isGreaterThanOrEqualTo: rangeStart)
        .where('date', isLessThanOrEqualTo: rangeEnd)
        .orderBy('date', descending: false));

    return _combineMeetupStreams(byDateKeyRange, byTimestampRange);
  }

  /// 내 참여/참가신청(approved/pending) 모임 ID 스트림.
  Stream<Set<String>> watchMyParticipatingMeetupIds() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(<String>{});

    return _firestore
        .collection('meetup_participants')
        .where('userId', isEqualTo: user.uid)
        .where('status', whereIn: const [
          ParticipantStatus.approved,
          ParticipantStatus.pending
        ])
        .snapshots()
        .map((snapshot) {
          final ids = <String>{};
          for (final d in snapshot.docs) {
            final data = d.data();
            final meetupId = (data['meetupId'] ?? '').toString().trim();
            if (meetupId.isNotEmpty) ids.add(meetupId);
          }
          return ids;
        });
  }

  /// 내 "승인된 참여"(approved) 모임 ID 스트림.
  /// - 밋업 탭의 과거 날짜에서는 "참여했던 모임"만 보여야 하므로 pending은 제외한다.
  Stream<Set<String>> watchMyApprovedParticipatingMeetupIds() {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(<String>{});

    return _firestore
        .collection('meetup_participants')
        .where('userId', isEqualTo: user.uid)
        .where('status', isEqualTo: ParticipantStatus.approved)
        .snapshots()
        .map((snapshot) {
      final ids = <String>{};
      for (final d in snapshot.docs) {
        final data = d.data();
        final meetupId = (data['meetupId'] ?? '').toString().trim();
        if (meetupId.isNotEmpty) ids.add(meetupId);
      }
      return ids;
    });
  }

  Stream<List<Meetup>> _watchMeetupsByIds(Set<String> ids) {
    if (ids.isEmpty) return Stream.value(const <Meetup>[]);

    final list = ids.toList();
    final streams = <Stream<List<Meetup>>>[];

    for (var i = 0; i < list.length; i += 10) {
      final chunk = list.sublist(i, (i + 10).clamp(0, list.length));
      for (final id in chunk) {
        streams.add(
          _hideExpiredMeetupsOverTime(
            _firestore
                .collection('meetups')
                .doc(id)
                .snapshots()
                .asyncMap((doc) async {
              if (!doc.exists || doc.data() == null) return const <Meetup>[];
              final meetup = Meetup.fromJson(<String, dynamic>{
                ...doc.data()!,
                'id': doc.id,
              });
              return _filterVisibleAndBlocked(<Meetup>[meetup]);
            }),
          ).handleError((Object error) {
            // 공개 대상에서 빠진 사용자의 기존 참여 ID가 남아 있어도 문서를
            // 우회 조회하지 않고 해당 항목만 목록에서 제외합니다.
            Logger.warning('접근할 수 없는 밋업 문서 제외($id): $error');
          }),
        );
      }
    }

    return _mergeManyMeetupStreams(streams);
  }

  /// 밋업 탭에서 과거 날짜용으로 사용할 "내 관련 모임(호스트 + 참여/신청)" 월 스트림.
  /// - 과거 날짜에서는 전체 모임을 조회/표시하지 않고, 내 관련 모임만 노출하기 위함.
  Stream<List<Meetup>> watchMyRelevantMeetupsForMonth(DateTime focusedMonth) {
    final user = _auth.currentUser;
    if (user == null) return Stream.value(const <Meetup>[]);

    final controller = StreamController<List<Meetup>>.broadcast();
    StreamSubscription? hostedSub;
    StreamSubscription? idsSub;
    StreamSubscription? participatingMeetupsSub;

    var latestHosted = const <Meetup>[];
    var latestParticipating = const <Meetup>[];

    List<Meetup> filterToMonth(List<Meetup> src) {
      final m = _monthStart(focusedMonth);
      return src.where((x) => _isSameMonth(x.date, m)).toList();
    }

    void emit() {
      final byId = <String, Meetup>{};
      for (final m in latestHosted) {
        byId[m.id] = m;
      }
      for (final m in latestParticipating) {
        byId[m.id] = m;
      }
      final merged = byId.values.toList()
        ..sort((a, b) {
          final d = a.date.compareTo(b.date);
          if (d != 0) return d;
          return _minutesFromMeetupTime(a.time)
              .compareTo(_minutesFromMeetupTime(b.time));
        });
      controller.add(merged);
    }

    hostedSub = _firestore
        .collection('meetups')
        .where('userId', isEqualTo: user.uid)
        .snapshots()
        .map(_convertToMeetups)
        .listen((meetups) async {
      latestHosted =
          filterToMonth(await ContentFilterService.filterMeetups(meetups));
      emit();
    }, onError: controller.addError);

    idsSub = watchMyApprovedParticipatingMeetupIds().listen((ids) {
      participatingMeetupsSub?.cancel();
      participatingMeetupsSub = _watchMeetupsByIds(ids).listen((meetups) {
        latestParticipating = filterToMonth(meetups);
        emit();
      }, onError: controller.addError);
    }, onError: controller.addError);

    controller.onCancel = () async {
      await hostedSub?.cancel();
      await idsSub?.cancel();
      await participatingMeetupsSub?.cancel();
    };

    return controller.stream;
  }

  /// 오늘 "생성된" 모임 가져오기 (약속 날짜와 무관)
  /// - Today 탭에서 "오늘 올라온 모임"을 함께 보여주기 위함
  Stream<List<Meetup>> getMeetupsCreatedToday({DateTime? now}) {
    final base = (now ?? DateTime.now()).toLocal();
    final startOfDay = DateTime(base.year, base.month, base.day);
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));

    return _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('createdAt', isGreaterThanOrEqualTo: startOfDay)
        .where('createdAt', isLessThanOrEqualTo: endOfDay)
        .orderBy('createdAt', descending: true));
  }

  /// Today 탭용 모임 스트림
  /// - 약속 날짜가 오늘인 모임 + 오늘 생성된 모임을 함께 보여줌(중복 제거)
  Stream<List<Meetup>> getTodayTabMeetups({DateTime? now}) {
    final base = (now ?? DateTime.now()).toLocal();
    final today = DateTime(base.year, base.month, base.day);

    return _combineMeetupStreams(
      // 두 스트림 모두 같은 기준 시각을 사용해야 자정 경계에서도 서로 다른
      // 날짜의 결과가 섞이지 않습니다.
      getTodayMeetups(now: base),
      getMeetupsCreatedToday(now: base),
    ).map((meetups) {
      // 요구사항:
      // - "오늘(약속 날짜)인 모임"을 맨 위로 묶어서
      // - 그 아래에 "오늘 생성됐지만 오늘 약속이 아닌 모임"을 붙여 표시
      // - 각 묶음 내부는 최신 등록(createdAt) 기준 내림차순
      final todayDateMeetups = <Meetup>[];
      final createdTodayButNotTodayDateMeetups = <Meetup>[];
      // ⚠️ 어떤 이유로든(레거시 dateKey 불일치 등) 오늘 규칙을 벗어난 모임이 섞여 들어오면
      // Today 탭에서는 절대 노출되면 안 된다.
      final eligibleMeetups = meetups.where((m) {
        final isMeetupDateToday = _isSameLocalDay(m.date, today);
        final isCreatedToday = _isSameLocalDay(m.createdAt, today);
        return isMeetupDateToday || isCreatedToday;
      });

      for (final m in eligibleMeetups) {
        final isMeetupDateToday = _isSameLocalDay(m.date, today);
        if (isMeetupDateToday) {
          todayDateMeetups.add(m);
        } else {
          // isCreatedToday == true (eligibleMeetups 조건)
          createdTodayButNotTodayDateMeetups.add(m);
        }
      }

      int byCreatedDesc(Meetup a, Meetup b) =>
          b.createdAt.toLocal().compareTo(a.createdAt.toLocal());
      todayDateMeetups.sort(byCreatedDesc);
      createdTodayButNotTodayDateMeetups.sort(byCreatedDesc);

      return <Meetup>[
        ...todayDateMeetups,
        ...createdTodayButNotTodayDateMeetups,
      ];
    });
  }

  // 카테고리별 모임 가져오기 (새로운 메서드)
  Stream<List<Meetup>> getMeetupsByCategory(String category) {
    // 현재 날짜 이후의 모임만 가져오기
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 모든 모임 가져오기인 경우
    if (category == '전체') {
      return _watchAudienceScopedMeetupQuery(_firestore
          .collection('meetups')
          .where('date', isGreaterThanOrEqualTo: today)
          .orderBy('date', descending: false));
    }

    // 특정 카테고리 모임 가져오기
    return _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('category', isEqualTo: category)
        .where('date', isGreaterThanOrEqualTo: today)
        .orderBy('date', descending: false));
  }

  // 오늘의 모임 가져오기
  Stream<List<Meetup>> getTodayMeetups({DateTime? now}) {
    final base = (now ?? DateTime.now()).toLocal();
    final startOfDay = DateTime(base.year, base.month, base.day);
    final endOfDay = startOfDay
        .add(const Duration(days: 1))
        .subtract(const Duration(microseconds: 1));

    final dateKey = _dateKey(startOfDay);
    final legacyCandidates = _legacyDateStringCandidates(startOfDay);

    final byDateKey = _watchAudienceScopedMeetupQuery(
        _firestore.collection('meetups').where('dateKey', isEqualTo: dateKey));

    final byTimestampRange = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isGreaterThanOrEqualTo: startOfDay)
        .where('date', isLessThanOrEqualTo: endOfDay));

    final byLegacyString1 = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isEqualTo: legacyCandidates[0]));
    final byLegacyString2 = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isEqualTo: legacyCandidates[1]));
    final byLegacyString3 = _watchAudienceScopedMeetupQuery(_firestore
        .collection('meetups')
        .where('date', isEqualTo: legacyCandidates[2]));

    final byLegacyStrings = _combineMeetupStreams(byLegacyString1,
        _combineMeetupStreams(byLegacyString2, byLegacyString3));

    return _combineMeetupStreams(
        byDateKey, _combineMeetupStreams(byTimestampRange, byLegacyStrings));
  }

  // Firestore 문서를 Meetup 객체 리스트로 변환하는 헬퍼 메서드
  List<Meetup> _convertToMeetups(QuerySnapshot snapshot) {
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;

      final meetupDate = _parseMeetupDateFromFirestore(data);
      final createdAt = _parseCreatedAtFromFirestore(data);

      return Meetup(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        location: data['location'] ?? '',
        time: data['time'] ?? '',
        maxParticipants: data['maxParticipants'] ?? 0,
        currentParticipants: data['currentParticipants'] ?? 1,
        host: data['hostNickname'] ?? '익명',
        hostNationality: data['hostNickname'] == 'dev99'
            ? '한국'
            : (data['hostNationality'] ?? ''), // 테스트 목적으로 dev99인 경우 한국으로 설정
        hostPhotoURL: data['hostPhotoURL'] ?? '',
        imageUrl: data['thumbnailImageUrl'] ?? '',
        thumbnailContent: data['thumbnailContent'] ?? '',
        thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
        imageUrls: (data['imageUrls'] is List)
            ? List<String>.from(data['imageUrls'] as List)
                .map((e) => e.toString())
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : ((data['thumbnailImageUrl'] ?? '').toString().trim().isNotEmpty
                ? [data['thumbnailImageUrl'].toString().trim()]
                : const []),
        date: meetupDate,
        createdAt: createdAt,
        category: data['category'] ?? '기타',
        userId: data['ownerId'] ?? data['userId'], // 모임 주최자 ID 추가
        hostNickname: data['hostNickname'], // 주최자 닉네임 추가
        visibility: data['visibilityMode'] ?? data['visibility'] ?? 'public',
        visibleToCategoryIds:
            ((data['sourceGroupIds'] ?? data['visibleToCategoryIds']) is List)
                ? List<String>.from(
                    (data['sourceGroupIds'] ?? data['visibleToCategoryIds'])
                        as List,
                  )
                : const [],
        allowedUserIds:
            ((data['audienceUserIdsFrozen'] ?? data['allowedUserIds']) is List)
                ? List<String>.from(
                    (data['audienceUserIdsFrozen'] ?? data['allowedUserIds'])
                        as List,
                  )
                : const [],
        visibilitySchemaVersion:
            (data['visibilitySchemaVersion'] as num?)?.toInt() ?? 0,
        visibilityLockedAt: data['visibilityLockedAt'] is Timestamp
            ? (data['visibilityLockedAt'] as Timestamp).toDate()
            : null,
        requiresHanyangVerification:
            data['requiresHanyangVerification'] == true,
        isCompleted: data['isCompleted'] ?? false,
        hasReview: data['hasReview'] ?? false,
        groupChatEnabled: data['groupChatEnabled'] ?? false,
        isConfirmed: data['isConfirmed'] ?? false,
        publicDurationHours: (data['publicDurationHours'] as num?)?.toInt(),
        publicExpiresAt: data['publicExpiresAt'] is Timestamp
            ? (data['publicExpiresAt'] as Timestamp).toDate()
            : null,
        publicWindowStatus: (data['publicWindowStatus'] ?? '').toString(),
        snackChatId: (data['snackChatId'] ?? '').toString().trim().isEmpty
            ? null
            : data['snackChatId'].toString().trim(),
        reviewId: data['reviewId'],
        viewCount: data['viewCount'] ?? 0,
        commentCount: data['commentCount'] ?? 0,
      );
    }).toList();
  }

  // 특정 ID의 모임 가져오기
  Future<Meetup?> getMeetupById(String meetupId) async {
    try {
      final user = _auth.currentUser;
      final doc = await _firestore.collection('meetups').doc(meetupId).get();

      if (!doc.exists || doc.data() == null) {
        return null;
      }

      final data = Map<String, dynamic>.from(doc.data()!);

      // 공개 대상은 게시 시점 데이터 그대로 읽는다. 상세 화면 진입 시 현재
      // 친구/그룹 상태로 과거 allowedUserIds를 보정하지 않는다.

      final meetupDate = _parseMeetupDateFromFirestore(data);

      final meetup = Meetup(
        id: doc.id,
        title: data['title'] ?? '',
        description: data['description'] ?? '',
        location: data['location'] ?? '',
        time: data['time'] ?? '',
        maxParticipants: data['maxParticipants'] ?? 0,
        currentParticipants: data['currentParticipants'] ?? 1,
        host: data['hostNickname'] ?? '익명',
        hostNationality: data['hostNickname'] == 'dev99'
            ? '한국'
            : (data['hostNationality'] ?? ''), // 테스트 목적으로 dev99인 경우 한국으로 설정
        hostPhotoURL: data['hostPhotoURL'] ?? '',
        imageUrl: data['thumbnailImageUrl'] ?? '',
        thumbnailContent: data['thumbnailContent'] ?? '',
        thumbnailImageUrl: data['thumbnailImageUrl'] ?? '',
        imageUrls: (data['imageUrls'] is List)
            ? List<String>.from(data['imageUrls'] as List)
                .map((e) => e.toString())
                .map((s) => s.trim())
                .where((s) => s.isNotEmpty)
                .toList()
            : ((data['thumbnailImageUrl'] ?? '').toString().trim().isNotEmpty
                ? [data['thumbnailImageUrl'].toString().trim()]
                : const []),
        date: meetupDate,
        category: data['category'] ?? '기타', // 카테고리 필드 추가
        userId: data['ownerId'] ?? data['userId'], // 모임 주최자 ID 추가
        hostNickname: data['hostNickname'], // 주최자 닉네임 추가
        visibility: data['visibilityMode'] ?? data['visibility'] ?? 'public',
        visibleToCategoryIds:
            ((data['sourceGroupIds'] ?? data['visibleToCategoryIds']) is List)
                ? List<String>.from(
                    (data['sourceGroupIds'] ?? data['visibleToCategoryIds'])
                        as List,
                  )
                : const [],
        allowedUserIds:
            ((data['audienceUserIdsFrozen'] ?? data['allowedUserIds']) is List)
                ? List<String>.from(
                    (data['audienceUserIdsFrozen'] ?? data['allowedUserIds'])
                        as List,
                  )
                : const [],
        visibilitySchemaVersion:
            (data['visibilitySchemaVersion'] as num?)?.toInt() ?? 0,
        visibilityLockedAt: data['visibilityLockedAt'] is Timestamp
            ? (data['visibilityLockedAt'] as Timestamp).toDate()
            : null,
        requiresHanyangVerification:
            data['requiresHanyangVerification'] == true,
        isCompleted: data['isCompleted'] ?? false, // 모임 완료 여부
        hasReview: data['hasReview'] ?? false, // 후기 작성 여부
        isConfirmed: data['isConfirmed'] ?? false,
        publicDurationHours: (data['publicDurationHours'] as num?)?.toInt(),
        publicExpiresAt: data['publicExpiresAt'] is Timestamp
            ? (data['publicExpiresAt'] as Timestamp).toDate()
            : null,
        publicWindowStatus: (data['publicWindowStatus'] ?? '').toString(),
        reviewId: data['reviewId'], // 후기 ID
        viewCount: data['viewCount'] ?? 0,
        commentCount: data['commentCount'] ?? 0,
      );

      if (!meetup.isPublishedAt()) return null;

      // 🔒 단건 조회에서도 공개범위/차단 필터 적용 (검색/홈과 동일 기준)
      if (user == null) {
        // 비로그인: 전체 공개만 허용
        if (meetup.visibility != 'public') return null;
        return meetup;
      }

      final visibilityFiltered = await filterMeetupsForCurrentUser([meetup]);
      if (visibilityFiltered.isEmpty) return null;

      final blockedFiltered =
          await ContentFilterService.filterMeetups(visibilityFiltered);
      if (blockedFiltered.isEmpty) return null;

      return blockedFiltered.first;
    } catch (e) {
      Logger.error('모임 정보 불러오기 오류: $e');
      return null;
    }
  }

  /// 현재 사용자 기준으로 모임 공개 범위를 필터링합니다.
  /// - Home 화면의 "기본 모임 리스트"와 동일한 기준(친구/카테고리 공개 포함)
  Future<List<Meetup>> filterMeetupsForCurrentUser(
    List<Meetup> meetups, {
    List<String>? categoryIds,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return [];
      return meetups.where((meetup) {
        if (!meetup.isPublishedAt()) return false;
        final canRead = FrozenAudiencePolicy.canRead(
          viewerId: user.uid,
          ownerId: meetup.userId ?? '',
          visibilityMode: meetup.visibility,
          audienceUserIdsFrozen: meetup.allowedUserIds,
        );
        if (!canRead) return false;
        // 화면의 그룹 필터는 sourceGroupIds 표시에만 사용한다. 실제 접근 권한은
        // 생성 시 고정된 allowedUserIds로 이미 판정했다.
        return categoryIds == null ||
            meetup.visibleToCategoryIds.any(categoryIds.contains);
      }).toList(growable: false);
    } catch (e) {
      Logger.error('❌ 모임 공개 범위 필터링 오류: $e');
      return [];
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

  // Firebase 연결 테스트 메서드
  Future<bool> testFirebaseConnection() async {
    try {
      Logger.log('🔗 [TEST] Firebase 연결 테스트 시작');

      final testQuery = await _firestore
          .collection('meetups')
          .where('visibility', isEqualTo: 'public')
          .limit(1)
          .get(const GetOptions(source: Source.server));

      Logger.log('✅ [TEST] Firebase 연결 성공 - 문서 수: ${testQuery.docs.length}');
      return true;
    } catch (e) {
      Logger.error('❌ [TEST] Firebase 연결 실패: $e');
      return false;
    }
  }

  // 모임 검색 메서드 추가
  Stream<List<Meetup>> searchMeetups(String query) {
    Logger.log('🔍 [SERVICE] 검색 시작: "$query"');

    if (query.trim().isEmpty) {
      Logger.log('⚠️ [SERVICE] 빈 검색어 - 빈 결과 반환');
      // 빈 검색어인 경우 빈 결과 반환
      return Stream.value([]);
    }

    // 소문자로 변환하여 대소문자 구분 없이 검색
    final lowercaseQuery = query.trim().toLowerCase();
    Logger.log('🔍 [SERVICE] 정규화된 검색어: "$lowercaseQuery"');

    // 현재 날짜 이후의 모임 중에서 검색
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    Logger.log('📅 [SERVICE] 검색 기준 날짜: $today');

    return _watchAudienceScopedMeetupQuery(_firestore
            .collection('meetups')
            .where('date', isGreaterThanOrEqualTo: today)
            .orderBy('date', descending: false))
        .map((meetups) {
      final matched = meetups.where((meetup) {
        return meetup.title.toLowerCase().contains(lowercaseQuery) ||
            meetup.description.toLowerCase().contains(lowercaseQuery) ||
            meetup.location.toLowerCase().contains(lowercaseQuery) ||
            (meetup.hostNickname ?? meetup.host)
                .toLowerCase()
                .contains(lowercaseQuery);
      }).toList();
      Logger.log('📋 [SERVICE] 최종 검색 결과: ${matched.length}개');
      return matched;
    }).handleError((error) {
      Logger.error('❌ [SERVICE] 검색 스트림 오류: $error');
      throw error;
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

      final meetups = await _getAudienceScopedMeetupQuery(_firestore
          .collection('meetups')
          .where('date', isGreaterThanOrEqualTo: today)
          .orderBy('date', descending: false));
      return meetups.where((meetup) {
        return meetup.title.toLowerCase().contains(lowercaseQuery) ||
            meetup.description.toLowerCase().contains(lowercaseQuery) ||
            meetup.location.toLowerCase().contains(lowercaseQuery) ||
            (meetup.hostNickname ?? meetup.host)
                .toLowerCase()
                .contains(lowercaseQuery);
      }).toList();
    } catch (e) {
      Logger.error('모임 검색 오류: $e');
      return [];
    }
  }

  // 특정 요일에 해당하는 날짜 계산
  DateTime getDayDate(int dayIndex) {
    final List<DateTime> weekDates = getWeekDates();
    return weekDates[dayIndex];
  }

  // 모임 참여 (meetup_participants 컬렉션 사용, 즉시 승인)
  Future<bool> joinMeetup(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 로그인 필요');
        return false;
      }
      final callable =
          FirebaseFunctions.instance.httpsCallable('joinMeetupSecure');
      final response = await callable.call<Map<String, dynamic>>({
        'meetupId': meetupId,
      });
      if (response.data['joined'] != true) return false;

      _cacheService.invalidateCache(meetupId, user.uid);
      Logger.log('✅ 서버 검증 기반 모임 참여 성공: $meetupId');
      return true;
    } on FirebaseFunctionsException catch (e) {
      Logger.warning('모임 참여 서버 차단: ${e.code} / ${e.message}');
      return false;
    } catch (e) {
      Logger.error('모임 참여 오류: $e');
      return false;
    }
  }

  // 모임 참여 취소 (meetup_participants 삭제)
  Future<bool> leaveMeetup(String meetupId) async {
    // cancelMeetupParticipation 쪽에 로그/알림까지 통합되어 있음
    return cancelMeetupParticipation(meetupId);
  }

  /// 호스트가 참여자를 모임에서 퇴장(강퇴)시키기
  /// - meetup_participants/{meetupId}_{targetUserId} 삭제
  /// - meetups/{meetupId}.currentParticipants 감소 (최소 1 보장: 호스트)
  Future<bool> kickParticipant({
    required String meetupId,
    required String targetUserId,
  }) async {
    try {
      final me = _auth.currentUser;
      if (me == null) return false;
      if (targetUserId == me.uid) return false; // 자기 자신 퇴장 방지

      final meetupRef = _firestore.collection('meetups').doc(meetupId);
      final participantId = '${meetupId}_$targetUserId';
      final participantRef =
          _firestore.collection('meetup_participants').doc(participantId);

      // 호스트 권한 확인 (클라이언트 방어; 서버 규칙이 있다면 그쪽이 최종 권한)
      final meetupDoc = await meetupRef.get();
      if (!meetupDoc.exists) return false;
      final hostId = meetupDoc.data()?['userId']?.toString();
      final meetupTitle = meetupDoc.data()?['title']?.toString() ?? '';
      if (hostId == null || hostId != me.uid) return false;

      await _firestore.runTransaction((tx) async {
        final pDoc = await tx.get(participantRef);
        if (!pDoc.exists) return;

        tx.delete(participantRef);

        final mDoc = await tx.get(meetupRef);
        if (mDoc.exists) {
          final data = mDoc.data() as Map<String, dynamic>? ?? const {};
          final cur = (data['currentParticipants'] is int)
              ? (data['currentParticipants'] as int)
              : 1;
          final next = cur > 1 ? cur - 1 : 1;
          tx.update(meetupRef, {
            'currentParticipants': next,
            'updatedAt': FieldValue.serverTimestamp(),
            _kickedUserIdsField: FieldValue.arrayUnion([targetUserId]),
          });
        }
      });

      // 동기화 검증 (선택적)
      await _validateParticipantCount(meetupId);

      // 캐시 무효화 (강퇴된 유저의 참여 상태)
      _cacheService.invalidateCache(meetupId, targetUserId);

      // ✅ 강퇴 로그 (닉네임은 participants 컬렉션이 삭제되면 못 가져오므로 user 문서에서 best-effort)
      String targetName = 'User';
      try {
        final uDoc =
            await _firestore.collection('users').doc(targetUserId).get();
        final data = uDoc.data();
        targetName = (data?['nickname'] ?? '').toString().trim().isNotEmpty
            ? (data?['nickname'] ?? '').toString().trim()
            : 'User';
      } catch (_) {}
      String hostName = 'Host';
      try {
        final hDoc = await _firestore.collection('users').doc(me.uid).get();
        final data = hDoc.data();
        hostName = (data?['nickname'] ?? '').toString().trim().isNotEmpty
            ? (data?['nickname'] ?? '').toString().trim()
            : 'Host';
      } catch (_) {}
      unawaited(_logParticipantEvent(
        meetupId: meetupId,
        meetupTitle: meetupTitle,
        type: 'kick',
        actorId: me.uid,
        actorName: hostName,
        targetUserId: targetUserId,
        targetUserName: targetName,
      ));

      Logger.log('✅ 참여자 퇴장 처리 성공: $meetupId -> $targetUserId');
      return true;
    } catch (e) {
      Logger.error('❌ 참여자 퇴장 처리 실패: $e');
      return false;
    }
  }

  // 기존 leaveMeetup (배열 기반 - 사용 안함, 참고용으로 주석 처리)
  Future<bool> _leaveMeetupOld(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final meetupRef = _firestore.collection('meetups').doc(meetupId);

      // 트랜잭션으로 안전하게 참여자 제거
      bool success = await _firestore.runTransaction<bool>((transaction) async {
        final meetupDoc = await transaction.get(meetupRef);
        if (!meetupDoc.exists) return false;

        final data = meetupDoc.data()!;
        final List<dynamic> participants =
            List.from(data['participants'] ?? []);

        // 참여하지 않은 상태인지 확인
        if (!participants.contains(user.uid)) {
          Logger.log('참여하지 않은 모임: $meetupId');
          return false;
        }

        // 참여자에서 제거
        participants.remove(user.uid);

        // 참여자 수 업데이트 (주최자는 제외하고 계산)
        final currentParticipants = data['currentParticipants'] ?? 1;
        final newParticipantCount =
            currentParticipants > 1 ? currentParticipants - 1 : 1;

        transaction.update(meetupRef, {
          'participants': participants,
          'currentParticipants': newParticipantCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });

        return true;
      });

      if (success) {
        Logger.log('✅ 모임 참여 취소 성공: $meetupId');
      }

      return success;
    } catch (e) {
      Logger.error('❌ 모임 참여 취소 실패: $e');
      return false;
    }
  }

  //모임 삭제
  Future<bool> deleteMeetup(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('❌ 모임 삭제 실패: 로그인되지 않은 사용자');
        return false;
      }

      Logger.log('🗑️ 모임 삭제 시작: meetupId=$meetupId, currentUser=${user.uid}');

      // 모임 문서 가져오기 (서버에서 최신 데이터 가져오기)
      final meetupDoc = await _firestore
          .collection('meetups')
          .doc(meetupId)
          .get(const GetOptions(source: Source.server));

      // 문서가 없는 경우
      if (!meetupDoc.exists) {
        Logger.error('❌ 모임 삭제 실패: 모임 문서가 존재하지 않음');
        return false;
      }

      final data = meetupDoc.data()!;
      Logger.log(
          '📄 모임 데이터: userId=${data['userId']}, hostNickname=${data['hostNickname']}, host=${data['host']}');
      Logger.log(
          '📄 후기 정보: hasReview=${data['hasReview']}, reviewId=${data['reviewId']}');

      // 확정된 모임은 어떤 클라이언트 경로에서도 취소(삭제)할 수 없다.
      if (data['isConfirmed'] == true) {
        Logger.warning('⛔ 확정된 모임 삭제 차단: $meetupId');
        return false;
      }

      // 권한 체크: userId가 있으면 userId로, 없으면 hostNickname/host로 비교
      bool isOwner = false;

      if (data['userId'] != null && data['userId'].toString().isNotEmpty) {
        // 새로운 데이터: userId로 비교
        isOwner = data['userId'] == user.uid;
        Logger.log(
            '🔍 userId 기반 권한 체크: ${data['userId']} == ${user.uid} → $isOwner');
      } else {
        // 기존 데이터: 현재 사용자 닉네임과 비교
        final hostToCheck = data['hostNickname'] ?? data['host'];
        if (hostToCheck != null && hostToCheck.toString().isNotEmpty) {
          // 현재 사용자 닉네임 가져오기
          final userDoc =
              await _firestore.collection('users').doc(user.uid).get();
          if (userDoc.exists) {
            final userData = userDoc.data();
            final currentUserNickname = userData?['nickname'] as String?;

            if (currentUserNickname != null && currentUserNickname.isNotEmpty) {
              isOwner =
                  hostToCheck.toString().trim() == currentUserNickname.trim();
              Logger.log(
                  '🔍 닉네임 기반 권한 체크: "$hostToCheck" == "$currentUserNickname" → $isOwner');
            }
          }
        }
      }

      if (!isOwner) {
        Logger.error('❌ 모임 삭제 실패: 권한 없음 (현재 사용자가 주최자가 아님)');
        return false;
      }

      // 후기가 있는 경우 후기 관련 데이터도 삭제
      final reviewId = data['reviewId'] as String?;
      if (reviewId != null && reviewId.isNotEmpty) {
        Logger.log('🗑️ 후기 관련 데이터 삭제 시작: reviewId=$reviewId');

        try {
          // 1. meetup_reviews 문서 삭제 (Cloud Function이 자동으로 users/{userId}/posts 삭제)
          await _firestore.collection('meetup_reviews').doc(reviewId).delete();
          Logger.log('✅ meetup_reviews 삭제 완료');

          // 2. review_requests 문서들 삭제
          final reviewRequestsSnapshot = await _firestore
              .collection('review_requests')
              .where('metadata.reviewId', isEqualTo: reviewId)
              .get();

          for (var doc in reviewRequestsSnapshot.docs) {
            await doc.reference.delete();
          }
          Logger.log(
              '✅ review_requests ${reviewRequestsSnapshot.docs.length}개 삭제 완료');
        } catch (e) {
          Logger.error('⚠️ 후기 데이터 삭제 중 오류 (계속 진행): $e');
        }
      }

      // 3. meetup_participants 문서들 삭제
      try {
        final participantsSnapshot = await _firestore
            .collection('meetup_participants')
            .where('meetupId', isEqualTo: meetupId)
            .get();

        for (var doc in participantsSnapshot.docs) {
          await doc.reference.delete();
        }
        Logger.log(
            '✅ meetup_participants ${participantsSnapshot.docs.length}개 삭제 완료');
      } catch (e) {
        Logger.error('⚠️ 참여자 데이터 삭제 중 오류 (계속 진행): $e');
      }

      // 4. 모임 문서 삭제
      await _firestore.collection('meetups').doc(meetupId).delete();
      Logger.log('✅ 모임 삭제 성공: meetupId=$meetupId');
      return true;
    } catch (e) {
      Logger.error('❌ 모임 삭제 오류: $e');
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
      Logger.error('주최자 확인 오류: $e');
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
          .get();

      var participants = querySnapshot.docs
          .map((doc) => MeetupParticipant.fromJson(doc.data()))
          .toList();
      participants = await _resolveLatestParticipantProfiles(participants);
      participants.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
      return participants;
    } catch (e) {
      Logger.error('참여자 목록 조회 오류: $e');
      return [];
    }
  }

  /// 특정 상태의 참여자만 조회
  Future<List<MeetupParticipant>> getMeetupParticipantsByStatus(
    String meetupId,
    String status,
  ) async {
    try {
      Logger.log('🔍 참여자 조회 시작: meetupId=$meetupId, status=$status');

      // orderBy 제거하여 복합 인덱스 문제 회피
      final querySnapshot = await _firestore
          .collection('meetup_participants')
          .where('meetupId', isEqualTo: meetupId)
          .where('status', isEqualTo: status)
          .get();

      Logger.log('📊 조회 결과: ${querySnapshot.docs.length}명의 참여자');

      var participants = querySnapshot.docs.map((doc) {
        Logger.log('  - 참여자: ${doc.data()['userName']} (${doc.id})');
        return MeetupParticipant.fromJson(doc.data());
      }).toList();

      participants = await _resolveLatestParticipantProfiles(participants);

      // 클라이언트 측에서 정렬
      participants.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));

      return participants;
    } catch (e) {
      Logger.error('❌ 참여자 목록 조회 오류: $e');
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

      Logger.log('✅ 참여자 상태 업데이트 성공: $participantId -> $newStatus');
      return true;
    } catch (e) {
      Logger.error('❌ 참여자 상태 업데이트 실패: $e');
      return false;
    }
  }

  /// 참여자 승인
  Future<bool> approveParticipant(String participantId) async {
    return await updateParticipantStatus(
        participantId, ParticipantStatus.approved);
  }

  /// 참여자 거절
  Future<bool> rejectParticipant(String participantId) async {
    return await updateParticipantStatus(
        participantId, ParticipantStatus.rejected);
  }

  /// 참여자 제거 (모임에서 완전히 제거)
  Future<bool> removeParticipant(String participantId) async {
    try {
      await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .delete();

      Logger.log('✅ 참여자 제거 성공: $participantId');
      return true;
    } catch (e) {
      Logger.error('❌ 참여자 제거 실패: $e');
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
        userName: (userData['nickname'] ?? '').toString().trim().isNotEmpty
            ? userData['nickname'].toString().trim()
            : '익명',
        userEmail: user.email ?? '',
        userProfileImage: userData['photoURL'],
        joinedAt: DateTime.now(),
        status: ParticipantStatus.pending,
        message: message,
        userCountry: userData['nationality'] ?? '', // 국가 정보 추가
      );

      await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .set(participant.toJson());

      Logger.log('✅ 모임 참여 신청 성공: $meetupId');
      return true;
    } catch (e) {
      Logger.error('❌ 모임 참여 신청 실패: $e');
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
      Logger.error('참여 상태 확인 오류: $e');
      return null;
    }
  }

  /// 실시간 참여자 수 조회 (호스트 포함)
  Future<int> getRealTimeParticipantCount(String meetupId) async {
    try {
      // 승인된 참여자 수 조회
      final participantsQuery = await _firestore
          .collection('meetup_participants')
          .where('meetupId', isEqualTo: meetupId)
          .where('status', isEqualTo: 'approved')
          .get();

      // 호스트 포함하여 +1
      final participantCount = participantsQuery.docs.length + 1;
      return participantCount;
    } catch (e) {
      Logger.error('❌ 실시간 참여자 수 조회 오류: $e');
      // 오류 시 Firestore 필드값 사용
      try {
        final meetupDoc =
            await _firestore.collection('meetups').doc(meetupId).get();
        if (meetupDoc.exists) {
          final currentParticipants =
              meetupDoc.data()?['currentParticipants'] ?? 1;
          Logger.log('📋 Firestore 필드값 사용: $currentParticipants명');
          return currentParticipants;
        }
      } catch (fallbackError) {
        Logger.error('❌ Firestore 필드값 조회도 실패: $fallbackError');
      }
      return 1; // 최소 호스트 1명
    }
  }

  /// 참여자 수를 실시간으로 스트리밍합니다 (호스트 포함).
  /// - `meetup_participants`에서 `approved` 문서 수 + 1(호스트)
  Stream<int> participantCountStream(String meetupId, {int fallback = 1}) {
    return _firestore
        .collection('meetup_participants')
        .where('meetupId', isEqualTo: meetupId)
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .map((snapshot) => snapshot.size + 1)
        .handleError((e) {
      Logger.error('❌ 참여자 수 스트림 오류: $e');
    }).map((v) => v <= 0 ? fallback : v);
  }

  /// 참여자 수 동기화 검증 및 수정
  Future<void> _validateParticipantCount(String meetupId) async {
    try {
      // 실제 참여자 수 조회
      final realCount = await getRealTimeParticipantCount(meetupId);

      // Firestore 필드값 조회
      final meetupDoc =
          await _firestore.collection('meetups').doc(meetupId).get();
      if (!meetupDoc.exists) return;

      final storedCount = meetupDoc.data()?['currentParticipants'] ?? 1;

      // 불일치 시 수정
      if (realCount != storedCount) {
        Logger.log(
            '⚠️ 참여자 수 불일치 감지: $meetupId (실제: $realCount, 저장된 값: $storedCount)');
        await _firestore.collection('meetups').doc(meetupId).update({
          'currentParticipants': realCount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        Logger.log('✅ 참여자 수 동기화 완료: $meetupId -> $realCount명');
      }
    } catch (e) {
      Logger.error('❌ 참여자 수 검증 오류: $e');
    }
  }

  /// 모임 참여 취소
  Future<bool> cancelMeetupParticipation(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      // 참여자 문서 ID 생성
      final participantId = '${meetupId}_${user.uid}';

      // 먼저 문서가 존재하는지 확인
      final participantDoc = await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .get();

      if (!participantDoc.exists) {
        Logger.log('⚠️ 참여자 문서가 존재하지 않음: $participantId');
        return false;
      }

      // 호스트/모임 타이틀 확보 (알림/로그용)
      final meetupDoc =
          await _firestore.collection('meetups').doc(meetupId).get();
      final meetupData = meetupDoc.data() ?? const <String, dynamic>{};
      // ⛔️ 과거(만료) 모임은 나가기(상태 변경) 불가
      if (meetupData.isNotEmpty &&
          _isMeetupExpiredFromMeetupDocData(meetupData)) {
        Logger.log('⛔️ 만료된 모임 나가기 차단: $meetupId');
        return false;
      }
      final hostId = meetupData['userId']?.toString() ?? '';
      final meetupTitle = meetupData['title']?.toString() ?? '';

      // 참여자 이름 확보 (문서에 있으면 그걸 사용)
      final pData = participantDoc.data() as Map<String, dynamic>? ?? const {};
      final participantName = (pData['userName'] ??
              pData['userNickname'] ??
              pData['nickname'] ??
              '익명')
          .toString();

      // 문서 삭제
      await _firestore
          .collection('meetup_participants')
          .doc(participantId)
          .delete();

      // 모임의 currentParticipants 감소
      final meetupRef = _firestore.collection('meetups').doc(meetupId);
      await _firestore.runTransaction((transaction) async {
        final meetupDoc = await transaction.get(meetupRef);
        if (meetupDoc.exists) {
          final currentCount = meetupDoc.data()?['currentParticipants'] ?? 1;
          transaction.update(meetupRef, {
            'currentParticipants': currentCount > 0 ? currentCount - 1 : 0,
          });
        }
      });

      // 🔧 캐시 무효화 (참여 상태 변경됨)
      _cacheService.invalidateCache(meetupId, user.uid);

      Logger.log('✅ 모임 참여 취소 성공: $meetupId');

      // ✅ 나가기 이벤트 로그 + 호스트 알림
      if (hostId.isNotEmpty) {
        unawaited(_logParticipantEvent(
          meetupId: meetupId,
          meetupTitle: meetupTitle,
          type: 'leave',
          actorId: user.uid,
          actorName: participantName,
          targetUserId: user.uid,
          targetUserName: participantName,
        ));
        unawaited(_notificationService.sendMeetupParticipantLeftNotification(
          hostId: hostId,
          meetupId: meetupId,
          meetupTitle: meetupTitle,
          participantId: user.uid,
          participantName: participantName,
        ));
      }

      return true;
    } catch (e) {
      Logger.error('❌ 모임 참여 취소 실패: $e');
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

      // 디버그: Logger.log('🔍 모임 필터링 시작: categoryIds = $categoryIds');

      // 1. 전체 모임 가져오기 (현재 날짜 이후만)
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final allMeetups = await _getAudienceScopedMeetupQuery(_firestore
          .collection('meetups')
          .where('date', isGreaterThanOrEqualTo: today)
          .orderBy('date', descending: false));

      // 공개 대상은 생성 시점에 고정된다. 현재 친구/그룹 문서를 다시 읽으면
      // 과거 모임의 공개 범위가 소급 변경되므로 저장된 스냅샷만 사용한다.
      final filteredMeetups = <Meetup>[];
      for (final meetup in allMeetups) {
        final canRead = FrozenAudiencePolicy.canRead(
          viewerId: user.uid,
          ownerId: meetup.userId ?? '',
          visibilityMode: meetup.visibility,
          audienceUserIdsFrozen: meetup.allowedUserIds,
        );
        if (!canRead) continue;

        // 이 인자는 콘텐츠 공개 범위를 다시 계산하는 값이 아니라, 생성 당시
        // 저장된 sourceGroupIds를 기준으로 화면을 좁히는 로컬 필터일 뿐이다.
        final matchesRequestedFilter = categoryIds == null ||
            (categoryIds.isEmpty
                ? meetup.visibility == 'public'
                : meetup.sourceGroupIds.any(categoryIds.contains));
        if (matchesRequestedFilter) filteredMeetups.add(meetup);
      }

      return filteredMeetups;
    } catch (e) {
      Logger.error('❌ 친구 그룹별 모임 필터링 오류: $e');
      return [];
    }
  }

  // ===== 모임 후기 관련 메서드 =====

  /// 모임장이 예정된 모임을 확정한다.
  Future<bool> confirmMeetup(String meetupId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;
      final response = await FirebaseFunctions.instance
          .httpsCallable('confirmMeetupSecure')
          .call(<String, dynamic>{'meetupId': meetupId}).timeout(
              const Duration(seconds: 20));
      final data = response.data;
      return data is Map && data['success'] == true;
    } catch (error, stackTrace) {
      Logger.error('모임 확정 실패: $error\n$stackTrace');
      return false;
    }
  }

  /// 모임 완료 처리
  Future<bool> markMeetupAsCompleted(String meetupId) async {
    Logger.log('🚀 [SERVICE] 모임 완료 처리 시작: $meetupId');

    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.error('❌ [SERVICE] 사용자 인증 필요');
        return false;
      }
      Logger.log('👤 [SERVICE] 현재 사용자: ${user.uid}');

      // 모임 존재 및 권한 확인
      Logger.log('📡 [SERVICE] Firestore에서 모임 문서 조회 중...');
      final meetupDoc =
          await _firestore.collection('meetups').doc(meetupId).get();

      if (!meetupDoc.exists) {
        Logger.error('❌ [SERVICE] 모임을 찾을 수 없음: $meetupId');
        return false;
      }
      Logger.log('✅ [SERVICE] 모임 문서 존재 확인');

      final meetupData = meetupDoc.data()!;
      final hostUserId = meetupData['userId'];
      Logger.log('🔍 [SERVICE] 권한 확인 - 호스트: $hostUserId, 현재 사용자: ${user.uid}');

      if (hostUserId != user.uid) {
        Logger.error('❌ [SERVICE] 권한 없음 - 모임장만 완료 처리 가능');
        return false;
      }

      // ✅ 요구사항: 정원과 무관하게 "총 3명 이상(모임장 포함)"이면 모임 마감(완료) 가능
      // - currentParticipants는 호스트 포함 값으로 유지되고 있으므로 그대로 사용한다.
      final currentParticipants = (meetupData['currentParticipants'] is int)
          ? (meetupData['currentParticipants'] as int)
          : int.tryParse(
                  (meetupData['currentParticipants'] ?? '0').toString()) ??
              0;
      if (currentParticipants < 3) {
        Logger.log(
            '⏭️ [SERVICE] 완료 처리 불가: 참여자 수 부족 ($currentParticipants명, 최소 3명 필요)');
        return false;
      }

      // 현재 상태 확인
      final currentCompleted = meetupData['isCompleted'] ?? false;
      Logger.log('📋 [SERVICE] 현재 완료 상태: $currentCompleted');

      if (currentCompleted) {
        Logger.log('⚠️ [SERVICE] 이미 완료된 모임');
        return true; // 이미 완료된 경우 성공으로 처리
      }

      // 모임 완료 상태로 업데이트
      Logger.log('📡 [SERVICE] Firestore 업데이트 실행 중...');
      await _firestore.collection('meetups').doc(meetupId).update({
        'isCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      Logger.log('✅ [SERVICE] 모임 완료 처리 성공: $meetupId');

      // 업데이트 확인
      Logger.log('🔍 [SERVICE] 업데이트 결과 확인 중...');
      final updatedDoc =
          await _firestore.collection('meetups').doc(meetupId).get();
      final updatedData = updatedDoc.data();
      Logger.log(
          '📋 [SERVICE] 업데이트 후 상태: isCompleted=${updatedData?['isCompleted']}');

      return true;
    } catch (e) {
      Logger.error('❌ [SERVICE] 모임 완료 처리 오류: $e');
      Logger.error('📍 [SERVICE] 스택 트레이스: ${StackTrace.current}');
      return false;
    }
  }

  /// 모임 후기 생성
  Future<String?> createMeetupReview({
    required String meetupId,
    required List<String> imageUrls, // 여러 이미지 지원
    required String content,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 사용자 인증 필요');
        return null;
      }

      // 모임 정보 가져오기
      final meetupDoc =
          await _firestore.collection('meetups').doc(meetupId).get();
      if (!meetupDoc.exists) {
        Logger.log('❌ 모임을 찾을 수 없음');
        return null;
      }

      final meetupData = meetupDoc.data()!;
      final meetup = Meetup.fromJson({...meetupData, 'id': meetupId});

      // 모임장 확인
      if (meetup.userId != user.uid) {
        Logger.log('❌ 모임장만 후기 작성 가능');
        return null;
      }

      // 확정된 모임은 기존 완료 모임과 동일한 후기 플로우를 사용한다.
      if (!meetup.canStartReview) {
        Logger.log('❌ 확정되거나 완료된 모임이 아님');
        return null;
      }

      if (meetup.hasReview) {
        Logger.log('❌ 이미 후기가 작성된 모임');
        return null;
      }

      // 참여자 목록 가져오기
      final participants =
          await getMeetupParticipantsByStatus(meetupId, 'approved');
      final participantIds = participants
          .where((p) => p.userId != user.uid) // 모임장 제외
          .map((p) => p.userId)
          .toList();

      // 사용자 정보 가져오기
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final authorName =
          (userDoc.data()?['nickname'] ?? '').toString().trim().isNotEmpty
              ? userDoc.data()!['nickname'].toString().trim()
              : '익명';

      // 후기 생성
      final reviewDoc = await _firestore.collection('meetup_reviews').add({
        'meetupId': meetupId,
        'meetupTitle': meetup.title,
        'authorId': user.uid,
        'authorName': authorName,
        'imageUrls': imageUrls, // 여러 이미지 URL 저장
        'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '', // 하위 호환성
        'content': content,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': null,
        'approvedParticipants': [],
        'rejectedParticipants': [],
        'pendingParticipants': participantIds,
      });

      final reviewId = reviewDoc.id;

      // 모임에 후기 ID 저장
      await _firestore.collection('meetups').doc(meetupId).update({
        'hasReview': true,
        'reviewId': reviewId,
        // 확정 상태에서 후기를 작성하면 기존 후기 플로우와
        // 동일하게 추가 참여를 막기 위해 완료 상태로 전환한다.
        'isCompleted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 주최자 프로필에 후기 즉시 게시
      await _publishReviewToUserProfile(
        userId: user.uid,
        reviewId: reviewId,
        reviewData: {
          'meetupId': meetupId,
          'meetupTitle': meetup.title,
          'imageUrls': imageUrls,
          'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '', // 하위 호환성
          'content': content,
        },
      );

      Logger.log(
          '✅ 모임 후기 생성 성공 및 주최자 프로필에 게시: $reviewId (이미지 ${imageUrls.length}장)');
      return reviewId;
    } catch (e) {
      Logger.error('❌ 모임 후기 생성 오류: $e');
      return null;
    }
  }

  /// 모임 후기 조회
  Future<Map<String, dynamic>?> getMeetupReview(String reviewId) async {
    try {
      final reviewDoc =
          await _firestore.collection('meetup_reviews').doc(reviewId).get();
      if (!reviewDoc.exists) {
        Logger.log('❌ 후기를 찾을 수 없음');
        return null;
      }

      return {...reviewDoc.data()!, 'id': reviewDoc.id};
    } catch (e) {
      Logger.error('❌ 모임 후기 조회 오류: $e');
      return null;
    }
  }

  /// 모임 후기 수정
  Future<bool> updateMeetupReview({
    required String reviewId,
    required List<String> imageUrls, // 여러 이미지 지원
    required String content,
  }) async {
    try {
      Logger.log('✏️ 후기 수정 시작: reviewId=$reviewId (이미지 ${imageUrls.length}장)');

      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 사용자 인증 필요');
        return false;
      }

      // 후기 존재 및 권한 확인
      final reviewDoc =
          await _firestore.collection('meetup_reviews').doc(reviewId).get();
      if (!reviewDoc.exists) {
        Logger.log('❌ 후기를 찾을 수 없음');
        return false;
      }

      final reviewData = reviewDoc.data()!;
      if (reviewData['authorId'] != user.uid) {
        Logger.log('❌ 작성자만 후기 수정 가능');
        return false;
      }

      final approvedParticipants =
          List<String>.from(reviewData['approvedParticipants'] ?? []);
      final authorId = reviewData['authorId'];

      Logger.log('📋 수정 대상: 참여자 ${approvedParticipants.length}명');

      // 1. meetup_reviews 문서 업데이트
      Logger.log('✏️ 1단계: meetup_reviews 문서 업데이트...');
      await _firestore.collection('meetup_reviews').doc(reviewId).update({
        'imageUrls': imageUrls,
        'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '', // 하위 호환성
        'content': content,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      Logger.log('✅ meetup_reviews 업데이트 완료');

      // 2. 본인 프로필의 후기 업데이트 (다른 사용자는 Cloud Function에서 처리)
      Logger.log('✏️ 2단계: 본인 프로필 후기 업데이트...');
      final currentUser = _auth.currentUser;

      if (currentUser != null) {
        try {
          // 본인 프로필의 후기만 직접 업데이트
          final postDoc = await _firestore
              .collection('users')
              .doc(currentUser.uid)
              .collection('posts')
              .doc(reviewId)
              .get();

          if (postDoc.exists) {
            await _firestore
                .collection('users')
                .doc(currentUser.uid)
                .collection('posts')
                .doc(reviewId)
                .update({
              'imageUrls': imageUrls,
              'imageUrl': imageUrls.isNotEmpty ? imageUrls.first : '', // 하위 호환성
              'content': content,
              'updatedAt': FieldValue.serverTimestamp(),
            });
            Logger.log('✅ 본인 프로필 후기 업데이트 완료');
          } else {
            Logger.log('⚠️ 본인 프로필에 후기 없음');
          }
        } catch (e) {
          Logger.error('⚠️ 본인 프로필 후기 업데이트 실패: $e');
        }
      }

      // 다른 참여자들의 프로필은 Cloud Function(onMeetupReviewUpdated)에서 자동 처리됨
      Logger.log('💡 다른 참여자 프로필은 Cloud Function에서 자동 업데이트됩니다');
      Logger.log(
          '📋 총 대상자: ${[authorId, ...approvedParticipants].length}명 (본인 포함)');

      Logger.log('✅ 모임 후기 수정 완료: $reviewId');
      return true;
    } catch (e) {
      Logger.error('❌ 모임 후기 수정 오류: $e');
      return false;
    }
  }

  /// 모임 후기 삭제
  Future<bool> deleteMeetupReview(String reviewId) async {
    try {
      Logger.log('🗑️ 후기 삭제 시작: reviewId=$reviewId');

      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 사용자 인증 필요');
        throw Exception('로그인이 필요합니다');
      }

      Logger.log('👤 현재 사용자: ${user.uid}');

      // 후기 존재 및 권한 확인
      final reviewDoc =
          await _firestore.collection('meetup_reviews').doc(reviewId).get();
      if (!reviewDoc.exists) {
        Logger.log('❌ 후기를 찾을 수 없음');
        throw Exception('후기를 찾을 수 없습니다');
      }

      final reviewData = reviewDoc.data()!;
      Logger.log(
          '📄 후기 데이터: authorId=${reviewData['authorId']}, meetupId=${reviewData['meetupId']}');

      if (reviewData['authorId'] != user.uid) {
        Logger.log(
            '❌ 작성자만 후기 삭제 가능: authorId=${reviewData['authorId']}, currentUser=${user.uid}');
        throw Exception('작성자만 후기를 삭제할 수 있습니다');
      }

      final meetupId = reviewData['meetupId'];
      final approvedParticipants =
          List<String>.from(reviewData['approvedParticipants'] ?? []);
      final authorId = reviewData['authorId'];

      Logger.log(
          '📋 삭제 대상: meetupId=$meetupId, 참여자 ${approvedParticipants.length}명');

      // 1. 후기 삭제
      Logger.log('🗑️ 1단계: meetup_reviews 문서 삭제...');
      await _firestore.collection('meetup_reviews').doc(reviewId).delete();
      Logger.log('✅ meetup_reviews 삭제 완료');

      // 2. 모임에서 후기 정보 제거
      Logger.log('🗑️ 2단계: meetups 문서 업데이트...');
      try {
        await _firestore.collection('meetups').doc(meetupId).update({
          'hasReview': false,
          'reviewId': null,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        Logger.log('✅ meetups 업데이트 완료');
      } catch (e) {
        Logger.error('⚠️ meetups 업데이트 실패 (계속 진행): $e');
      }

      // 3. 관련 review_requests도 삭제
      Logger.log('🗑️ 3단계: review_requests 삭제...');
      try {
        final requests = await _firestore
            .collection('review_requests')
            .where('metadata.reviewId', isEqualTo: reviewId)
            .get();

        Logger.log('📋 삭제할 요청: ${requests.docs.length}개');
        for (final doc in requests.docs) {
          await doc.reference.delete();
        }
        Logger.log('✅ review_requests 삭제 완료');
      } catch (e) {
        Logger.error('⚠️ review_requests 삭제 실패 (계속 진행): $e');
      }

      // 4. 모든 참여자 프로필에서 후기 삭제 (주최자 + 수락한 참여자)
      Logger.log('🗑️ 4단계: 프로필 후기 삭제...');
      final allUserIds = [authorId, ...approvedParticipants];
      Logger.log('📋 삭제 대상 사용자: ${allUserIds.length}명');

      for (final userId in allUserIds) {
        try {
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('posts')
              .doc(reviewId)
              .delete();
          Logger.log('✅ 프로필에서 후기 삭제: userId=$userId');
        } catch (e) {
          Logger.error('⚠️ 프로필 후기 삭제 실패 (계속 진행): userId=$userId, error=$e');
        }
      }

      Logger.log('✅ 모임 후기 삭제 완료: $reviewId');
      return true;
    } catch (e, stackTrace) {
      Logger.error('❌ 모임 후기 삭제 오류: $e');
      Logger.log('스택 트레이스: $stackTrace');
      rethrow; // 에러를 다시 던져서 UI에서 처리할 수 있도록
    }
  }

  /// 내가 수락한 모임 후기 목록 가져오기
  Future<List<Map<String, dynamic>>> getMyApprovedReviews() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 사용자 인증 필요');
        return [];
      }

      final reviewsSnapshot = await _firestore
          .collection('meetup_reviews')
          .where('approvedParticipants', arrayContains: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return reviewsSnapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
    } catch (e) {
      Logger.error('❌ 내 후기 목록 조회 오류: $e');
      return [];
    }
  }

  /// 후기 수락 요청 전송
  Future<bool> sendReviewApprovalRequests({
    required String reviewId,
    required List<String> participantIds,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 사용자 인증 필요');
        return false;
      }

      // 후기 정보 가져오기
      final reviewDoc =
          await _firestore.collection('meetup_reviews').doc(reviewId).get();
      if (!reviewDoc.exists) {
        Logger.log('❌ 후기를 찾을 수 없음');
        return false;
      }

      final reviewData = reviewDoc.data()!;
      if ((reviewData['authorId'] ?? '').toString() != user.uid) {
        Logger.log('❌ 후기 작성자만 수락 요청을 보낼 수 있음');
        return false;
      }
      final meetupId = reviewData['meetupId'];
      final meetupTitle = reviewData['meetupTitle'];
      final imageUrl = reviewData['imageUrl'];
      final imageUrls = List<String>.from(
        reviewData['imageUrls'] ??
            <String>[(reviewData['imageUrl'] ?? '').toString()],
      ).where((url) => url.trim().isNotEmpty).toList(growable: false);
      final content = reviewData['content'];

      // 사용자 정보 가져오기
      final userDoc = await _firestore.collection('users').doc(user.uid).get();
      final requesterName =
          (userDoc.data()?['nickname'] ?? '').toString().trim().isNotEmpty
              ? userDoc.data()!['nickname'].toString().trim()
              : '익명';

      // 각 참여자에게 요청 생성
      for (final participantId in participantIds) {
        // 참여자 정보 가져오기
        final participantDoc =
            await _firestore.collection('users').doc(participantId).get();
        final recipientName = (participantDoc.data()?['nickname'] ?? '')
                .toString()
                .trim()
                .isNotEmpty
            ? participantDoc.data()!['nickname'].toString().trim()
            : '익명';

        // review_request 생성
        await _firestore
            .collection('review_requests')
            .doc('${reviewId}_$participantId')
            .set({
          'meetupId': meetupId,
          'requesterId': user.uid,
          'requesterName': requesterName,
          'recipientId': participantId,
          'recipientName': recipientName,
          'meetupTitle': meetupTitle,
          'message': content,
          'imageUrls': imageUrls,
          'imageUrl': imageUrl,
          'status': 'pending',
          'createdAt': FieldValue.serverTimestamp(),
          'respondedAt': null,
          'expiresAt':
              Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
          'metadata': {'reviewId': reviewId},
        });
      }

      Logger.log('✅ 후기 수락 요청 전송 완료: ${participantIds.length}명');
      return true;
    } catch (e) {
      Logger.error('❌ 후기 수락 요청 전송 오류: $e');
      return false;
    }
  }

  /// 레거시 후기에서 누락된 본인의 수락 요청만 복구한다.
  Future<bool> ensureMyReviewApprovalRequest({
    required String reviewId,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) return false;

      final reviewDoc =
          await _firestore.collection('meetup_reviews').doc(reviewId).get();
      if (!reviewDoc.exists) return false;
      final reviewData = reviewDoc.data()!;
      final pendingParticipants =
          List<String>.from(reviewData['pendingParticipants'] ?? const []);
      if (!pendingParticipants.contains(user.uid)) return false;

      final meetupId = (reviewData['meetupId'] ?? '').toString();
      final authorId = (reviewData['authorId'] ?? '').toString();
      if (meetupId.isEmpty || authorId.isEmpty) return false;

      final participantDoc = await _firestore
          .collection('meetup_participants')
          .doc('${meetupId}_${user.uid}')
          .get();
      if (!participantDoc.exists ||
          participantDoc.data()?['status'] != 'approved') {
        return false;
      }

      final users = _firestore.collection('users');
      final requesterDoc = await users.doc(authorId).get();
      final recipientDoc = await users.doc(user.uid).get();
      final requesterName =
          (requesterDoc.data()?['nickname'] ?? '').toString().trim();
      final recipientName =
          (recipientDoc.data()?['nickname'] ?? '').toString().trim();
      final imageUrls = List<String>.from(
        reviewData['imageUrls'] ??
            <String>[(reviewData['imageUrl'] ?? '').toString()],
      ).where((url) => url.trim().isNotEmpty).toList();

      await _firestore
          .collection('review_requests')
          .doc('${reviewId}_${user.uid}')
          .set({
        'meetupId': meetupId,
        'requesterId': authorId,
        'requesterName': requesterName.isEmpty ? '익명' : requesterName,
        'recipientId': user.uid,
        'recipientName': recipientName.isEmpty ? '익명' : recipientName,
        'meetupTitle': (reviewData['meetupTitle'] ?? '').toString(),
        'message': (reviewData['content'] ?? '').toString(),
        'imageUrls': imageUrls,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'respondedAt': null,
        'expiresAt':
            Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
        'metadata': {'reviewId': reviewId},
      });
      return true;
    } catch (error, stackTrace) {
      Logger.error('후기 수락 요청 복구 실패: $error\n$stackTrace');
      return false;
    }
  }

  /// 후기 요청 상태 조회
  Future<Map<String, dynamic>?> getReviewRequestStatus(String requestId) async {
    try {
      final requestDoc =
          await _firestore.collection('review_requests').doc(requestId).get();

      if (!requestDoc.exists) {
        Logger.log('❌ 요청을 찾을 수 없음: $requestId');
        return null;
      }

      return requestDoc.data();
    } catch (e) {
      Logger.error('❌ 요청 상태 조회 오류: $e');
      return null;
    }
  }

  /// 후기 수락/거절 처리
  Future<bool> respondToReviewRequest({
    required String requestId,
    required bool accept,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 사용자 인증 필요');
        return false;
      }

      // 요청 정보 가져오기
      final requestDoc =
          await _firestore.collection('review_requests').doc(requestId).get();
      if (!requestDoc.exists) {
        Logger.log('❌ 요청을 찾을 수 없음');
        return false;
      }

      final requestData = requestDoc.data()!;
      if (requestData['recipientId'] != user.uid) {
        Logger.log('❌ 권한 없음');
        return false;
      }

      final reviewId = (requestData['metadata']?['reviewId'] ?? '').toString();
      if (reviewId.isEmpty) {
        Logger.log('❌ 후기 ID 누락');
        return false;
      }

      // 과거에 수락 상태만 저장되고 프로필 게시가 누락된 경우에도
      // 동일 요청을 다시 열면 프로필 문서를 복구한다.
      final currentStatus = requestData['status'];
      if (currentStatus == 'accepted') {
        await _publishReviewToUserProfile(
          userId: user.uid,
          reviewId: reviewId,
          reviewData: requestData,
        );
        Logger.log('✅ 기존 수락 후기 프로필 게시 상태 확인 완료');
        return true;
      }
      if (currentStatus == 'rejected') {
        Logger.log('⚠️ 이미 거절한 요청입니다');
        return false;
      }

      final reviewRef = _firestore.collection('meetup_reviews').doc(reviewId);
      final reviewDoc = await reviewRef.get();
      if (!reviewDoc.exists) {
        Logger.log('❌ 후기를 찾을 수 없음: $reviewId');
        return false;
      }
      final reviewData = reviewDoc.data()!;
      final approvedParticipants =
          List<String>.from(reviewData['approvedParticipants'] ?? const []);
      final rejectedParticipants =
          List<String>.from(reviewData['rejectedParticipants'] ?? const []);

      // 후기에 사용자 추가/제거
      if (accept) {
        if (!approvedParticipants.contains(user.uid)) {
          await reviewRef.update({
            'approvedParticipants': FieldValue.arrayUnion([user.uid]),
            'pendingParticipants': FieldValue.arrayRemove([user.uid]),
          });
        }

        // 후기를 사용자 프로필에 게시
        await _publishReviewToUserProfile(
          userId: user.uid,
          reviewId: reviewId,
          reviewData: requestData,
        );

        await _firestore.collection('review_requests').doc(requestId).update({
          'status': 'accepted',
          'respondedAt': FieldValue.serverTimestamp(),
        });

        Logger.log('✅ 후기 수락 완료 및 프로필에 게시됨');
      } else {
        if (!rejectedParticipants.contains(user.uid)) {
          await reviewRef.update({
            'rejectedParticipants': FieldValue.arrayUnion([user.uid]),
            'pendingParticipants': FieldValue.arrayRemove([user.uid]),
          });
        }
        await _firestore.collection('review_requests').doc(requestId).update({
          'status': 'rejected',
          'respondedAt': FieldValue.serverTimestamp(),
        });
        Logger.log('✅ 후기 거절 완료');
      }

      return true;
    } catch (e) {
      Logger.error('❌ 후기 수락/거절 처리 오류: $e');
      return false;
    }
  }

  /// 내가 받은 후기 요청 목록 가져오기
  Future<List<Map<String, dynamic>>> getMyReviewRequests() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 사용자 인증 필요');
        return [];
      }

      final requestsSnapshot = await _firestore
          .collection('review_requests')
          .where('recipientId', isEqualTo: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      return requestsSnapshot.docs
          .map((doc) => {...doc.data(), 'id': doc.id})
          .toList();
    } catch (e) {
      Logger.error('❌ 내 후기 요청 목록 조회 오류: $e');
      return [];
    }
  }

  /// 수락은 완료됐지만 프로필 게시가 누락된 과거 후기를 복구한다.
  /// 문서 ID가 reviewId로 고정되어 있어 여러 번 실행해도 중복 생성되지 않는다.
  Future<int> ensureAcceptedReviewsPublishedToCurrentProfile() async {
    final user = _auth.currentUser;
    if (user == null) return 0;

    try {
      final requests = await _firestore
          .collection('review_requests')
          .where('recipientId', isEqualTo: user.uid)
          .get();
      var repairedCount = 0;

      for (final request in requests.docs) {
        final data = request.data();
        if (data['status'] != 'accepted') continue;
        final reviewId = (data['metadata']?['reviewId'] ?? '').toString();
        if (reviewId.isEmpty) continue;

        final profilePost = await _firestore
            .collection('users')
            .doc(user.uid)
            .collection('posts')
            .doc(reviewId)
            .get();
        if (profilePost.exists) continue;

        await _publishReviewToUserProfile(
          userId: user.uid,
          reviewId: reviewId,
          reviewData: data,
        );
        repairedCount++;
      }

      if (repairedCount > 0) {
        Logger.log('✅ 누락된 수락 후기 프로필 복구 완료: $repairedCount개');
      }
      return repairedCount;
    } catch (error, stackTrace) {
      Logger.error('❌ 수락 후기 프로필 복구 실패: $error\n$stackTrace');
      return 0;
    }
  }

  /// 후기를 사용자 프로필에 게시 (내부 헬퍼 메서드)
  Future<void> _publishReviewToUserProfile({
    required String userId,
    required String reviewId,
    required Map<String, dynamic> reviewData,
  }) async {
    try {
      Logger.log('📝 프로필에 후기 게시 시작: userId=$userId, reviewId=$reviewId');
      Logger.log('📝 reviewData: $reviewData');

      // 후기 전체 정보 가져오기
      final reviewDoc =
          await _firestore.collection('meetup_reviews').doc(reviewId).get();
      if (!reviewDoc.exists) {
        Logger.log('❌ 후기를 찾을 수 없음: reviewId=$reviewId');
        return;
      }

      final fullReviewData = reviewDoc.data()!;
      Logger.log('📊 fullReviewData: $fullReviewData');

      final profilePostRef = _firestore
          .collection('users')
          .doc(userId)
          .collection('posts')
          .doc(reviewId);
      if ((await profilePostRef.get()).exists) {
        Logger.log('ℹ️ 프로필 후기 이미 게시됨: userId=$userId, reviewId=$reviewId');
        return;
      }

      final profileUserDoc =
          await _firestore.collection('users').doc(userId).get();
      final profileUserData =
          profileUserDoc.data() ?? const <String, dynamic>{};
      final profileOwnerName =
          (profileUserData['nickname'] ?? '').toString().trim();

      final postData = {
        'type': 'meetup_review',
        'authorId': userId,
        'authorName': profileOwnerName.isEmpty ? '익명' : profileOwnerName,
        'authorProfileImage': (profileUserData['photoURL'] ?? '').toString(),
        'profileOwnerId': userId,
        'meetupId': fullReviewData['meetupId'],
        'meetupTitle': fullReviewData['meetupTitle'],
        'imageUrls': fullReviewData['imageUrls'] ?? [], // 여러 이미지 지원
        'imageUrl': fullReviewData['imageUrl'], // 하위 호환성
        'content': fullReviewData['content'],
        'category': fullReviewData['category'] ?? '모임',
        'participationRole':
            userId == fullReviewData['authorId'] ? 'host' : 'participant',
        'reviewId': reviewId,
        'createdAt':
            fullReviewData['createdAt'] ?? FieldValue.serverTimestamp(),
        'visibility': 'public', // 후기는 공개
        'isHidden': false,
        'likeCount': 0,
        'commentCount': 0,
      };

      Logger.log('📤 저장할 데이터: $postData');
      Logger.log('📍 저장 경로: users/$userId/posts/$reviewId');

      // users/{userId}/posts 컬렉션에 후기 게시
      await profilePostRef.set(postData, SetOptions(merge: true));

      Logger.log('✅ 프로필에 후기 게시 완료: userId=$userId, reviewId=$reviewId');
      Logger.log('✅ 저장된 경로: users/$userId/posts/$reviewId');
    } catch (e, stackTrace) {
      Logger.error('❌ 프로필에 후기 게시 오류: $e');
      Logger.log('❌ Stack trace: $stackTrace');
      // 에러가 발생해도 전체 프로세스는 계속 진행
      rethrow; // 에러를 다시 던져서 상위에서 확인 가능하도록
    }
  }

  /// 후기 숨김/표시 토글
  Future<bool> toggleReviewVisibility({
    required String reviewId,
    required bool hide,
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        Logger.log('❌ 사용자 인증 필요');
        return false;
      }

      // 사용자 프로필의 후기 문서 업데이트
      await _firestore
          .collection('users')
          .doc(user.uid)
          .collection('posts')
          .doc(reviewId)
          .update({
        'isHidden': hide,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      Logger.log('✅ 후기 ${hide ? "숨김" : "표시"} 처리 완료: $reviewId');
      return true;
    } catch (e) {
      Logger.error('❌ 후기 숨김/표시 처리 오류: $e');
      return false;
    }
  }

  // 모임 이미지 업로드
  Future<String> uploadMeetupImage(File imageFile, String meetupId) async {
    try {
      final storage = FirebaseStorage.instance;
      final Reference storageRef = storage.ref().child(
            'meetup_images/$meetupId/${DateTime.now().millisecondsSinceEpoch}',
          );

      await storageRef.putFile(imageFile);
      final imageUrl = await storageRef.getDownloadURL();

      Logger.log('✅ 모임 이미지 업로드 완료: $imageUrl');
      return imageUrl;
    } catch (e) {
      Logger.error('❌ 모임 이미지 업로드 오류: $e');
      throw Exception('이미지 업로드에 실패했습니다: $e');
    }
  }

  // 실시간 모임 데이터 스트림
  Stream<Meetup?> getMeetupStream(String meetupId) {
    Logger.log('📡 [STREAM] getMeetupStream 시작: $meetupId');

    final source = _firestore
        .collection('meetups')
        .doc(meetupId)
        .snapshots()
        .map<List<Meetup>>((snapshot) {
      Logger.log(
          '🔄 [STREAM] 스냅샷 수신 - exists: ${snapshot.exists}, metadata: ${snapshot.metadata}');

      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        data['id'] = snapshot.id;

        final meetup = Meetup.fromJson(data);
        Logger.log(
            '📋 [STREAM] 모임 데이터 파싱 완료: isCompleted=${meetup.isCompleted}, hasReview=${meetup.hasReview}');
        Logger.log(
            '🔍 [STREAM] 메타데이터 - fromCache: ${snapshot.metadata.isFromCache}, hasPendingWrites: ${snapshot.metadata.hasPendingWrites}');

        return <Meetup>[meetup];
      }

      Logger.log('⚠️ [STREAM] 모임 데이터 없음 또는 삭제됨');
      return const <Meetup>[];
    });
    return _hideExpiredMeetupsOverTime(source)
        .map((meetups) => meetups.isEmpty ? null : meetups.first);
  }

  // 모임 조회수 증가 (세션당 1회만)
  Future<void> incrementViewCount(String meetupId) async {
    try {
      // 이미 조회한 모임인지 확인
      if (_viewHistory.hasViewed('meetup', meetupId)) {
        Logger.log('⏭️ 조회수 증가 건너뜀: 이미 조회한 모임 ($meetupId)');
        return;
      }

      await _firestore.collection('meetups').doc(meetupId).update({
        'viewCount': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // 조회 이력에 추가
      _viewHistory.markAsViewed('meetup', meetupId);

      Logger.log('✅ 모임 조회수 증가: $meetupId');
    } catch (e) {
      Logger.error('❌ 모임 조회수 증가 오류: $e');
    }
  }

  // 모임 댓글수 업데이트
  Future<void> updateCommentCount(String meetupId) async {
    try {
      // 해당 모임의 댓글 수 계산
      final querySnapshot = await _firestore
          .collection('comments')
          .where('postId', isEqualTo: meetupId)
          .get();

      final commentCount = querySnapshot.docs.length;

      // 모임 문서의 댓글수 업데이트
      await _firestore.collection('meetups').doc(meetupId).update({
        'commentCount': commentCount,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      Logger.log('✅ 모임 댓글수 업데이트: $meetupId -> $commentCount개');
    } catch (e) {
      Logger.error('❌ 모임 댓글수 업데이트 오류: $e');
    }
  }

  // 간단한 마이그레이션 실행 (개발용)
  Future<void> quickMigration() async {
    try {
      Logger.log('🚀 빠른 마이그레이션 시작...');

      final snapshot = await _firestore.collection('meetups').get();
      Logger.log('📊 총 ${snapshot.docs.length}개 모임 발견');

      WriteBatch batch = _firestore.batch();
      int count = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        Map<String, dynamic> updates = {};

        Logger.log('📋 모임 확인: ${data['title']} (${doc.id})');
        Logger.log('   - 기존 viewCount: ${data['viewCount']}');
        Logger.log('   - 기존 commentCount: ${data['commentCount']}');

        if (!data.containsKey('viewCount')) {
          updates['viewCount'] = 0;
          Logger.log('   → viewCount 추가: 0');
        }

        if (!data.containsKey('commentCount')) {
          // 댓글 수 계산
          final commentsSnapshot = await _firestore
              .collection('comments')
              .where('postId', isEqualTo: doc.id)
              .get();
          final commentCount = commentsSnapshot.docs.length;
          updates['commentCount'] = commentCount;
          Logger.log('   → commentCount 추가: $commentCount');
        }

        if (updates.isNotEmpty) {
          updates['updatedAt'] = FieldValue.serverTimestamp();
          batch.update(doc.reference, updates);
          count++;
          Logger.log('   ✅ 업데이트 예정');
        } else {
          Logger.log('   ⏭️ 업데이트 불필요');
        }
      }

      if (count > 0) {
        Logger.log('💾 배치 커밋 실행 중...');
        await batch.commit();
        Logger.log('✅ 마이그레이션 완료: ${count}개 모임 업데이트');
      } else {
        Logger.log('ℹ️ 마이그레이션 불필요: 모든 모임이 이미 업데이트됨');
      }
    } catch (e) {
      Logger.error('❌ 마이그레이션 실패: $e');
      Logger.error('스택 트레이스: ${StackTrace.current}');
      rethrow;
    }
  }

  // 실시간 참여자 목록 스트림
  Stream<List<MeetupParticipant>> getParticipantsStream(String meetupId) {
    Logger.log('👥 [PARTICIPANTS_STREAM] 참여자 스트림 시작: $meetupId');

    return _firestore
        .collection('meetup_participants')
        .where('meetupId', isEqualTo: meetupId)
        .where('status', isEqualTo: ParticipantStatus.approved)
        .snapshots()
        .asyncMap((snapshot) async {
      Logger.log(
          '🔄 [PARTICIPANTS_STREAM] 스냅샷 수신 - 문서 수: ${snapshot.docs.length}');
      Logger.log(
          '🔍 [PARTICIPANTS_STREAM] 메타데이터 - fromCache: ${snapshot.metadata.isFromCache}, hasPendingWrites: ${snapshot.metadata.hasPendingWrites}');

      var participants = snapshot.docs.map((doc) {
        final data = doc.data();
        data['id'] = doc.id;
        final participant = MeetupParticipant.fromJson(data);
        Logger.log('  - 참여자: ${participant.userName} (${participant.userId})');
        return participant;
      }).toList();

      participants = await _resolveLatestParticipantProfiles(participants);

      // 클라이언트 측에서 정렬
      participants.sort((a, b) => a.joinedAt.compareTo(b.joinedAt));

      Logger.log('✅ [PARTICIPANTS_STREAM] 참여자 목록 반환: ${participants.length}명');
      return participants;
    });
  }
}
