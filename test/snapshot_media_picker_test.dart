import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wefilling/snapshot/snapshot_media_picker.dart';

AssetEntity _photo(String id) => AssetEntity(
      id: id,
      typeInt: 1,
      width: 100,
      height: 100,
      createDateSecond: 1789372800,
    );

AssetEntity _video(String id, int seconds) => AssetEntity(
      id: id,
      typeInt: 2,
      width: 100,
      height: 100,
      duration: seconds,
      createDateSecond: 1789372800,
    );

class _FakeSource implements SnapshotGallerySource {
  _FakeSource({
    this.accessResult = SnapshotGalleryAccess.full,
    List<AssetEntity>? all,
    List<AssetEntity>? videos,
    this.fail = false,
  })  : all = all ?? [_photo('p1'), _video('v1', 34), _photo('p2')],
        videos = videos ?? [_video('v1', 34)];

  SnapshotGalleryAccess accessResult;
  final List<AssetEntity> all;
  final List<AssetEntity> videos;
  bool fail;
  int settingsOpened = 0;
  int limitedPresented = 0;

  SnapshotAlbum get _recents => SnapshotAlbum(
        id: 'recents',
        kind: SnapshotAlbumKind.recents,
        deviceName: 'All',
        count: all.length,
        cover: all.isEmpty ? null : all.first,
      );

  @override
  Future<SnapshotGalleryAccess> access({required bool request}) async =>
      accessResult;

  @override
  Future<SnapshotAlbum?> recents() async {
    if (fail) throw StateError('fail');
    return _recents;
  }

  @override
  Future<List<SnapshotAlbum>> albums() async => [
        _recents,
        if (videos.isNotEmpty)
          SnapshotAlbum(
            id: 'videos',
            kind: SnapshotAlbumKind.videos,
            deviceName: 'Videos',
            count: videos.length,
            cover: videos.first,
          ),
        const SnapshotAlbum(
          id: 'shots',
          kind: SnapshotAlbumKind.device,
          deviceName: 'Screenshots',
          count: 1,
        ),
      ];

  @override
  Future<List<AssetEntity>> page(SnapshotAlbum album, int page, int size) async {
    if (page > 0) return const [];
    return switch (album.kind) {
      SnapshotAlbumKind.recents => all,
      SnapshotAlbumKind.videos => videos,
      SnapshotAlbumKind.device => [_photo('s1')],
    };
  }

  @override
  Future<void> presentLimited() async => limitedPresented++;

  @override
  Future<void> openSettings() async => settingsOpened++;

  @override
  ImageProvider thumbnail(AssetEntity asset, int size) =>
      MemoryImage(snapshotPickerTransparentPng);
}

Widget _host(
  SnapshotPickerController controller, {
  VoidCallback? onCamera,
  ValueChanged<AssetEntity>? onAsset,
  VoidCallback? onSystem,
  String? loadingId,
  bool busy = false,
  Locale locale = const Locale('ko'),
  double scale = 1,
}) {
  return MaterialApp(
    locale: locale,
    supportedLocales: const [Locale('ko'), Locale('en'), Locale('zh')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Scaffold(
      body: SnapshotMediaPicker(
        controller: controller,
        onClose: () {},
        onCamera: onCamera ?? () {},
        onAssetTap: onAsset ?? (_) {},
        onPickFromSystem: onSystem ?? () {},
        loadingAssetId: loadingId,
        busy: busy,
      ),
    ),
  );
}

Future<SnapshotPickerController> _ready(
  WidgetTester tester,
  _FakeSource source,
) async {
  final controller = SnapshotPickerController(source: source);
  addTearDown(controller.dispose);
  await controller.load();
  return controller;
}

void main() {
  testWidgets('겹치는 요소 없음: 다음·탭·12초 안내·24시간 안내·선택 원', (tester) async {
    final controller = await _ready(tester, _FakeSource());
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    for (final text in ['다음', '사진', '영상은 12초까지', '24시간 뒤 사라져요']) {
      expect(find.text(text), findsNothing, reason: text);
    }
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    expect(find.text('최근 항목'), findsOneWidget);
  });

  testWidgets('첫 칸은 카메라, 사진·영상 칸 탭은 바로 콜백', (tester) async {
    var camera = 0;
    final tapped = <String>[];
    final controller = await _ready(tester, _FakeSource());
    await tester.pumpWidget(_host(
      controller,
      onCamera: () => camera++,
      onAsset: (a) => tapped.add(a.id),
    ));
    await tester.pump();
    final cameraTopLeft =
        tester.getTopLeft(find.byKey(const ValueKey('snapshot_picker_camera')));
    final firstAsset = tester
        .getTopLeft(find.byKey(const ValueKey('snapshot_picker_cell_p1')));
    expect(cameraTopLeft.dx, lessThan(firstAsset.dx));
    await tester.tap(find.byKey(const ValueKey('snapshot_picker_camera')));
    await tester.tap(find.byKey(const ValueKey('snapshot_picker_cell_p1')));
    await tester.tap(find.byKey(const ValueKey('snapshot_picker_cell_v1')));
    expect(camera, 1);
    expect(tapped, ['p1', 'v1']);
    // 영상 길이 배지 m:ss
    expect(find.text('0:34'), findsOneWidget);
  });

  testWidgets('불러오는 중에는 다른 칸 탭이 무시되고 로딩 표시', (tester) async {
    final tapped = <String>[];
    final controller = await _ready(tester, _FakeSource());
    await tester.pumpWidget(_host(
      controller,
      busy: true,
      loadingId: 'p1',
      onAsset: (a) => tapped.add(a.id),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('snapshot_picker_cell_loading')),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('snapshot_picker_cell_p2')));
    expect(tapped, isEmpty);
  });

  testWidgets('앨범 시트: 배경 탭 닫기, 영상 앨범으로 바꾸면 이름·목록 갱신',
      (tester) async {
    final controller = await _ready(tester, _FakeSource());
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('snapshot_picker_album_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snapshot_album_sheet')), findsOneWidget);
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snapshot_album_sheet')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('snapshot_picker_album_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('snapshot_album_videos')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('snapshot_picker_album_name')))
          .data,
      '영상',
    );
    expect(find.byKey(const ValueKey('snapshot_picker_cell_p1')), findsNothing);
    expect(find.byKey(const ValueKey('snapshot_picker_cell_v1')), findsOneWidget);
  });

  testWidgets('영상이 0개면 시트에 영상 줄이 없다', (tester) async {
    final controller =
        await _ready(tester, _FakeSource(all: [_photo('p1')], videos: []));
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('snapshot_picker_album_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snapshot_album_videos')), findsNothing);
    expect(find.byKey(const ValueKey('snapshot_album_recents')), findsOneWidget);
  });

  testWidgets('다시 열면 보던 앨범과 스크롤 위치가 남는다', (tester) async {
    final many = [for (var i = 0; i < 60; i++) _photo('p$i')];
    final controller = await _ready(tester, _FakeSource(all: many));
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('snapshot_picker_grid')),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    // 편집으로 갔다가(위젯 제거) 돌아온다.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(controller.savedScrollOffset, greaterThan(0));
    final saved = controller.savedScrollOffset;
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable).first);
    expect(scrollable.position.pixels, saved);
  });

  testWidgets('권한: 제한 줄의 더 고르기, 거부 화면 두 버튼, 실패 다시 시도, 빈 앨범',
      (tester) async {
    final limited = _FakeSource(accessResult: SnapshotGalleryAccess.limited);
    var controller = await _ready(tester, limited);
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    expect(find.text('일부 사진만 볼 수 있어요'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('snapshot_picker_select_more')));
    await tester.pump();
    expect(limited.limitedPresented, 1);

    final denied = _FakeSource(accessResult: SnapshotGalleryAccess.denied);
    var system = 0;
    controller = await _ready(tester, denied);
    await tester.pumpWidget(_host(controller, onSystem: () => system++));
    await tester.pump();
    expect(find.text('사진과 영상을 보려면 접근 권한이 필요해요'), findsOneWidget);
    expect(find.byKey(const ValueKey('snapshot_picker_camera')), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.tap(find.text('앨범에서 고르기'));
    expect(denied.settingsOpened, 1);
    expect(system, 1);

    final failing = _FakeSource(fail: true);
    controller = await _ready(tester, failing);
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    expect(find.text('사진을 불러오지 못했어요'), findsOneWidget);
    failing.fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('snapshot_picker_cell_p1')), findsOneWidget);

    controller = await _ready(tester, _FakeSource(all: [], videos: []));
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    expect(find.text('사진이나 영상이 없어요'), findsOneWidget);
    expect(find.byKey(const ValueKey('snapshot_picker_camera')), findsOneWidget);
  });

  testWidgets('글자 크기 16 이하', (tester) async {
    final controller = await _ready(tester, _FakeSource());
    await tester.pumpWidget(_host(controller));
    await tester.pump();
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      expect(text.style?.fontSize ?? 14, lessThanOrEqualTo(16));
    }
  });

  for (final locale in const ['ko', 'en', 'zh']) {
    for (final width in const [320.0, 375.0, 430.0]) {
      for (final scale in const [1.0, 1.3, 2.0]) {
        testWidgets('오버플로우 없음 $locale ${width.toInt()} x$scale',
            (tester) async {
          await tester.binding.setSurfaceSize(Size(width, 760));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final denied =
              _FakeSource(accessResult: SnapshotGalleryAccess.limited);
          final controller = await _ready(tester, denied);
          await tester.pumpWidget(
            _host(controller, locale: Locale(locale), scale: scale),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          final refused = await _ready(
            tester,
            _FakeSource(accessResult: SnapshotGalleryAccess.denied),
          );
          await tester.pumpWidget(
            _host(refused, locale: Locale(locale), scale: scale),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
