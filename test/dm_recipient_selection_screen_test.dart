import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/screens/dm_recipient_selection_screen.dart';
import 'package:wefilling/ui/widgets/user_avatar.dart';

UserProfile _profile(String uid, String nickname) {
  final now = DateTime(2026, 9, 17);
  return UserProfile(
    uid: uid,
    nickname: nickname,
    createdAt: now,
    updatedAt: now,
  );
}

Widget _app({
  required List<UserProfile> friends,
  required Future<List<UserProfile>> Function(String query) searchUsers,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DmRecipientSelectionScreen(
      cacheOwnerId: 'test-owner',
      friendsStream: Stream<List<UserProfile>>.value(friends),
      searchUsers: searchUsers,
    ),
  );
}

void main() {
  test('friend filtering is case-insensitive and preserves source order', () {
    final friends = <UserProfile>[
      _profile('one', 'Alpha'),
      _profile('two', 'beta'),
      _profile('three', 'ALPINE'),
    ];

    expect(
      filterDmRecipientFriends(friends, 'alp').map((profile) => profile.uid),
      <String>['one', 'three'],
    );
    expect(
      filterDmRecipientFriends(friends, '  BETA  ')
          .map((profile) => profile.uid),
      <String>['two'],
    );
    expect(
        friends.map((profile) => profile.uid), <String>['one', 'two', 'three']);
  });

  testWidgets('renders as a full page and searches user IDs', (tester) async {
    final alice = _profile('friend-alice', 'alice');
    final bob = _profile('friend-bob', 'bob');
    final outsider = _profile('user-outsider', 'outsider');
    final queries = <String>[];

    await tester.pumpWidget(
      _app(
        friends: <UserProfile>[alice, bob],
        searchUsers: (query) async {
          queries.add(query);
          return query.toLowerCase() == 'outsider'
              ? <UserProfile>[outsider]
              : const <UserProfile>[];
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(Scaffold), findsOneWidget);
    expect(find.text('New message'), findsOneWidget);
    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('ID search'), findsOneWidget);
    expect(find.text('alice'), findsOneWidget);
    expect(find.text('bob'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('dm_recipient_search_field')),
      'BO',
    );
    await tester.pump();
    expect(find.text('alice'), findsNothing);
    expect(find.text('bob'), findsOneWidget);

    await tester.tap(find.text('ID search'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('dm_recipient_search_field')),
      'outsider',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(queries, <String>['outsider']);
    expect(find.text('@outsider'), findsOneWidget);
    expect(find.byType(UserAvatar), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('returns the selected profile to the DM flow', (tester) async {
    final alice = _profile('friend-alice-route', 'alice_route');
    UserProfile? selected;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.of(context).push<UserProfile>(
                  MaterialPageRoute<UserProfile>(
                    builder: (_) => DmRecipientSelectionScreen(
                      cacheOwnerId: 'route-owner',
                      friendsStream: Stream<List<UserProfile>>.value(
                        <UserProfile>[alice],
                      ),
                      searchUsers: (_) async => const <UserProfile>[],
                    ),
                  ),
                );
              },
              child: const Text('Open selector'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open selector'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('alice_route'));
    await tester.pumpAndSettle();

    expect(selected, same(alice));
    expect(find.text('Open selector'), findsOneWidget);
  });

  testWidgets('compact phone layout stays overflow-free with keyboard inset',
      (tester) async {
    const size = Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: size,
          padding: EdgeInsets.only(top: 24, bottom: 24),
          viewPadding: EdgeInsets.only(top: 24, bottom: 24),
          viewInsets: EdgeInsets.only(bottom: 280),
          textScaler: TextScaler.linear(1.3),
        ),
        child: _app(
          friends: <UserProfile>[_profile('friend', 'compact_friend')],
          searchUsers: (_) async => const <UserProfile>[],
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ID search'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('dm_recipient_search_field')),
      'missing',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('No results found'), findsOneWidget);
  });
}
