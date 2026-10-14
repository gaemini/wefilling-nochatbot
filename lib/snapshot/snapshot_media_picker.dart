// lib/snapshot/snapshot_media_picker.dart
// 스낵 만들기 첫 단계(고르기) v4: 위쪽 가운데 앨범 고르기 하나 + 3열 목록.
// 첫 칸은 카메라이고, 칸을 누르면 바로 편집으로 간다(미리보기·선택 원·다음 없음).
//
// 기기 갤러리(photo_manager)는 [SnapshotGallerySource]로 감싸 테스트에서 바꿀 수
// 있게 했다. 상태는 [SnapshotPickerController]가 들고 있어서 편집에서 `다시
// 고르기`로 돌아와도 보던 앨범과 스크롤 위치가 남는다.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../l10n/ui_locale.dart';
import 'snapshot_strings.dart';

const Color _accentText = Color(0xFF5B9BEA);
const Color _accentButton = Color(0xFF2C6BC0);
const Color _placeholder = Color(0xFF1A1A1A);

enum SnapshotGalleryAccess { full, limited, denied }

enum SnapshotAlbumKind { recents, videos, device }

/// 앨범 하나(시트의 한 줄).
class SnapshotAlbum {
  const SnapshotAlbum({
    required this.id,
    required this.kind,
    required this.deviceName,
    required this.count,
    this.cover,
    this.path,
  });

  final String id;
  final SnapshotAlbumKind kind;

  /// 기기 앨범 이름(최근 항목·영상은 앱 문구로 바꿔 보여 준다).
  final String deviceName;
  final int count;
  final AssetEntity? cover;
  final AssetPathEntity? path;

  String label(SnapshotStrings strings) => switch (kind) {
        SnapshotAlbumKind.recents => strings.albumRecents,
        SnapshotAlbumKind.videos => strings.albumVideos,
        SnapshotAlbumKind.device => deviceName,
      };
}

/// 기기 갤러리 접근. 실제 앱은 [PhotoManagerGallerySource], 테스트는 가짜를 쓴다.
abstract class SnapshotGallerySource {
  Future<SnapshotGalleryAccess> access({required bool request});

  /// 첫 화면에 쓸 `최근 항목`(전체) 앨범. 항목이 없으면 null.
  Future<SnapshotAlbum?> recents();

  /// 시트에 보일 순서: 최근 항목, 영상(0개면 없음), 나머지 기기 앨범(1개 이상).
  Future<List<SnapshotAlbum>> albums();

  Future<List<AssetEntity>> page(SnapshotAlbum album, int page, int size);

  Future<void> presentLimited();

  Future<void> openSettings();

  /// 썸네일. [size]는 요청할 한 변의 픽셀 수.
  ImageProvider thumbnail(AssetEntity asset, int size);
}

class PhotoManagerGallerySource implements SnapshotGallerySource {
  const PhotoManagerGallerySource();

  static const PermissionRequestOption permissionOption =
      PermissionRequestOption(
    androidPermission: AndroidPermission(
      type: RequestType.common,
      mediaLocation: false,
    ),
  );

  static FilterOptionGroup get _filter => FilterOptionGroup(
        orders: const <OrderOption>[
          OrderOption(type: OrderOptionType.createDate, asc: false),
        ],
      );

  /// 이 실행에서 영상 권한을 이미 물어봤는지(거절한 사람에게 반복해 묻지 않는다).
  static bool _askedVideoPermission = false;

  /// photo_manager는 사진 권한만 있어도 "허용됨"으로 보고 영상 권한
  /// (READ_MEDIA_VIDEO)을 따로 묻지 않는다. 그래서 예전에 사진만 허용한
  /// 기기에서는 영상이 목록에 나오지 않는다. Android에서는 영상 권한을 먼저
  /// 한 번 물어 사진·동영상 접근을 함께 받는다.
  Future<void> _ensureVideoPermission() async {
    if (!Platform.isAndroid || _askedVideoPermission) return;
    try {
      final status = await Permission.videos.status;
      if (status.isGranted || status.isPermanentlyDenied) return;
      _askedVideoPermission = true;
      await Permission.videos.request();
    } catch (_) {
      // 권한 플러그인을 쓸 수 없으면 사진만 보여 준다.
    }
  }

  @override
  Future<SnapshotGalleryAccess> access({required bool request}) async {
    if (request) await _ensureVideoPermission();
    final state = request
        ? await PhotoManager.requestPermissionExtend(
            requestOption: permissionOption,
          )
        : await PhotoManager.getPermissionState(
            requestOption: permissionOption,
          );
    if (!state.hasAccess) return SnapshotGalleryAccess.denied;
    return state.isLimited
        ? SnapshotGalleryAccess.limited
        : SnapshotGalleryAccess.full;
  }

  Future<SnapshotAlbum?> _toAlbum(
    AssetPathEntity path,
    SnapshotAlbumKind kind,
  ) async {
    final count = await path.assetCountAsync;
    if (count <= 0) return null;
    final first = await path.getAssetListRange(start: 0, end: 1);
    return SnapshotAlbum(
      id: '${kind.name}:${path.id}',
      kind: kind,
      deviceName: path.name,
      count: count,
      cover: first.isEmpty ? null : first.first,
      path: path,
    );
  }

  @override
  Future<SnapshotAlbum?> recents() async {
    final paths = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      onlyAll: true,
      filterOption: _filter,
    );
    if (paths.isEmpty) return null;
    return _toAlbum(paths.first, SnapshotAlbumKind.recents);
  }

  @override
  Future<List<SnapshotAlbum>> albums() async {
    final all = await PhotoManager.getAssetPathList(
      type: RequestType.common,
      filterOption: _filter,
    );
    final videos = await PhotoManager.getAssetPathList(
      type: RequestType.video,
      onlyAll: true,
      filterOption: _filter,
    );
    final result = <SnapshotAlbum>[];
    for (final path in all.where((p) => p.isAll)) {
      final album = await _toAlbum(path, SnapshotAlbumKind.recents);
      if (album != null) result.add(album);
      break;
    }
    if (videos.isNotEmpty) {
      final album = await _toAlbum(videos.first, SnapshotAlbumKind.videos);
      if (album != null) result.add(album);
    }
    for (final path in all.where((p) => !p.isAll)) {
      final album = await _toAlbum(path, SnapshotAlbumKind.device);
      if (album != null) result.add(album);
    }
    return result;
  }

  @override
  Future<List<AssetEntity>> page(
    SnapshotAlbum album,
    int page,
    int size,
  ) async {
    final path = album.path;
    if (path == null) return const <AssetEntity>[];
    return path.getAssetListPaged(page: page, size: size);
  }

  @override
  Future<void> presentLimited() =>
      PhotoManager.presentLimited(type: RequestType.common);

  @override
  Future<void> openSettings() => PhotoManager.openSetting();

  @override
  ImageProvider thumbnail(AssetEntity asset, int size) =>
      AssetEntityImageProvider(
        asset,
        isOriginal: false,
        thumbnailSize: ThumbnailSize.square(size),
      );
}

enum SnapshotPickerStatus { loading, ready, denied, failed }

/// 고르기 상태(앨범·목록·스크롤). 편집에 다녀와도 유지된다.
class SnapshotPickerController extends ChangeNotifier {
  SnapshotPickerController({required this.source, this.pageSize = 100});

  final SnapshotGallerySource source;
  final int pageSize;

  SnapshotPickerStatus status = SnapshotPickerStatus.loading;
  SnapshotGalleryAccess access = SnapshotGalleryAccess.full;
  SnapshotAlbum? album;
  List<AssetEntity> assets = const <AssetEntity>[];
  bool loadingMore = false;
  int _nextPage = 0;
  int _sequence = 0;
  List<SnapshotAlbum>? _albumCache;
  double savedScrollOffset = 0;
  bool _disposed = false;

  bool get hasMore => album != null && assets.length < album!.count;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 처음 열 때(권한 요청 포함) 또는 [다시 시도]. 보던 앨범이 있으면 그 앨범으로.
  Future<void> load({bool requestPermission = true}) async {
    final sequence = ++_sequence;
    status = SnapshotPickerStatus.loading;
    assets = const <AssetEntity>[];
    _nextPage = 0;
    _notify();
    try {
      final nextAccess = await source.access(request: requestPermission);
      if (sequence != _sequence || _disposed) return;
      access = nextAccess;
      if (nextAccess == SnapshotGalleryAccess.denied) {
        status = SnapshotPickerStatus.denied;
        album = null;
        _notify();
        return;
      }
      final keep = album;
      final target = keep == null || keep.kind == SnapshotAlbumKind.recents
          ? await source.recents()
          : keep;
      if (sequence != _sequence || _disposed) return;
      album = target;
      if (target == null) {
        status = SnapshotPickerStatus.ready;
        _notify();
        return;
      }
      final first = await source.page(target, 0, pageSize);
      if (sequence != _sequence || _disposed) return;
      assets = List<AssetEntity>.unmodifiable(first);
      _nextPage = 1;
      status = SnapshotPickerStatus.ready;
      _notify();
    } catch (_) {
      if (sequence != _sequence || _disposed) return;
      status = SnapshotPickerStatus.failed;
      _notify();
    }
  }

  Future<void> loadMore() async {
    final current = album;
    if (current == null ||
        loadingMore ||
        status != SnapshotPickerStatus.ready ||
        !hasMore) {
      return;
    }
    final sequence = _sequence;
    final requested = _nextPage;
    loadingMore = true;
    _notify();
    try {
      final next = await source.page(current, requested, pageSize);
      if (sequence != _sequence || _disposed || album?.id != current.id) {
        return;
      }
      final known = assets.map((a) => a.id).toSet();
      assets = List<AssetEntity>.unmodifiable(<AssetEntity>[
        ...assets,
        ...next.where((a) => known.add(a.id)),
      ]);
      _nextPage = requested + 1;
    } catch (_) {
      // 다음 스크롤에서 같은 페이지를 다시 시도한다.
    } finally {
      if (!_disposed) {
        loadingMore = false;
        _notify();
      }
    }
  }

  /// 앨범 목록(시트를 처음 열 때 불러와 캐시한다).
  Future<List<SnapshotAlbum>> albums() async {
    final cached = _albumCache;
    if (cached != null) return cached;
    final loaded = await source.albums();
    _albumCache = loaded;
    return loaded;
  }

  Future<void> selectAlbum(SnapshotAlbum next) async {
    album = next;
    savedScrollOffset = 0;
    await load(requestPermission: false);
  }

  Future<void> selectMore() async {
    try {
      await source.presentLimited();
    } catch (_) {
      return;
    }
    _albumCache = null;
    await load(requestPermission: false);
  }

  /// 앱 복귀: 앨범 목록 캐시를 비우고, 권한 상태가 바뀌었거나 실패·거부
  /// 상태였을 때만 다시 불러온다(보던 목록·스크롤은 그대로 둔다).
  Future<void> onResumed() async {
    _albumCache = null;
    SnapshotGalleryAccess next;
    try {
      next = await source.access(request: false);
    } catch (_) {
      return;
    }
    if (_disposed) return;
    if (next != access ||
        status == SnapshotPickerStatus.failed ||
        status == SnapshotPickerStatus.denied) {
      await load(requestPermission: false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// 고르기 화면 본문.
class SnapshotMediaPicker extends StatefulWidget {
  const SnapshotMediaPicker({
    super.key,
    required this.controller,
    required this.onClose,
    required this.onCamera,
    required this.onAssetTap,
    required this.onPickFromSystem,
    this.loadingAssetId,
    this.busy = false,
  });

  final SnapshotPickerController controller;
  final VoidCallback? onClose;
  final VoidCallback? onCamera;
  final ValueChanged<AssetEntity> onAssetTap;

  /// 권한 없이 쓰는 시스템 선택기(권한 거부 화면의 [앨범에서 고르기]).
  final VoidCallback? onPickFromSystem;

  /// 불러오는 중인 칸.
  final String? loadingAssetId;

  /// true면 칸·카메라 탭을 막는다(파일을 불러오는 중).
  final bool busy;

  @override
  State<SnapshotMediaPicker> createState() => _SnapshotMediaPickerState();
}

class _SnapshotMediaPickerState extends State<SnapshotMediaPicker> {
  late ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController(
      initialScrollOffset: widget.controller.savedScrollOffset,
    )..addListener(_rememberOffset);
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant SnapshotMediaPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  /// 편집에 다녀와도 같은 위치로 돌아오도록 스크롤 위치를 계속 기억한다.
  void _rememberOffset() {
    if (_scroll.hasClients) {
      widget.controller.savedScrollOffset = _scroll.offset;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _scroll.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  TextStyle _style(double size, FontWeight weight, Color color) => TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.2,
        color: color,
      );

  Future<void> _openAlbumSheet() async {
    final controller = widget.controller;
    final strings = SnapshotStrings.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final selected = await showModalBottomSheet<SnapshotAlbum>(
      context: context,
      useSafeArea: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .55),
      sheetAnimationStyle: AnimationStyle(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 240),
        curve: const Cubic(.2, .8, .2, 1),
        reverseDuration:
            reduce ? Duration.zero : const Duration(milliseconds: 200),
      ),
      builder: (sheetContext) => _AlbumSheet(
        albums: controller.albums(),
        currentId: controller.album?.id,
        currentKind: controller.album?.kind,
        strings: strings,
        source: controller.source,
      ),
    );
    if (!mounted || selected == null) return;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await controller.selectAlbum(selected);
  }

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final controller = widget.controller;
    final albumName = controller.album?.label(strings) ?? strings.albumRecents;
    final topPadding = MediaQuery.paddingOf(context).top;

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ColoredBox(
        color: Colors.black,
        child: Column(
          children: [
            SizedBox(height: topPadding),
            SizedBox(
              // 폭을 화면 전체로 둬야 닫기 버튼이 왼쪽 끝에 붙는다.
              width: double.infinity,
              height: 50,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: 6,
                    top: 3,
                    child: Semantics(
                      button: true,
                      label: MaterialLocalizations.of(context)
                          .closeButtonTooltip,
                      excludeSemantics: true,
                      child: GestureDetector(
                        key: const ValueKey('snapshot_picker_close'),
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onClose,
                        child: const SizedBox.square(
                          dimension: 44,
                          child: Icon(
                            CupertinoIcons.xmark,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: _AlbumButton(
                      label: albumName,
                      semanticLabel: strings.albumPickerA11y(albumName),
                      style: _style(16, FontWeight.w600, Colors.white),
                      onTap: controller.status == SnapshotPickerStatus.ready ||
                              controller.status ==
                                  SnapshotPickerStatus.loading
                          ? _openAlbumSheet
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildBody(strings)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(SnapshotStrings strings) {
    final controller = widget.controller;
    switch (controller.status) {
      case SnapshotPickerStatus.denied:
        return _buildNotice(
          strings: strings,
          title: strings.pickerPermissionTitle,
          body: strings.pickerPermissionBody,
          primary: strings.pickerOpenSettings,
          onPrimary: () => unawaited(controller.source.openSettings()),
          secondary: strings.pickerFromAlbum,
          onSecondary: widget.onPickFromSystem,
        );
      case SnapshotPickerStatus.failed:
        return _buildNotice(
          strings: strings,
          title: strings.pickerLoadFailed,
          primary: strings.retry,
          onPrimary: () => unawaited(controller.load()),
        );
      case SnapshotPickerStatus.loading:
      case SnapshotPickerStatus.ready:
        return _buildGrid(strings);
    }
  }

  Widget _cameraCell(SnapshotStrings strings) {
    return Semantics(
      button: true,
      label: strings.camera,
      excludeSemantics: true,
      child: _PressFade(
        key: const ValueKey('snapshot_picker_camera'),
        onTap: widget.busy ? null : widget.onCamera,
        child: ColoredBox(
          color: const Color(0xFF161616),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  CupertinoIcons.camera,
                  size: 26,
                  color: Colors.white,
                ),
                const SizedBox(height: 6),
                Text(
                  strings.camera,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _style(12, FontWeight.w500, Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(SnapshotStrings strings) {
    final controller = widget.controller;
    final loading = controller.status == SnapshotPickerStatus.loading;
    final width = MediaQuery.sizeOf(context).width;
    final cellPixels = ((width / 3) * MediaQuery.devicePixelRatioOf(context))
        .round()
        .clamp(60, 300);
    final bottom = MediaQuery.viewPaddingOf(context).bottom + 40;
    final limited = controller.access == SnapshotGalleryAccess.limited &&
        !loading;
    final assets = controller.assets;
    final empty = !loading && assets.isEmpty;
    final cellCount = loading ? 12 : 1 + assets.length;

    final grid = SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1.5,
        crossAxisSpacing: 1.5,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) return _cameraCell(strings);
          if (loading) {
            return const ColoredBox(color: _placeholder);
          }
          final asset = assets[index - 1];
          return _AssetCell(
            key: ValueKey<String>('snapshot_picker_cell_${asset.id}'),
            asset: asset,
            image: controller.source.thumbnail(asset, cellPixels),
            loading: widget.loadingAssetId == asset.id,
            enabled: !widget.busy,
            durationStyle: _style(11, FontWeight.w600, Colors.white).copyWith(
              shadows: const [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 3,
                  color: Color(0xAB000000),
                ),
              ],
            ),
            strings: strings,
            onTap: () => widget.onAssetTap(asset),
          );
        },
        childCount: cellCount,
      ),
    );

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.extentAfter < 600) {
          unawaited(controller.loadMore());
        }
        return false;
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: CustomScrollView(
          key: const ValueKey('snapshot_picker_grid'),
          controller: _scroll,
          slivers: [
            if (limited)
              SliverToBoxAdapter(child: _limitedBanner(strings)),
            grid,
            if (empty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 40, left: 32, right: 32),
                  child: Text(
                    strings.pickerEmpty,
                    key: const ValueKey('snapshot_picker_empty'),
                    textAlign: TextAlign.center,
                    style: _style(
                      13,
                      FontWeight.w400,
                      Colors.white.withValues(alpha: .6),
                    ),
                  ),
                ),
              ),
            SliverToBoxAdapter(child: SizedBox(height: bottom)),
          ],
        ),
      ),
    );
  }

  Widget _limitedBanner(SnapshotStrings strings) {
    return Container(
      key: const ValueKey('snapshot_picker_limited'),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: .1),
            width: .5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              strings.pickerLimitedNote,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: _style(
                13,
                FontWeight.w400,
                Colors.white.withValues(alpha: .7),
              ),
            ),
          ),
          GestureDetector(
            key: const ValueKey('snapshot_picker_select_more'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(widget.controller.selectMore()),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
              child: Center(
                widthFactor: 1,
                child: Text(
                  strings.pickerSelectMore,
                  style: _style(13, FontWeight.w600, _accentText),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotice({
    required SnapshotStrings strings,
    required String title,
    String? body,
    required String primary,
    required VoidCallback onPrimary,
    String? secondary,
    VoidCallback? onSecondary,
  }) {
    final width = MediaQuery.sizeOf(context).width;
    final cell = (width - 3) / 3;
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewPaddingOf(context).bottom + 40,
      ),
      child: Column(
        children: [
          // 위쪽 카메라 칸 하나는 그대로 보여 준다(3열 첫 칸).
          Align(
            alignment: Alignment.centerLeft,
            child: SizedBox.square(dimension: cell, child: _cameraCell(strings)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
            child: Column(
              children: [
                Text(
                  title,
                  key: const ValueKey('snapshot_picker_notice_title'),
                  textAlign: TextAlign.center,
                  style: _style(15, FontWeight.w600, Colors.white),
                ),
                if (body != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: _style(
                      13,
                      FontWeight.w400,
                      Colors.white.withValues(alpha: .6),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _NoticeButton(
                      key: const ValueKey('snapshot_picker_notice_primary'),
                      label: primary,
                      filled: true,
                      style: _style(14, FontWeight.w600, Colors.white),
                      onTap: onPrimary,
                    ),
                    if (secondary != null && onSecondary != null)
                      _NoticeButton(
                        key: const ValueKey('snapshot_picker_notice_secondary'),
                        label: secondary,
                        filled: false,
                        style: _style(14, FontWeight.w500, Colors.white),
                        onTap: onSecondary,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlbumButton extends StatefulWidget {
  const _AlbumButton({
    required this.label,
    required this.semanticLabel,
    required this.style,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  State<_AlbumButton> createState() => _AlbumButtonState();
}

class _AlbumButtonState extends State<_AlbumButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('snapshot_picker_album_button'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _pressed
                    ? Colors.white.withValues(alpha: .08)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.label,
                      key: const ValueKey('snapshot_picker_album_name'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: widget.style,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    CupertinoIcons.chevron_down,
                    size: 14,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 누르는 동안 불투명도 0.6(120ms).
class _PressFade extends StatefulWidget {
  const _PressFade({super.key, required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_PressFade> createState() => _PressFadeState();
}

class _PressFadeState extends State<_PressFade> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTap: widget.onTap,
      child: AnimatedOpacity(
        opacity: _pressed ? .6 : 1,
        duration: reduce ? Duration.zero : const Duration(milliseconds: 120),
        child: widget.child,
      ),
    );
  }
}

String formatSnapshotVideoDuration(Duration duration) {
  final total = duration.inSeconds;
  final minutes = total ~/ 60;
  final seconds = total % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

class _AssetCell extends StatelessWidget {
  const _AssetCell({
    super.key,
    required this.asset,
    required this.image,
    required this.loading,
    required this.enabled,
    required this.durationStyle,
    required this.strings,
    required this.onTap,
  });

  final AssetEntity asset;
  final ImageProvider image;
  final bool loading;
  final bool enabled;
  final TextStyle durationStyle;
  final SnapshotStrings strings;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isVideo = asset.type == AssetType.video;
    final date = MaterialLocalizations.of(context)
        .formatShortDate(asset.createDateTime);
    final label = isVideo
        ? strings.pickerVideoA11y(asset.videoDuration.inSeconds, date)
        : strings.pickerPhotoA11y(date);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: _PressFade(
        onTap: enabled ? onTap : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: _placeholder,
              child: Image(
                image: image,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            if (isVideo)
              Positioned(
                right: 6,
                bottom: 5,
                child: Text(
                  formatSnapshotVideoDuration(asset.videoDuration),
                  key: ValueKey<String>('snapshot_picker_duration_${asset.id}'),
                  style: durationStyle,
                ),
              ),
            if (loading)
              const ColoredBox(
                key: ValueKey('snapshot_picker_cell_loading'),
                color: Color(0x66000000),
                child: Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoticeButton extends StatelessWidget {
  const _NoticeButton({
    super.key,
    required this.label,
    required this.filled,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: filled ? _accentButton : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: filled
                ? null
                : Border.all(color: Colors.white.withValues(alpha: .3)),
          ),
          child: Center(
            widthFactor: 1,
            child: Text(label, maxLines: 1, style: style),
          ),
        ),
      ),
    );
  }
}

class _AlbumSheet extends StatelessWidget {
  const _AlbumSheet({
    required this.albums,
    required this.currentId,
    required this.currentKind,
    required this.strings,
    required this.source,
  });

  final Future<List<SnapshotAlbum>> albums;
  final String? currentId;
  final SnapshotAlbumKind? currentKind;
  final SnapshotStrings strings;
  final SnapshotGallerySource source;

  TextStyle _style(
    BuildContext context,
    double size,
    FontWeight weight,
    Color color,
  ) =>
      TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR', 'NotoSansSC'],
        fontSize: size,
        fontWeight: weight,
        letterSpacing: -0.2,
        color: color,
      );

  bool _isCurrent(SnapshotAlbum album) =>
      album.id == currentId ||
      (currentId == null && album.kind == SnapshotAlbumKind.recents) ||
      (album.kind == SnapshotAlbumKind.recents &&
          currentKind == SnapshotAlbumKind.recents);

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumbPixels = (44 * dpr).round().clamp(44, 88);
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * .7),
        child: DecoratedBox(
          key: const ValueKey('snapshot_album_sheet'),
          decoration: const BoxDecoration(
            color: Color(0xFF141414),
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Padding(
            padding: EdgeInsets.only(top: 8, bottom: media.viewPadding.bottom + 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: FutureBuilder<List<SnapshotAlbum>>(
                    future: albums,
                    builder: (context, snapshot) {
                      final list = snapshot.data;
                      if (list == null) {
                        return const SizedBox(
                          height: 120,
                          child: Center(
                            child: SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final album = list[index];
                          final current = _isCurrent(album);
                          final cover = album.cover;
                          return InkWell(
                            key: ValueKey<String>('snapshot_album_${album.id}'),
                            onTap: () => Navigator.of(context).pop(album),
                            child: SizedBox(
                              height: 60,
                              child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 20),
                                child: Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox.square(
                                        dimension: 44,
                                        child: ColoredBox(
                                          color: const Color(0xFF2A2A2A),
                                          child: cover == null
                                              ? null
                                              : Image(
                                                  image: source.thumbnail(
                                                    cover,
                                                    thumbPixels,
                                                  ),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) =>
                                                      const SizedBox.shrink(),
                                                ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        album.label(strings),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _style(
                                          context,
                                          15,
                                          current
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          current
                                              ? _accentText
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      '${album.count}',
                                      style: _style(
                                        context,
                                        12,
                                        FontWeight.w400,
                                        Colors.white.withValues(alpha: .45),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 테스트용: 메모리 썸네일(1×1 투명 PNG).
@visibleForTesting
final Uint8List snapshotPickerTransparentPng = Uint8List.fromList(const <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);
