// lib/models/ad_banner.dart
// 광고 배너 데이터 모델 - Firebase Firestore 연동

import 'package:cloud_firestore/cloud_firestore.dart';

class AdBanner {
  final String id;
  final String title;
  final String description;
  final String url;
  final String? imageUrl; // Firebase Storage URL
  final bool isActive;
  final int order; // 표시 순서
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AdBanner({
    required this.id,
    required this.title,
    required this.description,
    required this.url,
    this.imageUrl,
    this.isActive = true,
    this.order = 0,
    this.createdAt,
    this.updatedAt,
  });

  // Firestore로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'url': url,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'order': order,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  // Firestore에서 생성
  factory AdBanner.fromJson(Map<String, dynamic> json) {
    return AdBanner(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      url: json['url'] as String,
      imageUrl: json['imageUrl'] as String?,
      isActive: json['isActive'] as bool? ?? true,
      order: json['order'] as int? ?? 0,
      createdAt: json['createdAt'] is Timestamp 
          ? (json['createdAt'] as Timestamp).toDate() 
          : null,
      updatedAt: json['updatedAt'] is Timestamp 
          ? (json['updatedAt'] as Timestamp).toDate() 
          : null,
    );
  }

  // Firestore DocumentSnapshot에서 생성
  factory AdBanner.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdBanner.fromJson({
      'id': doc.id,
      ...data,
    });
  }
}

