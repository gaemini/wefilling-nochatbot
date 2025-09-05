// lib/models/user_profile.dart
// 사용자 프로필 데이터 모델
// 친구요청 시스템에서 사용할 사용자 정보 구조

import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String uid;
  final String displayName;
  final String? photoURL;
  final String? nickname;
  final String? nationality;
  final int friendsCount;
  final int incomingCount;  // 받은 친구요청 수
  final int outgoingCount;  // 보낸 친구요청 수
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.uid,
    required this.displayName,
    this.photoURL,
    this.nickname,
    this.nationality,
    this.friendsCount = 0,
    this.incomingCount = 0,
    this.outgoingCount = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  // Firestore 문서에서 UserProfile 객체 생성
  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return UserProfile(
      uid: doc.id,
      displayName: data['displayName'] ?? '',
      photoURL: data['photoURL'],
      nickname: data['nickname'],
      nationality: data['nationality'],
      friendsCount: data['friendsCount'] ?? 0,
      incomingCount: data['incomingCount'] ?? 0,
      outgoingCount: data['outgoingCount'] ?? 0,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  // UserProfile 객체를 Firestore 문서로 변환
  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'photoURL': photoURL,
      'nickname': nickname,
      'nationality': nationality,
      'friendsCount': friendsCount,
      'incomingCount': incomingCount,
      'outgoingCount': outgoingCount,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  // 사용자 표시 이름 (닉네임 우선, 없으면 displayName)
  String get displayNameOrNickname => nickname ?? displayName;

  // 프로필 이미지가 있는지 확인
  bool get hasProfileImage => photoURL != null && photoURL!.isNotEmpty;

  // 기본 프로필 이미지 URL (나중에 assets에서 가져올 수 있음)
  String get defaultProfileImage => 'assets/icons/default_profile.png';

  // 사용자 복사본 생성 (특정 필드만 수정)
  UserProfile copyWith({
    String? displayName,
    String? photoURL,
    String? nickname,
    String? nationality,
    int? friendsCount,
    int? incomingCount,
    int? outgoingCount,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      uid: uid,
      displayName: displayName ?? this.displayName,
      photoURL: photoURL ?? this.photoURL,
      nickname: nickname ?? this.nickname,
      nationality: nationality ?? this.nationality,
      friendsCount: friendsCount ?? this.friendsCount,
      incomingCount: incomingCount ?? this.incomingCount,
      outgoingCount: outgoingCount ?? this.outgoingCount,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'UserProfile(uid: $uid, displayName: $displayName, nickname: $nickname, friendsCount: $friendsCount)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserProfile && other.uid == uid;
  }

  @override
  int get hashCode => uid.hashCode;
}
