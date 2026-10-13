// lib/ui/widgets/together_proposal_banner.dart
// 같이하기 제안 표시(스낵챗 대화 맨 위). 보낸 사람/받는 사람 모드와 상태
// (pending / accepted / later)에 따라 모양이 바뀐다.

import 'package:flutter/material.dart';

import '../../l10n/together_strings.dart';
import '../../l10n/ui_locale.dart';
import '../../models/snack_chat.dart';

class TogetherProposalBanner extends StatelessWidget {
  const TogetherProposalBanner({
    super.key,
    required this.together,
    required this.isRecipient,
    required this.otherName,
    required this.myAvatar,
    required this.otherAvatar,
    this.busy = false,
    this.onAccept,
    this.onLater,
  });

  final SnackChatTogether together;

  /// true면 받는 사람 화면(버튼 노출), false면 보낸 사람 화면.
  final bool isRecipient;

  /// 상대방 이름(보낸 사람 화면에서는 받는 사람, 받는 사람 화면에서는 보낸 사람).
  final String otherName;
  final Widget myAvatar;
  final Widget otherAvatar;
  final bool busy;
  final VoidCallback? onAccept;
  final VoidCallback? onLater;

  TextStyle _style(
    BuildContext context,
    double size,
    FontWeight weight,
    Color color, {
    double? line,
  }) =>
      TextStyle(
        fontFamily: uiFontFamily(context, 'Inter'),
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: size,
        height: line == null ? null : line / size,
        fontWeight: weight,
        color: color,
      );

  @override
  Widget build(BuildContext context) {
    final strings = TogetherStrings.of(context);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final Widget content;
    switch (together.status) {
      case SnackChatTogetherStatus.accepted:
        content = _pill(
          context,
          strings.accepted(together.activity),
          const Color(0xFFEEF4FB),
          const Color(0xFF2C6BC0),
        );
      case SnackChatTogetherStatus.later:
        content = _pill(
          context,
          strings.laterDone,
          const Color(0xFFF2F2F2),
          const Color(0xFF707070),
        );
      case SnackChatTogetherStatus.pending:
        content = _card(context, strings);
    }
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.3,
      child: AnimatedSwitcher(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey<SnackChatTogetherStatus>(together.status),
          child: content,
        ),
      ),
    );
  }

  Widget _pill(BuildContext context, String text, Color bg, Color fg) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          key: const ValueKey('together_pill'),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style(context, 12, FontWeight.w600, fg),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, TogetherStrings strings) {
    final faces = SizedBox(
      width: 40 * 2 - 10,
      height: 40,
      child: Stack(
        children: [
          Positioned(left: 0, child: _face(myAvatar)),
          Positioned(left: 30, child: _face(otherAvatar)),
        ],
      ),
    );
    final subtitle = isRecipient
        ? strings.received(otherName)
        : strings.fromProfile(otherName);
    return Container(
      key: const ValueKey('together_banner'),
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 8),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          faces,
          const SizedBox(height: 10),
          Text(
            together.activity,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _style(context, 17, FontWeight.w700, Colors.black, line: 24),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: _style(context, 12, FontWeight.w400,
                const Color(0xFF5F5F5F),
                line: 17),
          ),
          const SizedBox(height: 10),
          if (isRecipient)
            Row(
              children: [
                SizedBox(
                  width: 84,
                  height: 40,
                  child: OutlinedButton(
                    key: const ValueKey('together_later'),
                    onPressed: busy ? null : onLater,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      backgroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFFE3E3E3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: Text(
                      strings.later,
                      style: _style(context, 14, FontWeight.w600,
                          const Color(0xFF5F5F5F)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: FilledButton(
                      key: const ValueKey('together_accept'),
                      onPressed: busy ? null : onAccept,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2C6BC0),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              strings.accept,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style(
                                context,
                                14,
                                FontWeight.w600,
                                Colors.white,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            )
          else
            Text(
              strings.waiting(otherName),
              key: const ValueKey('together_waiting'),
              textAlign: TextAlign.center,
              style: _style(context, 12, FontWeight.w400,
                  const Color(0xFF8A8A8A),
                  line: 17),
            ),
        ],
      ),
    );
  }

  Widget _face(Widget child) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFF5F8FC), width: 2),
        ),
        child: ClipOval(child: child),
      );
}
