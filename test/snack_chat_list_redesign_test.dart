import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snack_chat.dart';
import 'package:wefilling/ui/widgets/snack_chat_card.dart';

SnackChat _chat({
  int hours = 0,
  Duration? remaining,
  String title = '예전예전 휴학생들 서울 모임방',
  String last = '오케이~~',
  List<String> favorites = const [],
  Map<String, int> unread = const {},
}) {
  final now = DateTime.now();
  return SnackChat(
    id: 'room',
    title: title,
    creatorId: 'u',
    participantIds: const [],
    visibleToCategoryIds: const [],
    createdAt: now,
    activeDurationHours: hours,
    expiresAt: hours == 24
        ? now.add(remaining ?? const Duration(hours: 21, minutes: 5))
        : SnackChat.noExpirationDate,
    favoriteUserIds: favorites,
    lastMessage: last,
    lastMessageTime: now,
    lastMessageSenderId: 'u',
    unreadCount: unread,
    updatedAt: now,
  );
}

Future<void> _pump(
  WidgetTester tester,
  SnackChat chat, {
  double width = 375,
  double scale = 1,
  VoidCallback? onLongPress,
  VoidCallback? onTap,
  String? uid = 'me',
}) async {
  await tester.binding.setSurfaceSize(Size(width, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('ko'),
    supportedLocales: const [Locale('ko'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 400),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: SnackChatCard(
          snackChat: chat,
          onTap: onTap ?? () {},
          onLongPress: onLongPress,
          currentUserId: uid,
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('줄 높이는 남은 시간이 있어도 72', (tester) async {
    await _pump(tester, _chat());
    final plain = tester.getSize(find.byType(SnackChatCard)).height;
    await _pump(tester, _chat(hours: 24));
    final timed = tester.getSize(find.byType(SnackChatCard)).height;
    expect(plain, 72);
    expect(timed, 72);
  });

  testWidgets('남은 시간은 미리보기 앞에 붙고 별도 줄이 없다', (tester) async {
    await _pump(tester, _chat(hours: 24, remaining: const Duration(hours: 20, minutes: 30)));
    expect(find.textContaining('21시간 남음 · 오케이~~', findRichText: true), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsNothing);
    expect(find.byType(SnackChatDurationStatus), findsNothing);
  });

  testWidgets('빈 별은 없고 즐겨찾기한 방만 채운 별', (tester) async {
    await _pump(tester, _chat());
    expect(find.byIcon(Icons.star_border_rounded), findsNothing);
    expect(find.byIcon(Icons.star_rounded), findsNothing);
    await _pump(tester, _chat(favorites: const ['me']));
    expect(find.byKey(const ValueKey('snack_chat_favorite_star')), findsOneWidget);
    expect(find.byIcon(Icons.star_border_rounded), findsNothing);
  });

  testWidgets('길게 누르기와 탭 콜백', (tester) async {
    var longs = 0;
    var taps = 0;
    await _pump(tester, _chat(),
        onLongPress: () => longs++, onTap: () => taps++);
    await tester.longPress(find.byType(SnackChatCard));
    expect(longs, 1);
    await tester.tap(find.byType(SnackChatCard));
    expect(taps, 1);
  });

  testWidgets('글자 크기: 이름 15 / 미리보기 13 / 날짜 11', (tester) async {
    await _pump(tester, _chat(unread: const {'me': 3}));
    double size(Finder f) => tester.widget<Text>(f).style!.fontSize!;
    expect(size(find.text('예전예전 휴학생들 서울 모임방')), 15);
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final fontSize =
          text.style?.fontSize ?? text.textSpan?.style?.fontSize ?? 14;
      expect(fontSize, lessThanOrEqualTo(15));
    }
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        await _pump(
          tester,
          _chat(
            hours: 24,
            title: 'a_very_long_snack_chat_room_title_that_never_ends_ever_more',
            last: '아주 긴 마지막 메시지 ' * 8,
            favorites: const ['me'],
            unread: const {'me': 120},
          ),
          width: width,
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(SnackChatCard)).height, 72);
      });
    }
  }
}
