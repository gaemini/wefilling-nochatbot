import '../l10n/app_localizations.dart';

/// Stable product taxonomy for posts.
///
/// Only [key] is persisted. Labels and descriptions always come from ARB.
enum PostCategory {
  style('style'),
  create('create'),
  photo('photo'),
  content('content'),
  cafe('cafe'),
  academicStudy('academic_study'),
  booksWriting('books_writing'),
  travelLocal('travel_local'),
  global('global'),
  other('other');

  const PostCategory(this.key);

  final String key;

  static const List<PostCategory> ordered = values;

  static PostCategory fromKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    for (final category in values) {
      if (category.key == normalized) return category;
    }
    return PostCategory.other;
  }

  /// `categoryKey` 도입 전 저장된 한글·영문 카테고리도 현재의 안정적인
  /// key로 복원한다. 새 글 저장 검증에는 [isSupportedKey]를 계속 사용해
  /// 레거시 표시명이 다시 저장되는 것은 허용하지 않는다.
  static PostCategory fromPersistedValue(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return PostCategory.other;

    final direct = values.where((category) => category.key == raw);
    if (direct.isNotEmpty) return direct.first;

    final normalized = raw.toLowerCase().replaceAll(
          RegExp(r'[\s·・_\-/&]+'),
          '',
        );
    return switch (normalized) {
      'style' || 'fashion' || '스타일' => PostCategory.style,
      'create' ||
      'restaurant' ||
      'food' ||
      '레스토랑' ||
      '맛집' =>
        PostCategory.create,
      'photo' || 'photos' || '사진' => PostCategory.photo,
      'content' || 'contents' || '콘텐츠' => PostCategory.content,
      'cafe' || 'café' || '카페' => PostCategory.cafe,
      'academicstudy' ||
      'academicsstudy' ||
      'academic' ||
      'study' ||
      '학업스터디' ||
      '스터디' =>
        PostCategory.academicStudy,
      'bookswriting' ||
      'bookwriting' ||
      'books' ||
      'writing' ||
      '책글' =>
        PostCategory.booksWriting,
      'travellocal' ||
      'travel' ||
      'local' ||
      '여행로컬' =>
        PostCategory.travelLocal,
      'global' || '글로벌' => PostCategory.global,
      'other' || 'general' || 'normal' || '기타' || '일반' => PostCategory.other,
      _ => PostCategory.other,
    };
  }

  static bool isSupportedKey(Object? value) {
    final normalized = value?.toString().trim() ?? '';
    return values.any((category) => category.key == normalized);
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      PostCategory.style => l10n.postCategoryStyle,
      PostCategory.create => l10n.postCategoryCreate,
      PostCategory.photo => l10n.postCategoryPhoto,
      PostCategory.content => l10n.postCategoryContent,
      PostCategory.cafe => l10n.postCategoryCafe,
      PostCategory.academicStudy => l10n.postCategoryAcademicStudy,
      PostCategory.booksWriting => l10n.postCategoryBooksWriting,
      PostCategory.travelLocal => l10n.postCategoryTravelLocal,
      PostCategory.global => l10n.postCategoryGlobal,
      PostCategory.other => l10n.postCategoryOther,
    };
  }

  String description(AppLocalizations l10n) {
    return switch (this) {
      PostCategory.style => l10n.postCategoryStyleDescription,
      PostCategory.create => l10n.postCategoryCreateDescription,
      PostCategory.photo => l10n.postCategoryPhotoDescription,
      PostCategory.content => l10n.postCategoryContentDescription,
      PostCategory.cafe => l10n.postCategoryCafeDescription,
      PostCategory.academicStudy =>
          l10n.postCategoryAcademicStudyDescription,
      PostCategory.booksWriting => l10n.postCategoryBooksWritingDescription,
      PostCategory.travelLocal => l10n.postCategoryTravelLocalDescription,
      PostCategory.global => l10n.postCategoryGlobalDescription,
      PostCategory.other => l10n.postCategoryOtherDescription,
    };
  }
}
