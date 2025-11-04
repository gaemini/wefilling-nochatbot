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
  final List<String> archivedBy; // 이 대화방을 보관(삭제)한 사용자 uid 목록
  final Map<String, DateTime?> userLeftAt; // 각 사용자가 언제 나갔는지 기록
  final Map<String, DateTime?> rejoinedAt; // 각 사용자가 언제 다시 들어왔는지 기록

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
    this.archivedBy = const [],
    this.userLeftAt = const {},
    this.rejoinedAt = const {},
  });

  /// Firestore 문서에서 Conversation 객체 생성
  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    // userLeftAt 필드 파싱
    final userLeftAtData = data['userLeftAt'] as Map<String, dynamic>? ?? {};
    final userLeftAt = <String, DateTime?>{};
    for (final entry in userLeftAtData.entries) {
      userLeftAt[entry.key] = entry.value != null 
          ? (entry.value as Timestamp).toDate() 
          : null;
    }

    // rejoinedAt 필드 파싱
    final rejoinedAtData = data['rejoinedAt'] as Map<String, dynamic>? ?? {};
    final rejoinedAt = <String, DateTime?>{};
    for (final entry in rejoinedAtData.entries) {
      rejoinedAt[entry.key] = entry.value != null 
          ? (entry.value as Timestamp).toDate() 
          : null;
    }

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
      archivedBy: (data['archivedBy'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      userLeftAt: userLeftAt,
      rejoinedAt: rejoinedAt,
    );
  }

  /// Conversation 객체를 Firestore 문서로 변환
  Map<String, dynamic> toFirestore() {
    // userLeftAt 필드 변환
    final userLeftAtFirestore = <String, dynamic>{};
    for (final entry in userLeftAt.entries) {
      userLeftAtFirestore[entry.key] = entry.value != null 
          ? Timestamp.fromDate(entry.value!) 
          : null;
    }

    // rejoinedAt 필드 변환
    final rejoinedAtFirestore = <String, dynamic>{};
    for (final entry in rejoinedAt.entries) {
      rejoinedAtFirestore[entry.key] = entry.value != null 
          ? Timestamp.fromDate(entry.value!) 
          : null;
    }

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
      if (archivedBy.isNotEmpty) 'archivedBy': archivedBy,
      if (userLeftAt.isNotEmpty) 'userLeftAt': userLeftAtFirestore,
      if (rejoinedAt.isNotEmpty) 'rejoinedAt': rejoinedAtFirestore,
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

  /// 사용자가 나간 적이 있는지 확인
  bool hasUserLeft(String userId) {
    return userLeftAt[userId] != null;
  }

  /// 사용자가 다시 들어온 적이 있는지 확인
  bool hasUserRejoined(String userId) {
    return rejoinedAt[userId] != null;
  }

  /// 사용자가 현재 나간 상태인지 확인 (나갔지만 아직 다시 들어오지 않음)
  bool isUserCurrentlyLeft(String userId) {
    final leftTime = userLeftAt[userId];
    final rejoinTime = rejoinedAt[userId];
    
    if (leftTime == null) return false; // 나간 적이 없음
    if (rejoinTime == null) return true; // 나갔지만 다시 들어온 적 없음
    
    return leftTime.isAfter(rejoinTime); // 마지막 나간 시간이 마지막 들어온 시간보다 늦음
  }

  /// 사용자의 메시지 가시성 시작 시간 계산
  DateTime? getMessageVisibilityStartTime(String userId) {
    if (!hasUserLeft(userId)) {
      return null; // 나간 적이 없으면 모든 메시지 표시
    }
    
    final rejoinTime = rejoinedAt[userId];
    if (rejoinTime != null) {
      return rejoinTime; // 다시 들어온 시점부터 표시
    }
    
    return DateTime.now(); // 아직 다시 들어오지 않았으면 현재 시점부터 (실제로는 메시지 없음)
  }

  @override
  String toString() {
    return 'Conversation(id: $id, participants: $participants, lastMessage: $lastMessage)';
  }
}

