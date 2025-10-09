// lib/models/friend_category.dart
// 친구 카테고리 모델 정의

import 'package:cloud_firestore/cloud_firestore.dart';

class FriendCategory {
  final String id;
  final String name;
  final String description;
  final String color; // 카테고리 색상 (hex)
  final String iconName; // 아이콘 이름
  final DateTime createdAt;
  final DateTime updatedAt;
  final String userId; // 생성한 사용자 ID
  final List<String> friendIds; // 이 카테고리에 속한 친구들의 ID

  const FriendCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.color,
    required this.iconName,
    required this.createdAt,
    required this.updatedAt,
    required this.userId,
    required this.friendIds,
  });

  // Firestore 데이터로부터 객체 생성
  factory FriendCategory.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FriendCategory(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      color: data['color'] ?? '#4A90E2',
      iconName: data['iconName'] ?? 'group',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      userId: data['userId'] ?? '',
      friendIds: List<String>.from(data['friendIds'] ?? []),
    );
  }

  // Firestore에 저장할 데이터로 변환
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'color': color,
      'iconName': iconName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'userId': userId,
      'friendIds': friendIds,
    };
  }

  // 복사본 생성 (수정용)
  FriendCategory copyWith({
    String? id,
    String? name,
    String? description,
    String? color,
    String? iconName,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? userId,
    List<String>? friendIds,
  }) {
    return FriendCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      color: color ?? this.color,
      iconName: iconName ?? this.iconName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      userId: userId ?? this.userId,
      friendIds: friendIds ?? this.friendIds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FriendCategory && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

// 기본 카테고리 정의
class DefaultFriendCategories {
  static const List<Map<String, dynamic>> defaults = [
    {
      'name': '대학 친구',
      'description': '',
      'color': '#4A90E2',
      'iconName': 'school',
    },
    {
      'name': '동아리',
      'description': '',
      'color': '#6BC9A5',
      'iconName': 'groups',
    },
    {
      'name': '취미 친구',
      'description': '',
      'color': '#FF8C42',
      'iconName': 'palette',
    },
    {
      'name': '스터디 그룹',
      'description': '',
      'color': '#9B59B6',
      'iconName': 'book',
    },
  ];
}







