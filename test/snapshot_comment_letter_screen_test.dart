import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snapshot_comment_letter.dart';
import 'package:wefilling/screens/snapshot_comment_letter_screen.dart';

SnapshotCommentLetter _letter({required bool replied}) {
  return SnapshotCommentLetter(
    notificationId: 'snapshot_comment_snapshot_user',
    originalNotificationId: 'snapshot_comment_snapshot_user',
    snapshotId: 'snapshot',
    ownerId: 'owner',
    ownerName: 'owner-with-a-very-long-display-name',
    ownerPhotoUrl: '',
    commenterId: 'commenter',
    commenterName: 'commenter-with-a-very-long-display-name',
    commenterPhotoUrl: '',
    comment: 'This is the original private Snack comment.',
    reply: replied ? 'This is the one allowed reply.' : '',
    commentCreatedAt: DateTime.now().subtract(const Duration(minutes: 2)),
    repliedAt:
        replied ? DateTime.now().subtract(const Duration(minutes: 1)) : null,
    viewerRole: 'owner',
    canReply: !replied,
    sourceAuthorName: 'Snack owner',
    sourceText: '오늘의 하늘',
    sourceCreatedAt: DateTime.now().subtract(const Duration(minutes: 4)),
  );
}

void main() {
  testWidgets('작은 화면에서도 답장을 한 번만 보내고 입력창을 닫는다', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);

    var replied = false;
    var sendCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ko'),
        supportedLocales: const <Locale>[Locale('ko'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 640),
            padding: EdgeInsets.only(bottom: 24),
            viewPadding: EdgeInsets.only(bottom: 24),
            textScaler: TextScaler.linear(2),
          ),
          child: SnapshotCommentLetterScreen(
            notificationId: 'snapshot_comment_snapshot_user',
            letterLoader: (_) async => _letter(replied: replied),
            replySender: (_, __) async {
              sendCount += 1;
              replied = true;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('스낵 편지'), findsOneWidget);
    expect(find.text('Snack owner님이 올린 스낵'), findsOneWidget);
    expect(find.text('“오늘의 하늘”'), findsOneWidget);
    final sourceMediaSize = tester.getSize(
      find.byKey(const ValueKey<String>('snack-letter-source-image')),
    );
    expect(sourceMediaSize.width, greaterThan(250));
    expect(sourceMediaSize.height, greaterThanOrEqualTo(210));
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), '한 번만 보내는 답장');
    await tester.pump();
    await tester.tap(find.byTooltip('답장 보내기'));
    await tester.pumpAndSettle();

    expect(sendCount, 1);
    expect(find.text('나의 답장'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('코멘트 작성자는 알림에서 원문과 답장만 확인한다', (tester) async {
    final replyLetter = SnapshotCommentLetter(
      notificationId: 'snapshot_comment_reply_snapshot_user',
      originalNotificationId: 'snapshot_comment_snapshot_user',
      snapshotId: 'snapshot',
      ownerId: 'owner',
      ownerName: 'Snack owner',
      ownerPhotoUrl: '',
      commenterId: 'commenter',
      commenterName: 'Commenter',
      commenterPhotoUrl: '',
      comment: 'Original comment',
      reply: 'Only reply',
      commentCreatedAt: DateTime.now(),
      repliedAt: DateTime.now(),
      viewerRole: 'commenter',
      canReply: false,
      sourceAuthorName: 'Snack owner',
      sourceText: 'Sunset walk',
      sourceCreatedAt: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const <Locale>[Locale('ko'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: SnapshotCommentLetterScreen(
          notificationId: replyLetter.notificationId,
          letterLoader: (_) async => replyLetter,
          replySender: (_, __) async => fail('commenter cannot reply'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Original comment'), findsOneWidget);
    expect(find.text('A Snack by Snack owner'), findsOneWidget);
    expect(find.text('“Sunset walk”'), findsOneWidget);
    expect(find.text('Only reply'), findsOneWidget);
    expect(find.text("Snack owner's reply"), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });
}
