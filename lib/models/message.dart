import 'package:json_annotation/json_annotation.dart';

part 'message.g.dart';

/// 채팅 메시지 모델
@JsonSerializable()
class Message {
  /// 메시지 고유 ID
  final String id;
  
  /// 메시지 내용
  final String content;
  
  /// 사용자 메시지 여부
  final bool isFromUser;
  
  /// 메시지 생성 시간
  final DateTime timestamp;
  
  /// 메시지 언어 (다국어 지원용)
  final String? language;
  
  /// 출처 정보 (RAG에서 참조한 문서 정보)
  final List<String>? sources;
  
  /// 신뢰도 점수 (AI 응답의 확신도)
  final double? confidenceScore;

  const Message({
    required this.id,
    required this.content,
    required this.isFromUser,
    required this.timestamp,
    this.language,
    this.sources,
    this.confidenceScore,
  });

  /// JSON에서 Message 객체 생성
  factory Message.fromJson(Map<String, dynamic> json) => _$MessageFromJson(json);

  /// Message 객체를 JSON으로 변환
  Map<String, dynamic> toJson() => _$MessageToJson(this);

  /// 사용자 메시지 생성 헬퍼
  factory Message.user({
    required String content,
    String? language,
  }) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isFromUser: true,
      timestamp: DateTime.now(),
      language: language,
    );
  }

  /// 봇 메시지 생성 헬퍼
  factory Message.bot({
    required String content,
    String? language,
    List<String>? sources,
    double? confidenceScore,
  }) {
    return Message(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: content,
      isFromUser: false,
      timestamp: DateTime.now(),
      language: language,
      sources: sources,
      confidenceScore: confidenceScore,
    );
  }

  /// 메시지 복사 (수정된 필드와 함께)
  Message copyWith({
    String? id,
    String? content,
    bool? isFromUser,
    DateTime? timestamp,
    String? language,
    List<String>? sources,
    double? confidenceScore,
  }) {
    return Message(
      id: id ?? this.id,
      content: content ?? this.content,
      isFromUser: isFromUser ?? this.isFromUser,
      timestamp: timestamp ?? this.timestamp,
      language: language ?? this.language,
      sources: sources ?? this.sources,
      confidenceScore: confidenceScore ?? this.confidenceScore,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Message && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'Message(id: $id, content: $content, isFromUser: $isFromUser, timestamp: $timestamp)';
  }
}
