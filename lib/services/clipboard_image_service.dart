// lib/services/clipboard_image_service.dart
// 클립보드 이미지·텍스트 복사와 붙여넣기(댓글·스낵챗·DM 공용).
//
// Flutter 기본 Clipboard는 텍스트만 다루므로 이미지는 네이티브 채널
// (com.wefilling.app/clipboard_image)로 읽고 쓴다. 붙여넣은 이미지는 임시
// 파일로 저장해 각 화면의 기존 사진 첨부 경로(확인 화면 → 전송)에 넘긴다.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'cache/app_image_cache_manager.dart';

/// 클립보드에서 읽은 이미지.
class ClipboardImage {
  const ClipboardImage({required this.bytes, required this.mimeType});

  final Uint8List bytes;
  final String mimeType;

  bool get isGif => mimeType.toLowerCase() == 'image/gif';

  String get extension => switch (mimeType.toLowerCase()) {
        'image/png' => 'png',
        'image/gif' => 'gif',
        'image/webp' => 'webp',
        _ => 'jpg',
      };
}

class ClipboardImageService with WidgetsBindingObserver {
  ClipboardImageService._();
  static final ClipboardImageService instance = ClipboardImageService._();

  bool _watching = false;

  /// 마지막으로 확인한 "클립보드에 이미지가 있는지". 메뉴는 동기로 그려지므로
  /// 앱으로 돌아올 때·메뉴를 열 때 미리 갱신해 둔다(내용은 읽지 않는다).
  bool cachedHasImage = false;

  void _ensureWatching() {
    if (_watching) return;
    _watching = true;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: discarded_futures
      refreshHasImage();
    }
  }

  Future<bool> refreshHasImage() async {
    _ensureWatching();
    cachedHasImage = await hasImage();
    return cachedHasImage;
  }

  static const MethodChannel _channel =
      MethodChannel('com.wefilling.app/clipboard_image');

  /// 붙여넣기·복사 가능한 최대 크기.
  static const int maxBytes = 20 * 1024 * 1024;

  Future<bool> hasImage() async {
    try {
      return await _channel.invokeMethod<bool>('hasImage') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<ClipboardImage?> readImage() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('readImage');
      if (raw is! Map) return null;
      final bytes = raw['bytes'];
      final mime = (raw['mimeType'] ?? '').toString();
      if (bytes is! Uint8List) return null;
      return validated(bytes, mime);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  /// 형식·크기를 확인한다. 이미지 머리말이 아니면 null.
  @visibleForTesting
  static ClipboardImage? validated(Uint8List bytes, String mimeType) {
    if (bytes.length < 12 || bytes.length > maxBytes) return null;
    final sniffed = sniffImageMime(bytes);
    if (sniffed == null) return null;
    final declared = mimeType.toLowerCase();
    return ClipboardImage(
      bytes: bytes,
      mimeType: declared.startsWith('image/') && declared != 'image/*'
          ? (declared == 'image/jpg' ? 'image/jpeg' : declared)
          : sniffed,
    );
  }

  /// 파일 머리말로 이미지 형식을 판별한다(PNG·JPEG·GIF·WebP·HEIC).
  @visibleForTesting
  static String? sniffImageMime(Uint8List b) {
    if (b.length < 12) return null;
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
      return 'image/png';
    }
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
    if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) return 'image/gif';
    if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
        b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
      return 'image/webp';
    }
    if (b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
      return 'image/heic';
    }
    return null;
  }

  /// 붙여넣은 이미지를 임시 파일로 저장한다(기존 첨부 경로가 파일을 받는다).
  Future<File> saveToTemporaryFile(ClipboardImage image) async {
    final dir = Directory('${(await getTemporaryDirectory()).path}/pasted');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File(
      '${dir.path}/paste_${DateTime.now().microsecondsSinceEpoch}.${image.extension}',
    );
    await file.writeAsBytes(image.bytes, flush: true);
    return file;
  }

  Future<bool> writeImage(Uint8List bytes, {String? mimeType}) async {
    final sniffed = sniffImageMime(bytes);
    if (sniffed == null || bytes.length > maxBytes) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('writeImage', <String, Object>{
            'bytes': bytes,
            'mimeType': mimeType ?? sniffed,
          }) ??
          false;
      if (ok) {
        _ensureWatching();
        cachedHasImage = true;
      }
      return ok;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 네트워크 이미지(앱 이미지 캐시를 거친다)를 클립보드에 복사한다.
  Future<bool> copyImageFromUrl(String url) async {
    final value = url.trim();
    if (value.isEmpty) return false;
    try {
      final file = await AppImageCacheManager.instance
          .getSingleFile(value)
          .timeout(const Duration(seconds: 20));
      return copyImageFile(file);
    } catch (_) {
      return false;
    }
  }

  Future<bool> copyImageFile(File file) async {
    try {
      if (!await file.exists() || await file.length() > maxBytes) return false;
      return writeImage(await file.readAsBytes());
    } catch (_) {
      return false;
    }
  }

  Future<void> copyText(String text) =>
      Clipboard.setData(ClipboardData(text: text));
}

/// 키보드(예: Gboard 클립보드·스티커)가 넣어 주는 이미지 형식.
const List<String> kPastableImageMimeTypes = <String>[
  'image/png',
  'image/jpeg',
  'image/jpg',
  'image/gif',
  'image/webp',
];

const MethodChannel _keyboardContentChannel =
    MethodChannel('com.wefilling.app/keyboard_gif');

/// 키보드가 넣어 준 이미지를 읽는다. 바이트 없이 content:// 주소만 오면(안드로이드)
/// 기존 키보드 GIF 채널로 읽는다(5MB 이하).
Future<ClipboardImage?> readKeyboardInsertedImage(
  KeyboardInsertedContent content,
) async {
  var bytes = content.data;
  if (bytes == null && content.uri.startsWith('content://')) {
    try {
      bytes = await _keyboardContentChannel.invokeMethod<Uint8List>(
        'readGif',
        <String, String>{'uri': content.uri},
      );
    } on PlatformException {
      bytes = null;
    } on MissingPluginException {
      bytes = null;
    }
  }
  if (bytes == null) return null;
  return ClipboardImageService.validated(bytes, content.mimeType);
}

/// 입력창 길게 누르기 메뉴: [붙여넣기]를 누를 때 클립보드에 이미지가 있으면
/// [onImage]로 넘기고, 없으면 원래 텍스트 붙여넣기를 한다. iOS는 이미지만 있을
/// 때 붙여넣기 버튼을 숨기므로 그때 버튼을 직접 보탠다.
Widget pasteImageAwareContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
  ValueChanged<ClipboardImage> onImage,
) {
  Future<void> pasteOrImage(VoidCallback? textPaste) async {
    final image = await ClipboardImageService.instance.readImage();
    if (image == null) {
      if (textPaste != null) {
        textPaste();
      } else {
        await editableTextState.pasteText(SelectionChangedCause.toolbar);
      }
      return;
    }
    ContextMenuController.removeAny();
    editableTextState.hideToolbar();
    onImage(image);
  }

  final service = ClipboardImageService.instance;
  // 다음 메뉴를 위해 미리 갱신한다(이번 메뉴는 마지막으로 확인한 값으로 그린다).
  // ignore: discarded_futures
  service.refreshHasImage();
  final buttons = editableTextState.contextMenuButtonItems.map((item) {
    if (item.type != ContextMenuButtonType.paste) return item;
    return item.copyWith(onPressed: () => pasteOrImage(item.onPressed));
  }).toList();
  // 이미지만 있으면 시스템이 붙여넣기를 숨기므로 그때만 보탠다.
  if (service.cachedHasImage &&
      !buttons.any((item) => item.type == ContextMenuButtonType.paste)) {
    buttons.add(ContextMenuButtonItem(
      type: ContextMenuButtonType.paste,
      onPressed: () => pasteOrImage(null),
    ));
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: buttons,
  );
}
