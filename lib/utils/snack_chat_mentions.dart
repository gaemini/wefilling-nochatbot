import 'package:flutter/material.dart';

class SnackChatMention {
  const SnackChatMention(
      {required this.userId,
      required this.displayName,
      required this.start,
      required this.end});
  final String userId, displayName;
  final int start, end;
  Map<String, dynamic> toMap() => {
        'userId': userId,
        'displayName': displayName,
        'start': start,
        'end': end
      };
  SnackChatMention shifted(int delta) => SnackChatMention(
      userId: userId,
      displayName: displayName,
      start: start + delta,
      end: end + delta);
  static List<SnackChatMention> parse(Object? raw, String text) {
    if (raw is! List || raw.length > 10) return [];
    final items = <SnackChatMention>[];
    for (final entry in raw.whereType<Map>()) {
      final uid = entry['userId'],
          name = entry['displayName'],
          start = entry['start'],
          end = entry['end'];
      if (uid is! String ||
          uid.isEmpty ||
          name is! String ||
          start is! int ||
          end is! int ||
          start < 0 ||
          end <= start ||
          end > text.length ||
          text.substring(start, end) != '@$name' ||
          items.any((item) => start < item.end && end > item.start)) continue;
      items.add(SnackChatMention(
          userId: uid, displayName: name, start: start, end: end));
    }
    return items;
  }
}

/// Never rewrites IME input. Identity is retained only for untouched spans.
/// Pasted/undone plain @names are not promoted back to explicit mentions.
class SnackChatMentionController extends TextEditingController {
  final List<SnackChatMention> _mentions = [];
  List<SnackChatMention> get mentions => List.unmodifiable(_mentions);
  @override
  set value(TextEditingValue next) {
    final previous = value.text;
    if (previous != next.text) {
      var prefix = 0, suffix = 0;
      while (prefix < previous.length &&
          prefix < next.text.length &&
          previous.codeUnitAt(prefix) == next.text.codeUnitAt(prefix)) prefix++;
      while (suffix < previous.length - prefix &&
          suffix < next.text.length - prefix &&
          previous.codeUnitAt(previous.length - suffix - 1) ==
              next.text.codeUnitAt(next.text.length - suffix - 1)) suffix++;
      final oldEnd = previous.length - suffix;
      final delta = next.text.length - previous.length;
      final updated = <SnackChatMention>[];
      for (final mention in _mentions) {
        if (oldEnd <= mention.start) {
          updated.add(mention.shifted(delta));
        } else if (prefix >= mention.end) {
          updated.add(mention);
        }
        // An edit touching the span downgrades it to plain text, never a new ID.
      }
      _mentions
        ..clear()
        ..addAll(SnackChatMention.parse(
            updated.map((e) => e.toMap()).toList(), next.text));
    }
    super.value = next;
  }

  TextRange? get activeQuery {
    if (!selection.isCollapsed ||
        !selection.isValid ||
        selection.extentOffset > text.length) return null;
    final before = text.substring(0, selection.extentOffset);
    final match = RegExp(r'(^|\s)@([^\s@]{0,40})$').firstMatch(before);
    if (match == null) return null;
    // Some Android keyboards mark the literal @ as composing too. It must
    // still open the picker. Leave Korean/Chinese name composition untouched.
    if (value.composing.isValid &&
        !value.composing.isCollapsed &&
        match.group(2)!.isNotEmpty) return null;
    final start = match.start + match.group(1)!.length;
    if (_mentions.any((item) => start >= item.start && start < item.end))
      return null;
    return TextRange(start: start, end: selection.extentOffset);
  }

  bool insertMention(String uid, String name) {
    final range = activeQuery;
    if (range == null || _mentions.length >= 10 || uid.isEmpty || name.isEmpty)
      return false;
    final replacement = '@$name ';
    value = TextEditingValue(
        text: text.replaceRange(range.start, range.end, replacement),
        selection:
            TextSelection.collapsed(offset: range.start + replacement.length));
    _mentions.add(SnackChatMention(
        userId: uid,
        displayName: name,
        start: range.start,
        end: range.start + replacement.length - 1));
    notifyListeners();
    return true;
  }

  List<SnackChatMention> get trimmedMentions {
    final leading = text.length - text.trimLeft().length;
    return SnackChatMention.parse(
        _mentions.map((e) => e.shifted(-leading).toMap()).toList(),
        text.trim());
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final points = <int>{
      0,
      text.length,
      for (final m in _mentions) ...[m.start, m.end],
      if (composing.isValid) ...[composing.start, composing.end]
    }.toList()
      ..sort();
    return TextSpan(style: style, children: [
      for (var i = 0; i < points.length - 1; i++)
        TextSpan(
            text: text.substring(points[i], points[i + 1]),
            style: (style ?? const TextStyle()).copyWith(
              color: _mentions
                      .any((m) => points[i] >= m.start && points[i] < m.end)
                  ? const Color(0xFF087BB5)
                  : style?.color,
              fontWeight: _mentions
                      .any((m) => points[i] >= m.start && points[i] < m.end)
                  ? FontWeight.w600
                  : style?.fontWeight,
              decoration: composing.isValid &&
                      points[i] >= composing.start &&
                      points[i] < composing.end
                  ? TextDecoration.underline
                  : style?.decoration,
            )),
    ]);
  }
}
