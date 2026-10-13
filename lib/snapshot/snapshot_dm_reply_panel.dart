// lib/snapshot/snapshot_dm_reply_panel.dart
// 친구 스낵의 DM 답장 입력부. 사진 위에 떠 있는 상자가 아니라 화면 하단에
// 붙는 패널이며, 키보드 높이만큼 위로 올라온다. 전송은 콜백으로 위임한다.

import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/ui_locale.dart';
import 'snapshot_strings.dart';

const Color _panelBackground = Color(0xFF121212);
const Color _fieldBackground = Color(0xFF262626);
const Color _accent = Color(0xFF2C6BC0);

class SnapshotDmReplyPanel extends StatefulWidget {
  const SnapshotDmReplyPanel({
    super.key,
    required this.authorName,
    required this.thumbnail,
    required this.initialText,
    required this.onClose,
    required this.onSend,
  });

  final String authorName;

  /// 스낵 썸네일(30×40). 없으면 회색 자리 표시.
  final Widget? thumbnail;
  final String initialText;

  /// 닫을 때 입력 중이던 글을 넘긴다(임시 보관용).
  final ValueChanged<String> onClose;

  /// true면 성공(패널은 호출한 쪽이 닫는다). false면 글을 그대로 둔다.
  final Future<bool> Function(String text) onSend;

  @override
  State<SnapshotDmReplyPanel> createState() => _SnapshotDmReplyPanelState();
}

class _SnapshotDmReplyPanelState extends State<SnapshotDmReplyPanel> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  final FocusNode _focus = FocusNode(debugLabel: 'snapshot-dm-reply-panel');
  bool _sending = false;

  bool get _hasText => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (_sending || text.isEmpty) return;
    setState(() => _sending = true);
    var success = false;
    try {
      success = await widget.onSend(text);
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    // 실패하면 입력을 유지하고 글을 보존한다.
    setState(() => _sending = false);
    if (!success) _focus.requestFocus();
  }

  TextStyle _style(double size, double line, FontWeight weight, Color color) =>
      TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: size,
        height: line / size,
        fontWeight: weight,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final strings = SnapshotStrings.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final name = widget.authorName.trim().isEmpty
        ? strings.snapshot
        : widget.authorName.trim();
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final safeBottom = keyboard > 0 ? 0.0 : MediaQuery.paddingOf(context).bottom;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.25,
      child: Material(
        color: _panelBackground,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: Colors.white.withValues(alpha: .08)),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(bottom: safeBottom),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 0, 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 30,
                          height: 40,
                          child: widget.thumbnail ??
                              const ColoredBox(color: Color(0xFF2C2C2E)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              strings.replyContextTitle(name),
                              key: const ValueKey('dm_reply_context_title'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style(
                                  13, 18, FontWeight.w600, Colors.white),
                            ),
                            Text(
                              strings.replyContextSub,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style(
                                12,
                                17,
                                FontWeight.w400,
                                Colors.white.withValues(alpha: .55),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Semantics(
                        button: true,
                        label: strings.closeButtonLabel,
                        excludeSemantics: true,
                        child: GestureDetector(
                          key: const ValueKey('dm_reply_close'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onClose(_controller.text),
                          child: SizedBox.square(
                            dimension: 44,
                            child: Center(
                              child: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: Colors.white.withValues(alpha: .7),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _fieldBackground,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Semantics(
                            label: strings.replyByDm(name),
                            textField: true,
                            child: TextField(
                              key: const ValueKey('dm_reply_input'),
                              controller: _controller,
                              focusNode: _focus,
                              enabled: !_sending,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.newline,
                              cursorColor: _accent,
                              // 글자 크기는 15로 고정한다.
                              style: _style(15, 20, FontWeight.w400,
                                  Colors.white),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: strings.replyInputHint,
                                hintStyle: _style(
                                  15,
                                  20,
                                  FontWeight.w400,
                                  Colors.white.withValues(alpha: .4),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 36,
                        height: 40,
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: AnimatedScale(
                            scale: _hasText ? 1 : 0,
                            duration: reduce
                                ? Duration.zero
                                : const Duration(milliseconds: 150),
                            curve: Curves.easeOutBack,
                            child: Semantics(
                              button: true,
                              enabled: _hasText && !_sending,
                              label: strings.sendButtonLabel,
                              excludeSemantics: true,
                              child: GestureDetector(
                                key: const ValueKey('dm_reply_send'),
                                behavior: HitTestBehavior.opaque,
                                onTap: _hasText && !_sending
                                    ? () => unawaited(_send())
                                    : null,
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  margin: const EdgeInsets.only(bottom: 2),
                                  decoration: const BoxDecoration(
                                    color: _accent,
                                    shape: BoxShape.circle,
                                  ),
                                  child: _sending
                                      ? const Padding(
                                          padding: EdgeInsets.all(10),
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.arrow_upward_rounded,
                                          size: 18,
                                          color: Colors.white,
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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
