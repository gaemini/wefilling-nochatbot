// lib/models/post.dart
// 게시글 데이터 모델 정의
// 게시글 관련 속성 및 메서드 포함(제목,내용,작성자,작성일,좋아요 수 등)
// 데이터 포맷팅 메서드 제공(날짜, 미리보기 등)
// 번역 기능 추가

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/settings_provider.dart';
import '../l10n/app_localizations.dart';

class Post {
  final String id;
  final String title;
  final String content;
  final String author;
  final String authorNationality; // 작성자 국적
  final String authorPhotoURL; // 작성자 프로필 사진 URL
  final String category; // 카테고리
  final DateTime createdAt;
  final String userId;
  final int commentCount;
  final int likes; // 좋아요 수
  final List<String> likedBy; // 좋아요 누른 사용자 ID 목록
  final List<String> imageUrls; // 이미지 URL 목록
  
  // 공개 범위 관련 필드
  final String visibility; // 'public' 또는 'category'
  final bool isAnonymous; // 익명 여부
  final List<String> visibleToCategoryIds; // 공개할 카테고리 ID 목록
  final List<String> allowedUserIds; // 이 게시글을 볼 수 있는 사용자 ID 목록 (비공개용)

  // 캐시된 번역 결과
  String? _translatedTitle;
  String? _translatedContent;

  Post({
    required this.id,
    required this.title,
    required this.content,
    required this.author,
    this.authorNationality = '', // 국적 정보 (기본값은 빈 문자열)
    this.authorPhotoURL = '', // 프로필 사진 URL (기본값은 빈 문자열)
    this.category = '일반', // 카테고리 (기본값은 '일반')
    required this.createdAt,
    required this.userId,
    this.commentCount = 0,
    this.likes = 0,
    this.likedBy = const [],
    this.imageUrls = const [], // URL 변환 제거 - 원본 URL 그대로 사용
    this.visibility = 'public', // 공개 범위 (기본값: 전체 공개)
    this.isAnonymous = false, // 익명 여부 (기본값: 실명)
    this.visibleToCategoryIds = const [], // 공개할 카테고리 목록 (기본값: 빈 리스트)
    this.allowedUserIds = const [], // 허용된 사용자 ID 목록 (기본값: 빈 리스트)
  });

  // 모델 디버깅을 위한 문자열 표현
  @override
  String toString() {
    return 'Post(id: $id, title: $title, author: $author, '
        'authorNationality: $authorNationality, userId: $userId, likes: $likes)';
  }

  // 게시글 생성 시간을 표시 형식으로 변환
  String getFormattedTime(BuildContext context) {
    final now = DateTime.now();
    final difference = now.difference(createdAt);
    final locale = Localizations.localeOf(context).languageCode;

    if (difference.inDays > 7) {
      // 일주일 이상 지난 경우 날짜 표시
      return DateFormat('yyyy.MM.dd').format(createdAt);
    } else if (difference.inDays > 0) {
      // 복수형 처리를 위해 지역화 함수 호출 (숫자를 인자로 전달)
        return AppLocalizations.of(context)!.daysAgo(difference.inDays);
      } else if (difference.inHours > 0) {
        return AppLocalizations.of(context)!.hoursAgo(difference.inHours);
      } else if (difference.inMinutes > 0) {
        return AppLocalizations.of(context)!.minutesAgo(difference.inMinutes);
    } else {
      return AppLocalizations.of(context)!.justNow;
    }
  }

  // 미리보기용 내용 (최대 100자)
  String getPreviewContent() {
    if (content.length <= 100) {
      return content;
    }
    return '${content.substring(0, 100)}...';
  }

  // 현재 사용자가 이 게시글에 좋아요를 눌렀는지 확인
  bool isLikedByUser(String userId) {
    return likedBy.contains(userId);
  }

  // 제목 번역 메서드
  Future<String> getTranslatedTitle(SettingsProvider settings) async {
    if (!settings.autoTranslate) return title;
    if (_translatedTitle != null) return _translatedTitle!;

    _translatedTitle = await settings.translateText(title);
    return _translatedTitle!;
  }

  // 본문 번역 메서드
  Future<String> getTranslatedContent(SettingsProvider settings) async {
    if (!settings.autoTranslate) return content;
    if (_translatedContent != null) return _translatedContent!;

    _translatedContent = await settings.translateText(content);
    return _translatedContent!;
  }

  // 번역된 미리보기 내용
  Future<String> getTranslatedPreviewContent(SettingsProvider settings) async {
    final translatedContent = await getTranslatedContent(settings);
    if (translatedContent.length <= 100) {
      return translatedContent;
    }
    return '${translatedContent.substring(0, 100)}...';
  }

  // Post 객체 복제 메서드 (필요시 데이터 업데이트에 사용)
  Post copyWith({
    String? id,
    String? title,
    String? content,
    String? author,
    String? authorNationality,
    String? authorPhotoURL,
    String? category,
    DateTime? createdAt,
    String? userId,
    int? commentCount,
    int? likes,
    List<String>? likedBy,
    List<String>? imageUrls,
    String? visibility,
    bool? isAnonymous,
    List<String>? visibleToCategoryIds,
    List<String>? allowedUserIds,
  }) {
    return Post(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      author: author ?? this.author,
      authorNationality: authorNationality ?? this.authorNationality,
      authorPhotoURL: authorPhotoURL ?? this.authorPhotoURL,
      category: category ?? this.category,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      commentCount: commentCount ?? this.commentCount,
      likes: likes ?? this.likes,
      likedBy: likedBy ?? this.likedBy,
      imageUrls: imageUrls ?? this.imageUrls,
      visibility: visibility ?? this.visibility,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      visibleToCategoryIds: visibleToCategoryIds ?? this.visibleToCategoryIds,
      allowedUserIds: allowedUserIds ?? this.allowedUserIds,
    );
  }
}
