import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:wefilling/providers/auth_provider.dart';
import 'package:wefilling/screens/login_screen.dart';
import 'package:wefilling/screens/meetup_detail_screen.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/ui/widgets/board_meetup_card.dart';
import 'package:wefilling/ui/widgets/snack_chat_chrome.dart';
import 'package:wefilling/ui/snackbar/app_snackbar.dart';
import 'package:wefilling/ui/sheets/snack_chat_attachment_sheet.dart';
import 'package:wefilling/screens/account_settings_screen.dart';
import 'package:wefilling/services/app_messenger.dart';
import 'support/translation_test_backend.dart';
import 'package:wefilling/design/theme.dart';
import 'package:wefilling/l10n/app_localizations.dart';
import 'package:wefilling/l10n/chinese_terms.dart';
import 'package:wefilling/l10n/ui_locale.dart';
import 'package:wefilling/models/social_profile_data.dart';
import 'package:wefilling/screens/nickname_setup_screen.dart';
import 'package:wefilling/services/language_service.dart';
import 'package:wefilling/services/snack_chat_service.dart';
import 'package:wefilling/snapshot/snapshot_strings.dart';
import 'package:wefilling/ui/dialogs/snack_chat_poll_dialog.dart';
import 'package:wefilling/ui/sheets/snack_chat_unread_summary_sheet.dart';
import 'package:wefilling/ui/sheets/translation_language_sheet.dart';
import 'package:wefilling/utils/country_flag_helper.dart';
import 'package:wefilling/widgets/adaptive_bottom_navigation.dart';

const chinese = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans');

class _UiAuth extends Fake with ChangeNotifier implements AuthProvider {
  @override
  bool get isLoading => false;
  @override
  bool consumeSignupRequiredFlag() => false;
}

Widget app(Widget child, {Locale locale = chinese, double scale = 1.3}) =>
    MaterialApp(
      scaffoldMessengerKey: AppMessenger.scaffoldMessengerKey,
      locale: locale,
      supportedLocales: const [Locale('ko'), Locale('en'), chinese],
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: AppTheme.light(locale: locale),
      builder: (context, child) => RepaintBoundary(
        key: const ValueKey('chinese_ui_capture'),
        child: MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
      home: child,
    );

void smallScreen(WidgetTester tester, {double width = 320}) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 568);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> capture(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('CAPTURE_ZH_UI')) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('chinese_ui_capture')));
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/wefilling-zh-$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();

  setUpAll(() async {
    await backend.initialize();
    final font = FontLoader('NotoSansSC')
      ..addFont(
          rootBundle.load('assets/fonts/NotoSansSC/NotoSansSC-Variable.ttf'));
    await font.load();
    for (final entry in {
      'Inter': 'assets/fonts/Inter/Inter-Variable.ttf',
      'NotoSansKR': 'assets/fonts/NotoSansKR/NotoSansKR-Variable.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(entry.key)..addFont(rootBundle.load(entry.value)))
          .load();
    }
  });
  tearDownAll(() => backend.close());

  test('Chinese ARB covers every existing key and preserves placeholders', () {
    final ko =
        jsonDecode(File('lib/l10n/app_ko.arb').readAsStringSync()) as Map;
    final zh =
        jsonDecode(File('lib/l10n/app_zh.arb').readAsStringSync()) as Map;
    final keys =
        ko.keys.where((key) => !(key as String).startsWith('@')).toSet();
    expect(
        zh.keys.where((key) => !(key as String).startsWith('@')).toSet(), keys);
    for (final key in keys) {
      expect(zh[key], isNotEmpty, reason: key);
      final metadata = ko['@$key'];
      if (metadata is Map && metadata['placeholders'] is Map) {
        for (final placeholder in (metadata['placeholders'] as Map).keys) {
          expect((zh[key] as String).contains('{$placeholder}'), isTrue,
              reason: '$key: $placeholder');
        }
      }
    }
    expect(zh['appName'], '微邻');
    expect(zh['appInfoTitle'], '微邻');
    expect(zh['wefillingMeaning'], contains('微邻'));
    expect(zh['continueWithWefillingAccount'], contains('微邻'));
    expect(zh['copyright'], contains('微邻'));
    expect((zh.values.whereType<String>().join('\n')),
        isNot(contains('Wefilling')));
  });

  test(
      'language persists across service instances and invalid fallback is Korean',
      () async {
    SharedPreferences.setMockInitialValues({});
    expect(await LanguageService().getLanguage(), 'ko');
    for (final code in ['ko', 'en', 'zh_Hans']) {
      await LanguageService().saveLanguage(code);
      expect(await LanguageService().getLanguage(), code);
    }
    expect(uiLocale('zh_Hans'), chinese);
    expect(uiLocale('zh_Hans_CN'), chinese);
    await LanguageService().saveLanguage('invalid');
    expect(await LanguageService().getLanguage(), 'ko');
  });

  test('profile labels and countries translate without changing stored IDs',
      () {
    for (final options in [
      SocialProfileCatalog.interests,
      SocialProfileCatalog.activities,
      SocialProfileCatalog.conversationStarters,
      SocialProfileCatalog.friendshipPrompts
    ]) {
      for (final option in options) {
        expect(option.zh, isNotNull);
        expect(option.label('ko'), option.ko);
        expect(option.label('en'), option.en);
        expect(option.label('zh'), option.zh);
      }
    }
    expect(CountryFlagHelper.getLocalizedCountryName('중국', 'zh'), '中国');
    for (final country in CountryFlagHelper.allCountries) {
      expect(
          RegExp(r'[\u4e00-\u9fff]').hasMatch(country.getLocalizedName('zh')),
          isTrue,
          reason: country.isoCode);
    }
    expect(SocialProfileValidation.nicknameError('中文昵称', 'zh'),
        '仅支持韩文、英文字母、数字和下划线。');
  });

  testWidgets('switching all locales preserves Korean/English fonts and labels',
      (tester) async {
    for (final locale in [
      const Locale('ko'),
      const Locale('en'),
      chinese,
      const Locale('ko')
    ]) {
      await tester.pumpWidget(app(Builder(builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        return Scaffold(
            body: Text(l10n.settings,
                style: uiTextStyle(
                    context,
                    const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.1))));
      }), locale: locale));
      await tester.pumpAndSettle();
      final label = locale.languageCode == 'zh'
          ? '设置'
          : locale.languageCode == 'ko'
              ? '설정'
              : 'Settings';
      final style = tester.widget<Text>(find.text(label)).style!;
      expect(style.fontFamily,
          locale.languageCode == 'zh' ? 'NotoSansSC' : 'Inter');
      expect(style.fontSize, 16);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.height, locale.languageCode == 'zh' ? 1.3 : 1.1);
      expect(tester.takeException(), isNull);
    }
  });

  for (final width in [320.0, 360.0, 430.0]) {
    testWidgets('Chinese bottom navigation fits at $width with large text',
        (tester) async {
      smallScreen(tester, width: width);
      await tester.pumpWidget(app(
          Scaffold(
              bottomNavigationBar: AdaptiveBottomNavigation(
            selectedIndex: 2,
            onItemTapped: (_) {},
            items: [
              for (final label in ['动态', '聚会', '群聊', '我的', '私信'])
                BottomNavigationItem(icon: Icons.circle_outlined, label: label)
            ],
          )),
          scale: 2));
      await tester.pumpAndSettle();
      for (final label in ['动态', '聚会', '群聊', '我的', '私信']) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Chinese profile form and interest chips fit small screens',
      (tester) async {
    smallScreen(tester);
    await tester.pumpWidget(app(const NicknameSetupScreen()));
    await tester.pumpAndSettle();
    expect(find.text('昵称'), findsOneWidget);
    expect(find.text('国籍'), findsOneWidget);
    expect(tester.takeException(), isNull);
    final pager = tester.widget<PageView>(find.byType(PageView));
    pager.controller!.jumpToPage(1);
    await tester.pumpAndSettle();
    expect(find.text('最近对什么感兴趣？'), findsOneWidget);
    await tester.ensureVisible(find.text('咖啡馆'));
    await tester.tap(find.text('咖啡馆'));
    await tester.pumpAndSettle();
    expect(find.text('1/5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Chinese translation sheet wraps guidance and retains language codes',
      (tester) async {
    smallScreen(tester);
    String? selected;
    await tester.pumpWidget(app(Scaffold(
        body: TranslationLanguageSheet(
      selectedCode: 'en',
      forSnackChat: true,
      onSelected: (code) async => selected = code,
    ))));
    await tester.pumpAndSettle();
    expect(find.text('翻译目标语言'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('translation_language_zh')));
    await tester.pumpAndSettle();
    expect(selected, 'zh');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Chinese poll AppBar, buttons and form fit and preserve submission',
      (tester) async {
    smallScreen(tester);
    await tester.pumpWidget(app(Builder(
        builder: (context) => Scaffold(
            body: TextButton(
                onPressed: () => showSnackChatPollDialog(context),
                child: const Text('open'))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('创建出席投票'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(find.byType(TextFormField).first, '周末一起去看展吗？');
    await tester.tap(find.byTooltip('创建'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackChatPollDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Chinese recap headers and long content remain scrollable',
      (tester) async {
    smallScreen(tester);
    await tester.pumpWidget(app(
        Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => showSnackChatUnreadSummarySheet(context,
                        items: const [
                          SnackChatUnreadSummaryItem(
                              label: '需要确认的聚会安排',
                              content: '请在今天确认是否参加周末聚会，具体时间和地点将在群聊中通知。',
                              status: SnackChatSummaryStatus.changed,
                              sourceSequences: [1])
                        ],
                        messageCount: 24,
                        rangeType: SnackChatSummaryRangeType.today),
                    child: const Text('open')))),
        scale: 2));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('今日总结'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('snapshot strings use Chinese counts without English plurals',
      (tester) async {
    late SnapshotStrings strings;
    await tester.pumpWidget(app(Builder(builder: (context) {
      strings = SnapshotStrings.of(context);
      return const SizedBox();
    })));
    await tester.pumpAndSettle();
    expect(strings.viewersCount(2), '2人看过此限时动态');
    expect(strings.groupsSelected(2), '已选2个分组');
    expect(strings.publicDescription, '微邻的所有用户可见。');
  });

  test('Chinese legal copy uses the localized brand only', () {
    final copy =
        chineseTerms.expand((section) => [section.$1, section.$2]).join();
    expect(copy, contains('微邻'));
    expect(copy, isNot(contains('Wefilling')));
  });

  testWidgets('all three login language choices fit a narrow phone',
      (tester) async {
    smallScreen(tester);
    for (final locale in [const Locale('ko'), const Locale('en'), chinese]) {
      await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
          value: _UiAuth(), child: app(const LoginScreen(), locale: locale)));
      await tester.pumpAndSettle();
      expect(find.text('KOR'), findsOneWidget);
      expect(find.text('ENG'), findsOneWidget);
      expect(find.text('简体中文'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (locale.languageCode == 'zh') await capture(tester, 'login');
    }
  });

  testWidgets('Chinese meetup card handles long title, place, AppBar and tags',
      (tester) async {
    smallScreen(tester);
    await tester.pumpWidget(app(Scaffold(
        body: BoardMeetupCard(
      meetup: Meetup(
          id: 'local-test',
          title: '周末一起去首尔附近的展览和咖啡馆认识新朋友',
          description: '',
          location: '汉阳大学正门附近的咖啡馆二楼靠窗座位',
          time: '20:30',
          maxParticipants: 12,
          currentParticipants: 4,
          host: 'host',
          hostNickname: '这是一个比较长的用户昵称',
          imageUrl: '',
          date: DateTime(2026, 9, 12),
          visibility: 'public'),
      onTap: () {},
    ))));
    await tester.pumpAndSettle();
    expect(find.text('9月 · 周六'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
        SnackChatDateSeparator.formatDate(DateTime(2026, 9, 12),
            languageCode: 'zh'),
        '2026年9月12日 星期六');
  });

  test('meetup detail localizes its Chinese date and weekday', () async {
    await initializeDateFormatting('en');
    final meetup = Meetup(
      id: 'schedule-localization-test',
      title: '',
      description: '',
      location: '',
      time: '18:00',
      maxParticipants: 8,
      currentParticipants: 0,
      host: 'host',
      hostNickname: 'host',
      imageUrl: '',
      date: DateTime(2026, 10, 4),
      visibility: 'public',
    );
    expect(
      MeetupDetailScreen.formatScheduleForLocale(meetup, 'zh'),
      '10月4日（周日）18:00',
    );
    expect(
      MeetupDetailScreen.formatScheduleForLocale(meetup, 'ko'),
      '10월 4일 (일) 18:00',
    );
    expect(
      MeetupDetailScreen.formatScheduleForLocale(meetup, 'en'),
      'Oct 4 (Sun) 18:00',
    );
    expect(
      MeetupDetailScreen.formatScheduleForLocale(
        Meetup(
          id: 'schedule-no-time-test',
          title: '',
          description: '',
          location: '',
          time: '미정',
          maxParticipants: 8,
          currentParticipants: 0,
          host: 'host',
          hostNickname: 'host',
          imageUrl: '',
          date: DateTime(2026, 10, 4),
          visibility: 'public',
        ),
        'zh',
      ),
      '10月4日（周日）时间待定',
    );
  });

  testWidgets(
      'Chinese attachment actions and multiline snackbar stay inside screen',
      (tester) async {
    smallScreen(tester);
    await tester.pumpWidget(app(
        Builder(
            builder: (context) => Scaffold(
                    body: Column(children: [
                  TextButton(
                      onPressed: () => showSnackChatAttachmentSheet(context),
                      child: const Text('attach')),
                  TextButton(
                      onPressed: () => AppSnackBar.show(context,
                          message: '资料保存失败，请检查网络连接后重试。已保留你填写的内容。'),
                      child: const Text('snackbar')),
                ]))),
        scale: 2));
    await tester.tap(find.text('attach'));
    await tester.pumpAndSettle();
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('图片'), findsOneWidget);
    expect(find.text('投票'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('图片'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('snackbar'));
    await tester.pumpAndSettle();
    expect(find.text('资料保存失败，请检查网络连接后重试。已保留你填写的内容。'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings language picker fits three languages at 320dp',
      (tester) async {
    smallScreen(tester);
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: _UiAuth(), child: app(const AccountSettingsScreen())));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('语言'));
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    expect(find.text('한국어'), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(BottomSheet), matching: find.text('English')),
        findsOneWidget);
    expect(find.text('简体中文'), findsWidgets);
    expect(tester.takeException(), isNull);
    await capture(tester, 'settings');
  });
}
