import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/content_translation.dart';
import 'package:wefilling/services/content_translation_service.dart';
import 'package:wefilling/ui/widgets/post_chat_translated_text.dart';

import 'support/translation_test_backend.dart';

const _original = '나는 음악을 좋아해요';

Future<void> waitFor(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 250 && !done(); i++) {
    await tester.runAsync(() async {
      await Future<void>.value();
    });
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(done(), isTrue);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  late ContentTranslationService service;
  var serial = 0;

  setUpAll(() async {
    await backend.initialize();
    service = ContentTranslationService.instance;
  });
  setUp(() {
    backend.calls.clear();
    backend.handler = backend.completedBatch;
  });
  tearDownAll(backend.close);

  ({ContentTranslationRequest request, String scope}) fresh() {
    final id = 'chat-${serial++}';
    return (
      request: backend.request(id, type: 'comment', parentId: 'post-1'),
      scope: 'post-comments:post-$id',
    );
  }

  Future<void> pump(
    WidgetTester tester,
    ContentTranslationRequest request,
    String scope, {
    bool isCandidate = true,
    double width = 375,
    double scale = 1,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('ko'),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, 600),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width - 52 - 16 - 36 - 24),
              child: PostChatTranslatedText(
                request: request,
                scope: scope,
                isCandidate: isCandidate,
                builder: (context, fields) => Text(fields['content']!),
              ),
            ),
          ),
        ),
      ),
    ));
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  void expectOnly(String shown, String hidden) {
    expect(find.text(shown), findsOneWidget);
    expect(find.text(hidden), findsNothing);
  }

  testWidgets('번역됨: 번역문만, 발 줄은 원문 언어만(원문 보기 링크 없음)',
      (tester) async {
    final item = fresh();
    final translated = 'Translated ${item.request.contentId}';
    await pump(tester, item.request, item.scope);
    await waitFor(tester, () => find.text(translated).evaluate().isNotEmpty);
    expectOnly(translated, _original);
    expect(find.textContaining('원문 언어'), findsOneWidget);
    expect(find.textContaining('원문 보기'), findsNothing);
    await settle(tester);
  });

  testWidgets('스코프 꺼짐: 원문만, 번역 보기 링크·발 줄 없음', (tester) async {
    final item = fresh();
    service.toggleScope(item.scope);
    addTearDown(() => service.toggleScope(item.scope));
    await pump(tester, item.request, item.scope);
    await waitFor(
        tester, () => service.latestOutcomeFor(item.request) != null);
    expectOnly(_original, 'Translated ${item.request.contentId}');
    expect(find.text('번역 보기'), findsNothing);
    expect(find.byIcon(Icons.translate_rounded), findsNothing);
    await settle(tester);
  });

  testWidgets('번역 중: 300ms 뒤에만, 원문 유지', (tester) async {
    final item = fresh();
    final held = Completer<Object?>();
    backend.handler = (_) => held.future;
    await pump(tester, item.request, item.scope);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('번역 중'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('번역 중'), findsOneWidget);
    expectOnly(_original, 'Translated ${item.request.contentId}');
    held.complete(<String, Object?>{'items': <Object?>[]});
    await settle(tester);
  });

  testWidgets('실패: 원문 + 다시 번역', (tester) async {
    final item = fresh();
    backend.handler = (batch) => {
          'items': (batch['items'] as List)
              .cast<Map>()
              .map((raw) => {
                    'id': backend.idOf(raw),
                    'status': 'failed',
                    'errorCode': 'permission-denied',
                  })
              .toList(),
        };
    await pump(tester, item.request, item.scope);
    await waitFor(tester, () => find.text('다시 번역').evaluate().isNotEmpty);
    expectOnly(_original, 'Translated ${item.request.contentId}');
    await settle(tester);
  });

  testWidgets('다시 번역: 누르면 바로 번역 중, 성공하면 번역문', (tester) async {
    final item = fresh();
    backend.handler = (batch) => {
          'items': (batch['items'] as List)
              .cast<Map>()
              .map((raw) => {
                    'id': backend.idOf(raw),
                    'status': 'failed',
                    'errorCode': 'internal',
                  })
              .toList(),
        };
    await pump(tester, item.request, item.scope);
    await waitFor(tester, () => find.text('다시 번역').evaluate().isNotEmpty);
    final callsBefore = backend.calls.length;

    final held = Completer<Object?>();
    backend.handler = (_) => held.future;
    await tester.tap(find.text('다시 번역'));
    await tester.pump();
    // 누른 즉시 '다시 번역'이 사라진다(이전에는 응답까지 그대로 남았다).
    expect(find.text('다시 번역'), findsNothing);

    backend.handler = backend.completedBatch;
    held.complete(backend.completedBatch(
      backend.calls.isEmpty ? <String, dynamic>{} : backend.calls.last,
    ));
    final translated = 'Translated ${item.request.contentId}';
    await waitFor(tester, () => find.text(translated).evaluate().isNotEmpty);
    expect(backend.calls.length, greaterThan(callsBefore));
    await settle(tester);
  });

  testWidgets('대상 아님(내 댓글 등): 원문만, 요청·발 줄 없음', (tester) async {
    final item = fresh();
    await pump(tester, item.request, item.scope, isCandidate: false);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text(_original), findsOneWidget);
    expect(find.byIcon(Icons.translate_rounded), findsNothing);
    expect(backend.calls, isEmpty);
    await settle(tester);
  });

  for (final width in const [320.0, 375.0, 430.0]) {
    for (final scale in const [1.0, 1.3, 2.0]) {
      testWidgets('오버플로우 없음 $width/$scale', (tester) async {
        final item = fresh();
        await pump(tester, item.request, item.scope,
            width: width, scale: scale);
        await waitFor(tester,
            () => service.latestOutcomeFor(item.request) != null);
        expect(tester.takeException(), isNull);
        await settle(tester);
      });
    }
  }
}
