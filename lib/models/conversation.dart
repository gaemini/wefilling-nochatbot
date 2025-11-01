// lib/models/conversation.dart
// DM 대화방 데이터 모델
// Firestore conversations 컬렉션에 대응

import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  final String id;
  final List<String> participants;
  final Map<String, String> participantNames;
  final Map<String, String> participantPhotos;
  final Map<String, bool> isAnonymous;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String lastMessageSenderId;
  final Map<String, int> unreadCount;
  final String? postId;
  // 익명 게시글로부터 시작된 DM의 경우 채팅방 표시용 제목(게시글 제목)
  final String? dmTitle;
  final DateTime createdAt;
  final DateTime updatedAt;

  Conversation({
    required this.id,
    required this.participants,
    required this.participantNames,
    required this.participantPhotos,
    required this.isAnonymous,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.lastMessageSenderId,
    required this.unreadCount,
    this.postId,
    this.dmTitle,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Firestore 문서에서 Conversation 객체 생성
  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return Conversation(
      id: doc.id,
      participants: List<String>.from(data['participants'] ?? []),
      participantNames: Map<String, String>.from(data['participantNames'] ?? {}),
      participantPhotos: Map<String, String>.from(data['participantPhotos'] ?? {}),
      isAnonymous: Map<String, bool>.from(data['isAnonymous'] ?? {}),
      lastMessage: data['lastMessage'] ?? '',
      lastMessageTime: (data['lastMessageTime'] as Timestamp).toDate(),
      lastMessageSenderId: data['lastMessageSenderId'] ?? '',
      unreadCount: Map<String, int>.from(data['unreadCount'] ?? {}),
      postId: data['postId'],
      dmTitle: data['dmTitle'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
    );
  }

  /// Conversation 객체를 Firestore 문서로 변환
  Map<String, dynamic> toFirestore() {
    return {
      'participants': participants,
      'participantNames': participantNames,
      'participantPhotos': participantPhotos,
      'isAnonymous': isAnonymous,
      'lastMessage': lastMessage,
      'lastMessageTime': Timestamp.fromDate(lastMessageTime),
      'lastMessageSenderId': lastMessageSenderId,
      'unreadCount': unreadCount,
      if (postId != null) 'postId': postId,
      if (dmTitle != null && dmTitle!.isNotEmpty) 'dmTitle': dmTitle,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  /// 상대방 사용자 ID 가져오기
  String getOtherUserId(String currentUserId) {
    return participants.firstWhere(
      (id) => id != currentUserId,
      orElse: () => participants[0],
    );
  }

  /// 상대방 이름 가져오기 (익명 처리 포함)
  String getOtherUserName(String currentUserId) {
    final otherUserId = getOtherUserId(currentUserId);
    
    // 상대방이 익명인 경우
    if (isAnonymous[otherUserId] == true) {
      return '익명'; // 익명 표시 (UI에서 로컬라이제이션 처리)
    }
    
    return participantNames[otherUserId] ?? 'Unknown';
  }

  /// 상대방 프로필 사진 URL 가져오기
  String getOtherUserPhoto(String currentUserId) {
    final otherUserId = getOtherUserId(currentUserId);
    
    // 상대방이 익명인 경우 빈 문자열 반환
    if (isAnonymous[otherUserId] == true) {
      return '';
    }
    
    return participantPhotos[otherUserId] ?? '';
  }

  /// 상대방이 익명인지 확인
  bool isOtherUserAnonymous(String currentUserId) {
    final otherUserId = getOtherUserId(currentUserId);
    return isAnonymous[otherUserId] ?? false;
  }

  /// 내 읽지 않은 메시지 수 가져오기
  int getMyUnreadCount(String currentUserId) {
    return unreadCount[currentUserId] ?? 0;
  }

  /// 상대방 읽지 않은 메시지 수 가져오기
  int getOtherUnreadCount(String currentUserId) {
    final otherUserId = getOtherUserId(currentUserId);
    return unreadCount[otherUserId] ?? 0;
  }

  /// 마지막 메시지가 내가 보낸 것인지 확인
  bool isLastMessageMine(String currentUserId) {
    return lastMessageSenderId == currentUserId;
  }

  @override
  String toString() {
    return 'Conversation(id: $id, participants: $participants, lastMessage: $lastMessage)';
  }
}

