// lib/models/user_profile.dart
// 사용자 프로필 데이터 모델
// 친구요청 시스템에서 사용할 사용자 정보 구조

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/profile_photo_policy.dart';

class UserProfile {
  final String uid;
  final String? photoURL;
  final String? nickname;
  final String? nationality;
  final String? email;
  final String? university;
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

    return UserProfile(
      uid: doc.id,
      photoURL: data['photoURL'],
      nickname: data['nickname'],
      nationality: data['nationality'],
      email: data['email'],
      university: data['university'],
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
      (nickname != null && nickname!.trim().isNotEmpty) ? nickname!.trim() : '익명';

  // 프로필 이미지가 있는지 확인
  bool get hasProfileImage =>
      photoURL != null && ProfilePhotoPolicy.isAllowedProfilePhotoUrl(photoURL!);

  // 기본 프로필 이미지 URL (나중에 assets에서 가져올 수 있음)
  String get defaultProfileImage => 'assets/icons/default_profile.png';

  // 사용자 복사본 생성 (특정 필드만 수정)
  UserProfile copyWith({
    String? photoURL,
    String? nickname,
    String? nationality,
    String? email,
    String? university,
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
