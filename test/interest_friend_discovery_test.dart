import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations_en.dart';
import 'package:wefilling/l10n/app_localizations_ko.dart';
import 'package:wefilling/models/social_profile_data.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/repositories/users_repository.dart';

void main() {
  test('friend discovery uses unique managed profile interest ids', () {
    final ids = SocialProfileCatalog.interests
        .map((option) => option.id)
        .toList(growable: false);
    expect(ids.toSet(), hasLength(ids.length));
    expect(ids, <String>[
      'restaurants',
      'cafe',
      'running',
      'fitness',
      'soccer',
      'basketball',
      'travel',
      'photo',
      'movie',
      'music',
      'game',
      'reading',
      'language',
      'study',
      'exhibition',
      'performance',
      'volunteer',
      'startup',
      'development',
      'ai',
    ]);
  });

  test('interest result copy is localized', () {
    expect(
      AppLocalizationsKo().interestPeopleTitle('여행'),
      '#여행에 관심 있는 사람',
    );
    expect(
      AppLocalizationsEn().interestPeopleTitle('Travel'),
      'People interested in #Travel',
    );
  });

  test('interest search page keeps cursor and paging state', () {
    final now = DateTime(2026, 9, 5);
    final page = InterestUserSearchPage(
      users: <UserProfile>[
        UserProfile(
          uid: 'user-1',
          nickname: 'Friend',
          interests: const <String>['travel'],
          createdAt: now,
          updatedAt: now,
        ),
      ],
      nextCursor: 'user-1',
      hasMore: true,
    );

    expect(page.users.single.interests, const <String>['travel']);
    expect(page.nextCursor, 'user-1');
    expect(page.hasMore, isTrue);
  });
}
