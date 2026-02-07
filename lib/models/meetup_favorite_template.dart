import 'dart:convert';

class MeetupFavoriteTemplate {
  final String id;
  final String name; // 템플릿 표시명 (사용자용)
  final String title;
  final String description;
  final String location;
  final String categoryKey; // study/meal/cafe/drink/culture
  final bool isUndecidedTime;
  final String? time; // HH:mm (isUndecidedTime=false일 때)
  final int maxParticipants;
  final String? thumbnailImagePath; // 로컬 썸네일 이미지 경로
  final String? thumbnailImageUrl; // 원격 썸네일 URL(추천 장소 등)
  final DateTime updatedAt;

  const MeetupFavoriteTemplate({
    required this.id,
    required this.name,
    required this.title,
    required this.description,
    required this.location,
    required this.categoryKey,
    required this.isUndecidedTime,
    required this.time,
    required this.maxParticipants,
    required this.thumbnailImagePath,
    required this.thumbnailImageUrl,
    required this.updatedAt,
  });

  MeetupFavoriteTemplate copyWith({
    String? id,
    String? name,
    String? title,
    String? description,
    String? location,
    String? categoryKey,
    bool? isUndecidedTime,
    String? time,
    int? maxParticipants,
    String? thumbnailImagePath,
    String? thumbnailImageUrl,
    DateTime? updatedAt,
  }) {
    return MeetupFavoriteTemplate(
      id: id ?? this.id,
      name: name ?? this.name,
      title: title ?? this.title,
      description: description ?? this.description,
      location: location ?? this.location,
      categoryKey: categoryKey ?? this.categoryKey,
      isUndecidedTime: isUndecidedTime ?? this.isUndecidedTime,
      time: time ?? this.time,
      maxParticipants: maxParticipants ?? this.maxParticipants,
      thumbnailImagePath: thumbnailImagePath ?? this.thumbnailImagePath,
      thumbnailImageUrl: thumbnailImageUrl ?? this.thumbnailImageUrl,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'title': title,
      'description': description,
      'location': location,
      'categoryKey': categoryKey,
      'isUndecidedTime': isUndecidedTime,
      'time': time,
      'maxParticipants': maxParticipants,
      'thumbnailImagePath': thumbnailImagePath,
      'thumbnailImageUrl': thumbnailImageUrl,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static MeetupFavoriteTemplate fromJson(Map<String, dynamic> json) {
    return MeetupFavoriteTemplate(
      id: (json['id'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      title: (json['title'] ?? '') as String,
      description: (json['description'] ?? '') as String,
      location: (json['location'] ?? '') as String,
      categoryKey: (json['categoryKey'] ?? '') as String,
      isUndecidedTime: (json['isUndecidedTime'] ?? true) as bool,
      time: json['time'] as String?,
      maxParticipants: (json['maxParticipants'] ?? 3) as int,
      thumbnailImagePath: (json['thumbnailImagePath'] as String?)?.trim().isEmpty == true
          ? null
          : (json['thumbnailImagePath'] as String?),
      thumbnailImageUrl: (json['thumbnailImageUrl'] as String?)?.trim().isEmpty == true
          ? null
          : (json['thumbnailImageUrl'] as String?),
      updatedAt: DateTime.tryParse((json['updatedAt'] ?? '') as String) ??
          DateTime.now(),
    );
  }

  static List<MeetupFavoriteTemplate> listFromEncoded(String encoded) {
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! List) return [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(MeetupFavoriteTemplate.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String listToEncoded(List<MeetupFavoriteTemplate> list) {
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }
}

