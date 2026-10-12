import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';
import '../../l10n/ui_locale.dart';
import '../../utils/chat_date_label.dart';

/// Accumulates only direct-drag deltas supplied by SnackChatScreen and maps
/// reversed scroll axes to the direction a person sees on screen.
class SnackChatToolbarScrollTracker {
  SnackChatToolbarScrollTracker({this.threshold = 16});

  final double threshold;
  bool visible = true;
  double _directionalDistance = 0;
  bool? _movingTowardVisualBottom;

  void resetGesture() {
    _directionalDistance = 0;
    _movingTowardVisualBottom = null;
  }

  void resetRoom() {
    visible = true;
    resetGesture();
  }

  /// Returns a visibility value only when the toolbar should actually change.
  bool? addUserDelta({
    required AxisDirection axisDirection,
    required double scrollDelta,
    required bool outOfRange,
    required double scrollableExtent,
  }) {
    if (outOfRange) return null;
    if (scrollableExtent <= 1) {
      resetGesture();
      if (!visible) {
        visible = true;
        return true;
      }
      return null;
    }
    if (scrollDelta.abs() < .5) return null;

    final movingTowardVisualBottom = switch (axisDirection) {
      AxisDirection.down => scrollDelta > 0,
      AxisDirection.up => scrollDelta < 0,
      _ => false,
    };
    if (_movingTowardVisualBottom != movingTowardVisualBottom) {
      _movingTowardVisualBottom = movingTowardVisualBottom;
      _directionalDistance = 0;
    }
    _directionalDistance += scrollDelta.abs();
    if (_directionalDistance < threshold) return null;

    _directionalDistance = 0;
    final nextVisible = !movingTowardVisualBottom;
    if (visible == nextVisible) return null;
    visible = nextVisible;
    return nextVisible;
  }
}

/// 스낵챗 v3 디자인 값 (위필링 디자인 시스템).
class SnackChatPalette {
  SnackChatPalette._();

  static const Color background = Color(0xFFFFFFFF);
  static const Color ink = Color(0xFF000000);
  static const Color inkSecondary = Color(0xFF5F5F5F);
  static const Color inkTertiary = Color(0xFF707070);
  static const Color fillSubtle = Color(0xFFEEEEEE);
  static const Color hairline = Color(0xFFEBEBEB);
  static const Color pointStrong = Color(0xFF2C6BC0);
}

/// 스낵챗 대화 영역 배경. v3부터는 무늬 없는 흰 면이다.
class SnackChatBackdrop extends StatelessWidget {
  const SnackChatBackdrop({super.key, required this.child});

  static const Color backgroundColor = SnackChatPalette.background;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: backgroundColor, child: child);
  }
}

/// 방 제목 한 줄 + 아래에 참여자 아바타(최대 3개)와 인원 글자.
class SnackChatHeaderTitle extends StatelessWidget {
  const SnackChatHeaderTitle({
    super.key,
    required this.roomTitle,
    required this.participantLabel,
    this.participantAvatars = const <Widget>[],
  });

  final String roomTitle;
  final String participantLabel;

  /// 이미 로드된 참여자 아바타(16px). 비어 있으면 글자만 표시한다.
  final List<Widget> participantAvatars;

  static const double avatarSize = 16;

  @override
  Widget build(BuildContext context) {
    final avatars = participantAvatars.take(3).toList(growable: false);
    const overlap = 5.0;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.15,
      child: Semantics(
        header: true,
        label: '$roomTitle, $participantLabel',
        excludeSemantics: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              roomTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(16).clamp(15, 17).toDouble(),
                fontWeight: FontWeight.w700,
                color: SnackChatPalette.ink,
                height: isChineseUi(context) ? 1.3 : 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (avatars.isNotEmpty) ...[
                  SizedBox(
                    width: avatarSize +
                        (avatars.length - 1) * (avatarSize - overlap),
                    height: avatarSize,
                    child: Stack(
                      children: [
                        for (var i = 0; i < avatars.length; i++)
                          Positioned(
                            left: i * (avatarSize - overlap),
                            child: SizedBox.square(
                              dimension: avatarSize,
                              child: avatars[i],
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    participantLabel,
                    key: const ValueKey('snack_chat_participant_badge'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: SnackChatPalette.inkTertiary,
                      height: isChineseUi(context) ? 1.36 : 15 / 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact, high-contrast date marker for the beginning of a message day.
class SnackChatDateSeparator extends StatelessWidget {
  const SnackChatDateSeparator({
    super.key,
    required this.date,
    required this.languageCode,
  });

  final DateTime date;
  final String languageCode;

  static String formatDate(DateTime date, {required String languageCode}) =>
      formatChatCalendarDate(date, languageCode: languageCode);

  @override
  Widget build(BuildContext context) {
    final label = formatDate(date, languageCode: languageCode);
    return Semantics(
      key: ValueKey<String>(
        'snack_chat_date_${date.toLocal().year}_'
        '${date.toLocal().month}_${date.toLocal().day}',
      ),
      header: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          context.rs(8).clamp(6, 10).toDouble(),
          context.rs(15).clamp(12, 18).toDouble(),
          context.rs(8).clamp(6, 10).toDouble(),
          context.rs(10).clamp(8, 12).toDouble(),
        ),
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Row(
            children: [
              const Expanded(
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: SnackChatPalette.hairline,
                ),
              ),
              Flexible(
                flex: 0,
                child: Container(
                  key: const ValueKey('snack_chat_date_badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: uiFontFamily(context, 'Inter'),
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: SnackChatPalette.inkTertiary,
                      height: isChineseUi(context) ? 1.36 : 15 / 11,
                    ),
                  ),
                ),
              ),
              const Expanded(
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: SnackChatPalette.hairline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
