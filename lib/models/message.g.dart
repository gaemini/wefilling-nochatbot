// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'message.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Message _$MessageFromJson(Map<String, dynamic> json) => Message(
  id: json['id'] as String,
  content: json['content'] as String,
  isFromUser: json['isFromUser'] as bool,
  timestamp: DateTime.parse(json['timestamp'] as String),
  language: json['language'] as String?,
  sources:
      (json['sources'] as List<dynamic>?)?.map((e) => e as String).toList(),
  confidenceScore: (json['confidenceScore'] as num?)?.toDouble(),
);

Map<String, dynamic> _$MessageToJson(Message instance) => <String, dynamic>{
  'id': instance.id,
  'content': instance.content,
  'isFromUser': instance.isFromUser,
  'timestamp': instance.timestamp.toIso8601String(),
  'language': instance.language,
  'sources': instance.sources,
  'confidenceScore': instance.confidenceScore,
};
