import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/services/interest_tag_service.dart';
import 'package:wefilling/services/my_tags_store.dart';
import 'package:wefilling/ui/interest/friend_interest_section.dart';
import 'package:wefilling/ui/interest/interest_block_tile.dart';

import 'chinese_ui_localization_test.dart' show app, chinese;
import 'support/translation_test_backend.dart';

class _Auth extends Fake with ChangeNotifier implements AuthProvider {
  _Auth(this.tags);
  List<String> tags;
  @override
  Map<String, dynamic>? get userData => {'interestTagIds': tags};
  @override
  Future<void> refreshUser() async => notifyListeners();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  setUpAll(() async {
    await backend.initialize();
    for (final entry in {
      'Inter': 'assets/fonts/Inter/Inter-Variable.ttf',
      'NotoSansKR': 'assets/fonts/NotoSansKR/NotoSansKR-Variable.ttf',
      'NotoSansSC': 'assets/fonts/NotoSansSC/NotoSansSC-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
    InterestBlockTile.breathingEnabled = false;
  });
  tearDownAll(backend.close);

  final saved = <List<Object?>>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    saved.clear();
    MyTagsStore.instance.debugReset();
    InterestTagService.instance
      ..debugReset()
      ..debugGetTag = ((id) async => null)
      ..debugCall = (name, data) async {
        if (name == 'setProfileTags') {
          saved.add(data['tagIds'] as List<Object?>);
          return {'tagIds': data['tagIds'], 'gain': {}};
        }
        throw UnimplementedError(name);
      };
    for (final (id, ko, holders) in [
      ('travel', '여행', 26),
      ('cafe', '카페', 33),
      ('game', '게임', 12),
    ]) {
      InterestTagService.instance.debugPut(InterestTag(
          id: id, displayName: id, labels: {'ko': ko}, holderCount: holders));
    }
  });
  tearDown(() {
    InterestTagService.instance.debugReset();
    MyTagsStore.instance.debugReset();
  });

  Widget host(_Auth auth, {Locale locale = const Locale('ko'), double scale = 1}) =>
      ChangeNotifierProvider<AuthProvider>.value(
        value: auth,
        child: app(
          const Scaffold(
            body: SingleChildScrollView(
              child: FriendInterestSection(tags: ['travel', 'cafe', 'game']),
            ),
          ),
          locale: locale,
          scale: scale,
        ),
      );

  test('친구 프로필은 관심 | 활동 탭을 쓴다(소스 계약)', () {
    final source =
        File('lib/screens/friend_profile_screen.dart').readAsStringSync();
    expect(source.contains('ProfileTabBar('), isTrue);
    expect(source.contains('FriendInterestSection('), isTrue);
    expect(source.contains('includeTags: false'), isTrue);
  });

  testWidgets('겹치는 태그가 먼저·✓, 아닌 태그는 ＋로 바로 내 태그', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 1000);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(_Auth(['cafe'])));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
        tester.element(find.byType(FriendInterestSection)))!;
    expect(find.text(l10n.friendOverlapCaption(1)), findsOneWidget);
    // 겹치는 '카페'가 큰 칸(첫 자리).
    final cafe = tester.getTopLeft(find.byKey(const ValueKey('interest_block_cafe')));
    final travel =
        tester.getTopLeft(find.byKey(const ValueKey('interest_block_travel')));
    // 큰 칸(왼쪽 위 2×2) 다음 오른쪽 위가 여행.
    expect(cafe.dx < travel.dx, isTrue);
    expect(cafe.dy, travel.dy);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('interest_block_add_cafe')),
            matching: find.byIcon(Icons.check_rounded)),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('interest_block_add_travel')));
    await tester.pumpAndSettle();
    expect(saved.single, ['cafe', 'travel']);
  });

  for (final width in [320.0, 375.0, 430.0]) {
    for (final scale in [1.0, 1.3]) {
      testWidgets('친구 관심 넘침 없음 ${width.toInt()} / ${scale}x', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1000);
        addTearDown(tester.view.reset);
        for (final locale in [const Locale('ko'), const Locale('en'), chinese]) {
          await tester.pumpWidget(
              host(_Auth(['cafe']), locale: locale, scale: scale));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$locale');
        }
      });
    }
  }
}
