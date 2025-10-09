// lib/models/meetup.dart
// 모임 데이터 모델 정의
// 모임 관련 속성 포함(제목,설명,작성자,작성일,좋아요 수 등)
// 모임 정보 포맷팅을 위한 유틸리티 메서드 제공

import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

class Meetup {
  final String id;
  final String title;
  final String description;
  final String location;
  final String time;
  final int maxParticipants;
  final int currentParticipants;
  final String host;
  final String hostNationality;
  final String hostPhotoURL; // 주최자 프로필 사진 URL
  final String imageUrl;
  final String thumbnailContent;
  final String thumbnailImageUrl;
  final DateTime date;
  final String category;
  final String? userId; // 모임 주최자 ID
  final String? hostNickname; // 주최자 닉네임
  final String visibility; // 공개 범위: 'public', 'friends', 'category'
  final List<String> visibleToCategoryIds; // 특정 카테고리에만 공개할 경우 카테고리 ID들

  const Meetup({
    required this.id,
    required this.title,
    required this.description,
    required this.location,
    required this.time,
    required this.maxParticipants,
    required this.currentParticipants,
    required this.host,
    this.hostNationality = '',
    this.hostPhotoURL = '', // 프로필 사진 URL (기본값은 빈 문자열)
    required this.imageUrl,
    this.thumbnailContent = '',
    this.thumbnailImageUrl = '',
    required this.date,
    this.category = '기타',
    this.userId,
    this.hostNickname,
    this.visibility = 'public', // 기본값: 전체 공개
    this.visibleToCategoryIds = const [],
  });

  Meetup copyWith({
    String? id,
    String? title,
    String? description,
    String? location,
    String? time,
    int? maxParticipants,
    int? currentParticipants,
    String? host,
    String? hostNationality,
    String? hostPhotoURL,
    String? imageUrl,
    String? thumbnailContent,
    String? thumbnailImageUrl,
    DateTime? date,
    String? category,
    String? userId,
    String? hostNickname,
    String? visibility,
    List<String>? visibleToCategoryIds,
  }) {
    return Meetup(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      time: time ?? this.time,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      currentParticipants: currentParticipants ?? this.currentParticipants,
      host: host ?? this.host,
      hostNationality: hostNationality ?? this.hostNationality,
      hostPhotoURL: hostPhotoURL ?? this.hostPhotoURL,
      imageUrl: imageUrl ?? this.imageUrl,
      thumbnailContent: thumbnailContent ?? this.thumbnailContent,
      thumbnailImageUrl: thumbnailImageUrl ?? this.thumbnailImageUrl,
      date: date ?? this.date,
      category: category ?? this.category,
      userId: userId ?? this.userId,
      hostNickname: hostNickname ?? this.hostNickname,
      visibility: visibility ?? this.visibility,
      visibleToCategoryIds: visibleToCategoryIds ?? this.visibleToCategoryIds,
    );
  }

  // 날짜 포맷 문자열 반환 함수
  String getFormattedDate() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final meetupDate = DateTime(date.year, date.month, date.day);

    final difference = meetupDate.difference(today).inDays;

    if (difference == 0) {
      return '오늘 예정';
    } else if (difference == 1) {
      return '내일 예정';
    } else if (difference > 1 && difference < 7) {
      return '$difference일 후 예정';
    } else {
      return '${date.month}월 ${date.day}일 예정';
    }
  }

  // 포맷된 요일 문자열 반환
  String getFormattedDayOfWeek() {
    final dayNames = ['월', '화', '수', '목', '금', '토', '일'];
    // DateTime의 weekday는 1(월요일)부터 7(일요일)까지, 배열 인덱스는 0부터 시작하므로 -1
    final dayIndex = (date.weekday - 1) % 7;
    
    // 안전한 인덱스 접근
    if (dayIndex < 0 || dayIndex >= dayNames.length) {
      return '알 수 없음';
    }
    
    return dayNames[dayIndex];
  }

  // 간단한 날짜 문자열 (MM.dd)
  String getShortDate() {
    return DateFormat('MM.dd').format(date);
  }

  // 모임 상태 확인 (예정/진행중/종료)
  String getStatus() {
    final now = DateTime.now();

    // 시간이 "미정"이거나 잘못된 형식인 경우 처리
    if (time.isEmpty || time == '미정' || !time.contains(':')) {
      // 날짜만으로 판단 (시간 정보 없음)
      final meetupDate = DateTime(date.year, date.month, date.day, 23, 59);
      return now.isAfter(meetupDate) ? '종료' : '예정';
    }

    // 날짜와 시간 문자열을 결합하여 DateTime 객체 생성
    final meetupTimeStr = time.split('~')[0].trim(); // "14:00 ~ 16:00" => "14:00"
    
    // 안전한 시간 파싱
    final timeParts = meetupTimeStr.split(':');
    if (timeParts.length < 2) {
      // 시간 형식이 잘못된 경우 날짜만으로 판단
      final meetupDate = DateTime(date.year, date.month, date.day, 23, 59);
      return now.isAfter(meetupDate) ? '종료' : '예정';
    }
    
    final hour = int.tryParse(timeParts[0]) ?? 0;
    final minute = int.tryParse(timeParts[1]) ?? 0;

    final meetupDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      minute,
    );

    // 종료 시간 추정 (시작으로부터 2시간 후로 가정)
    int endHour = hour + 2;
    int endMinute = minute;
    
    if (time.contains('~')) {
      final endTimeStr = time.split('~')[1].trim();
      final endTimeParts = endTimeStr.split(':');
      
      if (endTimeParts.length >= 2) {
        endHour = int.tryParse(endTimeParts[0]) ?? (hour + 2);
        endMinute = int.tryParse(endTimeParts[1]) ?? minute;
      }
    }

    final meetupEndDateTime = DateTime(
      date.year,
      date.month,
      date.day,
      endHour,
      endMinute,
    );

    if (now.isBefore(meetupDateTime)) {
      return '예정';
    } else if (now.isAfter(meetupEndDateTime)) {
      return '종료';
    } else {
      return '진행중';
    }
  }

  // 모임이 가득 찼는지 확인
  bool isFull() {
    return currentParticipants >= maxParticipants;
  }

  // 기본 이미지 URL 가져오기 (이미지가 없을 때 카테고리별 기본 이미지 반환)
  String getDefaultImageUrl() {
    // 더 이상 asset 이미지를 사용하지 않고, 아이콘 기반 이미지를 사용
    return '';
  }

  // 카테고리별 아이콘 가져오기
  IconData getCategoryIcon() {
    switch (category) {
      case '스터디':
        return Icons.school_outlined;
      case '식사':
        return Icons.restaurant_outlined;
      case '취미':
        return Icons.palette_outlined;
      case '문화':
        return Icons.theater_comedy_outlined;
      default:
        return Icons.groups_outlined;
    }
  }

  // 카테고리별 색상 가져오기
  Color getCategoryColor() {
    switch (category) {
      case '스터디':
        return const Color(0xFF4A90E2); // 파란색
      case '식사':
        return const Color(0xFFFF9500); // 주황색
      case '취미':
        return const Color(0xFF34C759); // 초록색
      case '문화':
        return const Color(0xFFAF52DE); // 보라색
      default:
        return const Color(0xFF8E8E93); // 회색
    }
  }

  // 카테고리별 배경 색상 가져오기
  Color getCategoryBackgroundColor() {
    switch (category) {
      case '스터디':
        return const Color(0xFFF0F7FF); // 연한 파란색
      case '식사':
        return const Color(0xFFFFF8F0); // 연한 주황색
      case '취미':
        return const Color(0xFFF0FFF4); // 연한 초록색
      case '문화':
        return const Color(0xFFF8F0FF); // 연한 보라색
      default:
        return const Color(0xFFF8F8F8); // 연한 회색
    }
  }

  // 표시할 이미지 URL 가져오기 (실제 이미지가 있으면 그것을, 없으면 기본 이미지 반환)
  String getDisplayImageUrl() {
    // 우선순위: imageUrl > thumbnailImageUrl > 기본 이미지
    if (imageUrl.isNotEmpty) {
      return imageUrl;
    } else if (thumbnailImageUrl.isNotEmpty) {
      return thumbnailImageUrl;
    } else {
      return getDefaultImageUrl();
    }
  }

  // 이미지가 기본 이미지인지 확인
  bool isDefaultImage() {
    return imageUrl.isEmpty && thumbnailImageUrl.isEmpty;
  }

  // Firebase에서 데이터를 가져올 때 사용
  factory Meetup.fromJson(Map<String, dynamic> json) {
    return Meetup(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      location: json['location'] ?? '',
      time: json['time'] ?? '',
      maxParticipants: json['maxParticipants'] ?? 0,
      currentParticipants: json['currentParticipants'] ?? 0,
      host: json['host'] ?? json['hostNickname'] ?? '',
      hostNationality: json['hostNationality'] ?? '',
      hostPhotoURL: json['hostPhotoURL'] ?? '',
      imageUrl: json['imageUrl'] ?? '',
      thumbnailContent: json['thumbnailContent'] ?? '',
      thumbnailImageUrl: json['thumbnailImageUrl'] ?? '',
      date: json['date']?.toDate() ?? DateTime.now(),
      category: json['category'] ?? '기타',
      userId: json['userId'],
      hostNickname: json['hostNickname'],
      visibility: json['visibility'] ?? 'public',
      visibleToCategoryIds: json['visibleToCategoryIds'] != null
          ? List<String>.from(json['visibleToCategoryIds'] as List)
          : [],
    );
  }

  // Firebase에 데이터를 저장할 때 사용
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'location': location,
      'time': time,
      'maxParticipants': maxParticipants,
      'currentParticipants': currentParticipants,
      'host': host,
      'hostNationality': hostNationality,
      'hostPhotoURL': hostPhotoURL,
      'imageUrl': imageUrl,
      'thumbnailContent': thumbnailContent,
      'thumbnailImageUrl': thumbnailImageUrl,
      'date': date,
      'category': category,
      'userId': userId,
      'hostNickname': hostNickname,
      'visibility': visibility,
      'visibleToCategoryIds': visibleToCategoryIds,
    };
  }
}
