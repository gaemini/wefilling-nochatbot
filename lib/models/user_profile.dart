// lib/models/user_profile.dart
// 사용자 프로필 데이터 모델
// 친구요청 시스템에서 사용할 사용자 정보 구조

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/hanyang_verification_helper.dart';
import '../utils/profile_photo_policy.dart';
import 'student_type.dart';

class UserProfile {
  final String uid;
  final String? photoURL;
  final String? nickname;
  final String? nationality;
  final String? email;
  final String? university;
  final String? bio;
  final List<String> interests;
  final List<String> preferredActivities;
  final String? conversationStarter;
  final String? friendshipPrompt;
  final String? department;
  final String? grade;
  final bool showDepartment;
  final bool showGrade;
  final bool isSchoolVerified;
  final StudentType? studentType;
  final bool todoOnboardingCompleted;
  final String? languageCode;
  final int profileCompletion;
  final int friendsCount;
  final int incomingCount; // 받은 친구요청 수
  final int outgoingCount; // 보낸 친구요청 수
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.uid,
    this.photoURL,
    this.nickname,
    this.nationality,
    this.email,
    this.university,
    this.bio,
    this.interests = const <String>[],
    this.preferredActivities = const <String>[],
    this.conversationStarter,
    this.friendshipPrompt,
    this.department,
    this.grade,
    this.showDepartment = false,
    this.showGrade = false,
    this.isSchoolVerified = false,
    this.studentType,
    this.todoOnboardingCompleted = false,
    this.languageCode,
    this.profileCompletion = 0,
    this.friendsCount = 0,
    this.incomingCount = 0,
    this.outgoingCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  // Firestore 문서에서 UserProfile 객체 생성
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final now = DateTime.now();

    List<String> strings(String key) {
      final value = data[key];
      return value is List
          ? value
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .take(5)
              .toList(growable: false)
          : const <String>[];
    }

    String? nullableString(String key) {
      final value = data[key];
      if (value == null) return null;
      final text = value.toString().trim();
      return text.isEmpty ? null : text;
    }

    return UserProfile(
      uid: doc.id,
      photoURL: data['photoURL'],
      nickname: data['nickname'],
      nationality: data['nationality'],
      email: data['email'],
      university: data['university'],
      bio: nullableString('bio'),
      interests: strings('interests'),
      preferredActivities: strings('preferredActivities'),
      conversationStarter: nullableString('conversationStarter'),
      friendshipPrompt: nullableString('friendshipPrompt'),
      department: nullableString('department'),
      grade: nullableString('grade'),
      showDepartment: data['showDepartment'] == true,
      showGrade: data['showGrade'] == true,
      isSchoolVerified: isHanyangEmailVerified(data),
      studentType: StudentType.tryParse(data['studentType']),
      todoOnboardingCompleted: data['todoOnboardingCompleted'] == true,
      languageCode: nullableString('languageCode'),
      profileCompletion: data['profileCompletion'] is num
          ? (data['profileCompletion'] as num).clamp(0, 100).round()
          : 0,
      friendsCount: data['friendsCount'] ?? 0,
      incomingCount: data['incomingCount'] ?? 0,
      outgoingCount: data['outgoingCount'] ?? 0,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : now,
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : now,
    );
  }

  // UserProfile 객체를 Firestore 문서로 변환
  Map<String, dynamic> toFirestore() {
    return {
      'photoURL': photoURL,
      'nickname': nickname,
      'nationality': nationality,
      'email': email,
      'university': university,
      'bio': bio ?? '',
      'interests': interests,
      'preferredActivities': preferredActivities,
      'conversationStarter': conversationStarter ?? '',
      'friendshipPrompt': friendshipPrompt ?? '',
      'department': department ?? '',
      'grade': grade ?? '',
      'showDepartment': showDepartment,
      'showGrade': showGrade,
      if (studentType != null) 'studentType': studentType!.value,
      'todoOnboardingCompleted': todoOnboardingCompleted,
      if (languageCode != null) 'languageCode': languageCode,
      'profileCompletion': profileCompletion,
      'friendsCount': friendsCount,
      'incomingCount': incomingCount,
      'outgoingCount': outgoingCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // 사용자 표시 이름 (nickname 단일 소스)
  // - nickname이 비어있으면 "익명"으로 표시
  String get displayNameOrNickname =>
      (nickname != null && nickname!.trim().isNotEmpty)
          ? nickname!.trim()
          : '익명';

  // 프로필 이미지가 있는지 확인
  bool get hasProfileImage =>
      photoURL != null &&
      ProfilePhotoPolicy.isAllowedProfilePhotoUrl(photoURL!);

  // 기본 프로필 이미지 URL (나중에 assets에서 가져올 수 있음)
  String get defaultProfileImage => 'assets/icons/default_profile.png';

  // 사용자 복사본 생성 (특정 필드만 수정)
  UserProfile copyWith({
    String? photoURL,
    String? nickname,
    String? nationality,
    String? email,
    String? university,
    String? bio,
    List<String>? interests,
    List<String>? preferredActivities,
    String? conversationStarter,
    String? friendshipPrompt,
    String? department,
    String? grade,
    bool? showDepartment,
    bool? showGrade,
    bool? isSchoolVerified,
    StudentType? studentType,
    bool? todoOnboardingCompleted,
    String? languageCode,
    int? profileCompletion,
    int? friendsCount,
    int? incomingCount,
    int? outgoingCount,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      photoURL: photoURL ?? this.photoURL,
      nickname: nickname ?? this.nickname,
      nationality: nationality ?? this.nationality,
      email: email ?? this.email,
      university: university ?? this.university,
      bio: bio ?? this.bio,
      interests: interests ?? this.interests,
      preferredActivities: preferredActivities ?? this.preferredActivities,
      conversationStarter: conversationStarter ?? this.conversationStarter,
      friendshipPrompt: friendshipPrompt ?? this.friendshipPrompt,
      department: department ?? this.department,
      grade: grade ?? this.grade,
      showDepartment: showDepartment ?? this.showDepartment,
      showGrade: showGrade ?? this.showGrade,
      isSchoolVerified: isSchoolVerified ?? this.isSchoolVerified,
      studentType: studentType ?? this.studentType,
      todoOnboardingCompleted:
          todoOnboardingCompleted ?? this.todoOnboardingCompleted,
      languageCode: languageCode ?? this.languageCode,
      profileCompletion: profileCompletion ?? this.profileCompletion,
      friendsCount: friendsCount ?? this.friendsCount,
      incomingCount: incomingCount ?? this.incomingCount,
      outgoingCount: outgoingCount ?? this.outgoingCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'UserProfile(uid: $uid, nickname: $nickname, friendsCount: $friendsCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserProfile && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
