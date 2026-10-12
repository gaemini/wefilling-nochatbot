import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/user_profile.dart';
import 'package:wefilling/repositories/users_repository.dart';
import 'package:wefilling/ui/widgets/snack_chat_participant_picker.dart';

UserProfile _profile(String uid, String nickname) {
  final now = DateTime(2026, 1, 1);
  return UserProfile(
    uid: uid,
    nickname: nickname,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  testWidgets('searches non-friends case-insensitively and keeps selections',
      (tester) async {
    final friend = _profile('friend-1', 'friend_one');
    final nonFriend = _profile('user-2', 'not_friend');
    final selected = <String, UserProfile>{};

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return SnackChatParticipantPicker(
                friends: <UserProfile>[friend],
                selectedProfiles: selected,
                searchUserById: (query, {cursor}) async {
                  return SnackChatUserSearchPage(
                    users: query.toLowerCase() == 'not_friend'
                        ? <UserProfile>[nonFriend]
                        : const <UserProfile>[],
                  );
                },
                onToggle: (profile) {
                  setState(() {
                    if (selected.containsKey(profile.uid)) {
                      selected.remove(profile.uid);
                    } else {
                      selected[profile.uid] = profile;
                    }
                  });
                },
              );
            },
          ),
        ),
      ),
    );

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('All · ID search'), findsOneWidget);
    expect(find.text('friend_one'), findsOneWidget);

    await tester.tap(find.text('All · ID search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'NOT_FRIEND');
    await tester.tap(
      find.byKey(const Key('snack_chat_participant_search_button')),
    );
    await tester.pumpAndSettle();

    expect(find.text('@not_friend'), findsOneWidget);
    await tester.tap(find.text('@not_friend'));
    await tester.pump();

    expect(selected.keys, contains('user-2'));
    expect(find.text('not_friend'), findsWidgets);
  });

  testWidgets('compact screen stays overflow-free with the keyboard open',
      (tester) async {
    const size = Size(320, 568);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: size,
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
            viewInsets: EdgeInsets.only(bottom: 280),
            textScaler: TextScaler.linear(1.25),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            body: SnackChatParticipantPicker(
              friends: const <UserProfile>[],
              selectedProfiles: const <String, UserProfile>{},
              searchUserById: (_, {cursor}) async =>
                  const SnackChatUserSearchPage(users: <UserProfile>[]),
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('All · ID search'));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('No matching user'), findsOneWidget);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
  });

  testWidgets(
      'selected participant strip stays overflow-free with the keyboard open',
      (tester) async {
    const size = Size(320, 568);
    final selectedUser = _profile('selected-1', '테스트172');
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: size,
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
            viewInsets: EdgeInsets.only(bottom: 280),
            textScaler: TextScaler.linear(1.3),
          ),
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            body: SnackChatParticipantPicker(
              friends: const <UserProfile>[],
              selectedProfiles: <String, UserProfile>{
                selectedUser.uid: selectedUser,
              },
              searchUserById: (_, {cursor}) async =>
                  const SnackChatUserSearchPage(users: <UserProfile>[]),
              onToggle: (_) {},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('All · ID search'));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '테스트');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('테스트172'), findsOneWidget);
  });

  testWidgets('loads all-user search results 10 at a time', (tester) async {
    final firstPage = List<UserProfile>.generate(
      10,
      (index) => _profile('user-$index', 'anto_$index'),
    );
    final secondPage = <UserProfile>[
      _profile('user-10', 'anto_10'),
      _profile('user-11', 'anto_11'),
    ];
    final cursors = <String?>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SnackChatParticipantPicker(
            friends: const <UserProfile>[],
            selectedProfiles: const <String, UserProfile>{},
            searchUserById: (query, {cursor}) async {
              cursors.add(cursor);
              return cursor == null
                  ? SnackChatUserSearchPage(
                      users: firstPage,
                      nextCursor: 'anto_9',
                    )
                  : SnackChatUserSearchPage(users: secondPage);
            },
            onToggle: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('All · ID search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'AnTo');
    await tester.tap(
      find.byKey(const Key('snack_chat_participant_search_button')),
    );
    await tester.pumpAndSettle();

    expect(cursors, <String?>[null]);
    expect(find.text('@anto_0'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('snack_chat_load_more_users')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const Key('snack_chat_load_more_users')));
    await tester.pumpAndSettle();

    expect(cursors, <String?>[null, 'anto_9']);
    expect(find.text('@anto_10'), findsOneWidget);
  });

  testWidgets('ignores a stale response after the query changes',
      (tester) async {
    final oldResponse = Completer<SnackChatUserSearchPage>();
    final newResponse = Completer<SnackChatUserSearchPage>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SnackChatParticipantPicker(
            friends: const <UserProfile>[],
            selectedProfiles: const <String, UserProfile>{},
            searchUserById: (query, {cursor}) {
              return query == 'old' ? oldResponse.future : newResponse.future;
            },
            onToggle: (_) {},
          ),
        ),
      ),
    );

    await tester.tap(find.text('All · ID search'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.tap(
      find.byKey(const Key('snack_chat_participant_search_button')),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'new');
    await tester.tap(
      find.byKey(const Key('snack_chat_participant_search_button')),
    );
    await tester.pump();

    newResponse.complete(
      SnackChatUserSearchPage(users: <UserProfile>[_profile('new', 'new_id')]),
    );
    await tester.pump();
    expect(find.text('@new_id'), findsOneWidget);

    oldResponse.complete(
      SnackChatUserSearchPage(users: <UserProfile>[_profile('old', 'old_id')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('@new_id'), findsOneWidget);
    expect(find.text('@old_id'), findsNothing);
  });
}
