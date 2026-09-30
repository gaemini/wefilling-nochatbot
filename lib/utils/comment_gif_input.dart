import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/snapshot.dart';

const int maxCommentGifBytes = 5 * 1024 * 1024;
const MethodChannel _keyboardGifChannel =
    MethodChannel('com.wefilling.app/keyboard_gif');

/// Flutter's rich keyboard insertion currently delivers GIF bytes on Android.
/// Reject missing bytes rather than treating the keyboard's URI as a public URL.
Uint8List? validatedKeyboardGif(KeyboardInsertedContent content) {
  final bytes = content.data;
  if (content.mimeType.toLowerCase() != 'image/gif' ||
      bytes == null ||
      bytes.length < 10 ||
      bytes.length > maxCommentGifBytes ||
      !isValidSnapshotCommentGifHeader(bytes)) {
    return null;
  }
  return bytes;
}

Future<Uint8List?> readKeyboardGif(KeyboardInsertedContent content) async {
  if (content.mimeType.toLowerCase() != 'image/gif') return null;
  if (content.data != null) return validatedKeyboardGif(content);
  try {
    final bytes = await _keyboardGifChannel.invokeMethod<Uint8List>(
      'readGif',
      <String, String>{'uri': content.uri},
    );
    if (bytes == null) return null;
    return validatedKeyboardGif(KeyboardInsertedContent(
      mimeType: content.mimeType,
      uri: content.uri,
      data: bytes,
    ));
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

Future<Uint8List?> readPastedGif() async {
  try {
    final bytes = await _keyboardGifChannel.invokeMethod<Uint8List>(
      'readPasteboardGif',
    );
    if (bytes == null) return null;
    return validatedKeyboardGif(KeyboardInsertedContent(
      mimeType: 'image/gif',
      uri: 'pasteboard://gif',
      data: bytes,
    ));
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

Widget commentGifContextMenu(
  BuildContext context,
  EditableTextState editableTextState,
  ValueChanged<Uint8List> onGif,
) {
  final isIos = defaultTargetPlatform == TargetPlatform.iOS;
  final buttons = editableTextState.contextMenuButtonItems.map((item) {
    if (item.type != ContextMenuButtonType.paste || !isIos) return item;
    return item.copyWith(onPressed: () async {
      final bytes = await readPastedGif();
      if (bytes == null) {
        item.onPressed?.call();
        return;
      }
      ContextMenuController.removeAny();
      onGif(bytes);
    });
  }).toList();
  if (isIos &&
      !buttons.any((item) => item.type == ContextMenuButtonType.paste)) {
    // iOS may hide its standard Paste action when the pasteboard contains only
    // an image. Keep the usual localized Paste action available for GIF keyboards.
    buttons.add(ContextMenuButtonItem(
      type: ContextMenuButtonType.paste,
      onPressed: () async {
        final bytes = await readPastedGif();
        if (bytes == null) {
          await editableTextState.pasteText(SelectionChangedCause.toolbar);
          return;
        }
        ContextMenuController.removeAny();
        onGif(bytes);
      },
    ));
  }
  return AdaptiveTextSelectionToolbar.buttonItems(
    anchors: editableTextState.contextMenuAnchors,
    buttonItems: buttons,
  );
}
