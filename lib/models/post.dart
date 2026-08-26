// lib/models/post.dart
// 게시글 데이터 모델 정의
// 게시글 관련 속성 및 메서드 포함(제목,내용,작성자,작성일,좋아요 수 등)
// 데이터 포맷팅 메서드 제공(날짜, 미리보기 등)
// 번역 기능 추가

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../providers/settings_provider.dart';
import '../l10n/app_localizations.dart';
import 'post_category.dart';
import 'shared_link_preview.dart';

List<String> _normalizePostCategoryKeys(
  Iterable<Object?> values,
  Object? legacyKey,
) {
  final normalized = <String>[];
  for (final value in values) {
    final raw = value?.toString().trim() ?? '';
    if (!PostCategory.isSupportedKey(raw) || normalized.contains(raw)) {
      continue;
    }
    normalized.add(raw);
  }
  if (normalized.isNotEmpty) return normalized;
  return <String>[PostCategory.fromPersistedValue(legacyKey).key];
}

class PollOption {
  final String id;
  final String text;
  final int votes;

  const PollOption({
    required this.id,
    required this.text,
    this.votes = 0,
  });

  PollOption copyWith({String? id, String? text, int? votes}) {
    return PollOption(
      id: id ?? this.id,
      text: text ?? this.text,
      votes: votes ?? this.votes,
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'text': text, 'votes': votes};
  }

  factory PollOption.fromMap(Map<String, dynamic> map) {
    return PollOption(
      id: map['id']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      votes: (map['votes'] is int) ? (map['votes'] as int) : 0,
    );
  }
}

class Post {
  final String id;
  final String title;
  final String content;
  final String author;
  final String authorNationality; // 작성자 국적
  final String authorPhotoURL; // 작성자 프로필 사진 URL
  final String category; // 카테고리
  final String categoryKey; // 안정적인 Post 카테고리 저장 key
  final List<String> categoryKeys; // 선택한 포스트 태그 key 목록
  final DateTime createdAt;
  final String userId;
  final int commentCount;
  final int viewCount; // 조회수
  final int likes; // 좋아요 수
  final List<String> likedBy; // 좋아요 누른 사용자 ID 목록
  final List<String> imageUrls; // 이미지 URL 목록
  final SharedLinkPreview? linkPreview;

  // 게시글 타입 (기본: text)
  final String type; // 'text' | 'poll'

  // 투표형 게시글 데이터 (type == 'poll'일 때 사용)
  final List<PollOption> pollOptions;
  final int pollTotalVotes;

  // 공개 범위 관련 필드
  final String visibility; // 'public' 또는 'category'
  final bool isAnonymous; // 익명 여부
  final List<String> visibleToCategoryIds; // 공개할 카테고리 ID 목록
  final List<String> allowedUserIds; // 이 게시글을 볼 수 있는 사용자 ID 목록 (비공개용)
  final int visibilitySchemaVersion;
  final DateTime? visibilityLockedAt;
  final bool requiresHanyangVerification;

  String get ownerId => userId;
  String get visibilityMode => visibility;
  List<String> get audienceUserIdsFrozen => allowedUserIds;
  List<String> get sourceGroupIds => visibleToCategoryIds;

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
    this.category = '일반', // 레거시 필드 호환
    String? categoryKey,
    List<String> categoryKeys = const [],
    required this.createdAt,
    required this.userId,
    this.commentCount = 0,
    this.viewCount = 0,
    this.likes = 0,
    this.likedBy = const [],
    this.imageUrls = const [], // URL 변환 제거 - 원본 URL 그대로 사용
    this.linkPreview,
    this.type = 'text',
    this.pollOptions = const [],
    this.pollTotalVotes = 0,
    this.visibility = 'public', // 공개 범위 (기본값: 전체 공개)
    this.isAnonymous = false, // 익명 여부 (기본값: 실명)
    this.visibleToCategoryIds = const [], // 공개할 카테고리 목록 (기본값: 빈 리스트)
    this.allowedUserIds = const [], // 허용된 사용자 ID 목록 (기본값: 빈 리스트)
    this.visibilitySchemaVersion = 0,
    this.visibilityLockedAt,
    this.requiresHanyangVerification = false,
  })  : categoryKeys = _normalizePostCategoryKeys(
          categoryKeys,
          (categoryKey?.trim().isNotEmpty ?? false) ? categoryKey : category,
        ),
        categoryKey = _normalizePostCategoryKeys(
          categoryKeys,
          (categoryKey?.trim().isNotEmpty ?? false) ? categoryKey : category,
        ).first;

  PostCategory get postCategory => PostCategory.fromKey(categoryKey);
  List<PostCategory> get postCategories =>
      categoryKeys.map(PostCategory.fromKey).toList(growable: false);

  /// 현재 포스트 작성 화면은 제목과 본문을 나누지 않고 content 한 필드만
  /// 입력받는다. 과거 데이터의 title만 남아 있는 경우까지 한 곳에서 호환한다.
  String get displayText {
    final normalizedContent = content.trim();
    if (normalizedContent.isNotEmpty) return normalizedContent;
    return title.trim();
  }

  /// 공유 링크에 공식 썸네일이 없으면 공유 payload의 첫 이미지를 카드에
  /// 사용한다. 피드/상세 모두 같은 우선순위를 사용해 빈 카드가 생기지 않는다.
  String get sharedLinkCardFallbackImageUrl {
    final preview = linkPreview;
    if (preview == null || imageUrls.isEmpty) return '';
    if (preview.provider != 'youtube' && preview.provider != 'instagram') {
      return '';
    }
    final first = imageUrls.first.trim();
    return preview.thumbnailUrl.trim() == first ? first : '';
  }

  /// 첫 첨부 이미지를 링크 카드가 대신 표시하는 경우 본문 갤러리에서는
  /// 중복 노출하지 않는다. 나머지 사용자가 추가한 이미지는 그대로 유지한다.
  List<String> get standaloneImageUrls {
    final preview = linkPreview;
    if (preview == null || imageUrls.isEmpty) return imageUrls;
    if (preview.provider != 'youtube' && preview.provider != 'instagram') {
      return imageUrls;
    }

    final first = imageUrls.first.trim();
    final thumbnail = preview.thumbnailUrl.trim();
    final firstIsCardImage = thumbnail == first;
    if (!firstIsCardImage) return imageUrls;
    return List<String>.unmodifiable(imageUrls.skip(1));
  }

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
    final text = displayText;
    if (text.length <= 100) {
      return text;
    }
    return '${text.substring(0, 100)}...';
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
    if (!settings.autoTranslate) return displayText;
    if (_translatedContent != null) return _translatedContent!;

    _translatedContent = await settings.translateText(displayText);
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
    String? categoryKey,
    List<String>? categoryKeys,
    DateTime? createdAt,
    String? userId,
    int? commentCount,
    int? viewCount,
    int? likes,
    List<String>? likedBy,
    List<String>? imageUrls,
    SharedLinkPreview? linkPreview,
    String? type,
    List<PollOption>? pollOptions,
    int? pollTotalVotes,
    String? visibility,
    bool? isAnonymous,
    List<String>? visibleToCategoryIds,
    List<String>? allowedUserIds,
    int? visibilitySchemaVersion,
    DateTime? visibilityLockedAt,
    bool? requiresHanyangVerification,
  }) {
    return Post(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      author: author ?? this.author,
      authorNationality: authorNationality ?? this.authorNationality,
      authorPhotoURL: authorPhotoURL ?? this.authorPhotoURL,
      category: category ?? this.category,
      categoryKey: categoryKey ?? this.categoryKey,
      categoryKeys: categoryKeys ??
          (categoryKey != null ? <String>[categoryKey] : this.categoryKeys),
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      likes: likes ?? this.likes,
      likedBy: likedBy ?? this.likedBy,
      imageUrls: imageUrls ?? this.imageUrls,
      linkPreview: linkPreview ?? this.linkPreview,
      type: type ?? this.type,
      pollOptions: pollOptions ?? this.pollOptions,
      pollTotalVotes: pollTotalVotes ?? this.pollTotalVotes,
      visibility: visibility ?? this.visibility,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      visibleToCategoryIds: visibleToCategoryIds ?? this.visibleToCategoryIds,
      allowedUserIds: allowedUserIds ?? this.allowedUserIds,
      visibilitySchemaVersion:
          visibilitySchemaVersion ?? this.visibilitySchemaVersion,
      visibilityLockedAt: visibilityLockedAt ?? this.visibilityLockedAt,
      requiresHanyangVerification:
          requiresHanyangVerification ?? this.requiresHanyangVerification,
    );
  }

  // Map으로 변환 (캐싱용)
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'authorNickname': author,
      'authorNationality': authorNationality,
      'authorPhotoURL': authorPhotoURL,
      'category': category,
      'categoryKey': categoryKey,
      'categoryKeys': categoryKeys,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'userId': userId,
      'commentCount': commentCount,
      'viewCount': viewCount,
      'likes': likes,
      'likedBy': likedBy,
      'imageUrls': imageUrls,
      if (linkPreview != null) 'linkPreview': linkPreview!.toMap(),
      'type': type,
      'pollOptions': pollOptions.map((o) => o.toMap()).toList(),
      'pollTotalVotes': pollTotalVotes,
      'visibility': visibility,
      'isAnonymous': isAnonymous,
      'visibleToCategoryIds': visibleToCategoryIds,
      'allowedUserIds': allowedUserIds,
      'ownerId': ownerId,
      'visibilityMode': visibilityMode,
      'audienceUserIdsFrozen': audienceUserIdsFrozen,
      'sourceGroupIds': sourceGroupIds,
      'visibilitySchemaVersion': visibilitySchemaVersion,
      if (visibilityLockedAt != null)
        'visibilityLockedAt': visibilityLockedAt!.millisecondsSinceEpoch,
      'requiresHanyangVerification': requiresHanyangVerification,
    };
  }

  // Map에서 Post 객체 생성 (캐싱용)
  factory Post.fromMap(Map<String, dynamic> map, String id) {
    final dynamic rawPollOptions = map['pollOptions'];
    final List<PollOption> parsedPollOptions = (rawPollOptions is List)
        ? rawPollOptions
            .whereType<Map>()
            .map((m) => PollOption.fromMap(Map<String, dynamic>.from(m)))
            .toList()
        : const [];

    return Post(
      id: id,
      title: map['title'] ?? '',
      content: map['content'] ?? '',
      author: map['authorNickname'] ?? '익명',
      authorNationality: map['authorNationality'] ?? '',
      authorPhotoURL: map['authorPhotoURL'] ?? '',
      category: map['category'] ?? '일반',
      categoryKey: map['categoryKey']?.toString(),
      categoryKeys: map['categoryKeys'] is List
          ? List<String>.from(map['categoryKeys'])
          : const <String>[],
      createdAt: map['createdAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['createdAt'])
          : DateTime.now(),
      userId: map['ownerId'] ?? map['userId'] ?? '',
      commentCount: map['commentCount'] ?? 0,
      viewCount: map['viewCount'] ?? 0,
      likes: map['likes'] ?? 0,
      likedBy: List<String>.from(map['likedBy'] ?? []),
      imageUrls: List<String>.from(map['imageUrls'] ?? []),
      linkPreview: map['linkPreview'] is Map
          ? SharedLinkPreview.fromMap(
              Map<String, dynamic>.from(map['linkPreview'] as Map),
            )
          : null,
      type: map['type'] ?? 'text',
      pollOptions: parsedPollOptions,
      pollTotalVotes: map['pollTotalVotes'] ?? 0,
      visibility: map['visibilityMode'] ?? map['visibility'] ?? 'public',
      isAnonymous: map['isAnonymous'] ?? false,
      visibleToCategoryIds: List<String>.from(
          map['sourceGroupIds'] ?? map['visibleToCategoryIds'] ?? []),
      allowedUserIds: List<String>.from(
        map['audienceUserIdsFrozen'] ?? map['allowedUserIds'] ?? [],
      ),
      visibilitySchemaVersion:
          (map['visibilitySchemaVersion'] as num?)?.toInt() ?? 0,
      visibilityLockedAt: map['visibilityLockedAt'] is int
          ? DateTime.fromMillisecondsSinceEpoch(map['visibilityLockedAt'])
          : null,
      requiresHanyangVerification: map['requiresHanyangVerification'] == true,
    );
  }
}
