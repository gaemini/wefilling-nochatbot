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
      PostCategory.booksWriting => l10n.postCategoryBooksWritingDescription,
      PostCategory.travelLocal => l10n.postCategoryTravelLocalDescription,
      PostCategory.global => l10n.postCategoryGlobalDescription,
      PostCategory.other => l10n.postCategoryOtherDescription,
    };
  }
}
