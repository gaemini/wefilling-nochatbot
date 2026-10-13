// lib/ui/widgets/tab_empty_state.dart
// 스낵챗 탭의 빈 화면(스낵챗·그룹)이 함께 쓰는 제목/설명/버튼과 목록 미리보기.
// 글자는 제목 17, 설명 13, 보조 12, 버튼 15만 쓴다(화면 비례 크기 없음).

import 'package:flutter/material.dart';

import '../../l10n/ui_locale.dart';
import 'audience_ring.dart';
import 'motion_press.dart';

const Color emptyStateAccent = Color(0xFF2C6BC0);

/// 제목 17/24 700 #000, 설명 13/19 #707070(가운데 정렬).
class TabEmptyStateText extends StatelessWidget {
  const TabEmptyStateText({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final zh = isChineseUi(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            key: const ValueKey('tab_empty_title'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 17,
              height: zh ? 1.4 : 24 / 17,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            key: const ValueKey('tab_empty_body'),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: uiFontFamily(context, 'Inter'),
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 13,
              height: zh ? 1.5 : 19 / 13,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF707070),
            ),
          ),
        ],
      ),
    );
  }
}

/// 높이 46, 좌우 22, 모서리 23, 내용 폭 버튼(아이콘 없음).
class TabEmptyStateButton extends StatelessWidget {
  const TabEmptyStateButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MotionPress(
      pressedScale: .975,
      child: Material(
        color: emptyStateAccent,
        borderRadius: BorderRadius.circular(23),
        child: InkWell(
          borderRadius: BorderRadius.circular(23),
          onTap: onPressed,
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            alignment: Alignment.center,
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 15,
                height: 20 / 15,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 스낵챗 빈 화면의 흐린 목록 예시(장식). 탭할 수 없고 스크린리더에서 제외된다.
class SnackChatEmptyPreview extends StatelessWidget {
  const SnackChatEmptyPreview({
    super.key,
    required this.rows,
    required this.sampleTitle,
    required this.sampleRemaining,
    required this.sampleMessage,
  });

  /// 보여 줄 줄 수(2 또는 3).
  final int rows;
  final String sampleTitle;
  final String sampleRemaining;
  final String sampleMessage;

  static const double rowHeight = 64;
  static const Color _text = Color(0xFFC9C9C9);

  @override
  Widget build(BuildContext context) {
    final height = rows * rowHeight;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: SizedBox(
          key: const ValueKey('snack_chat_empty_preview'),
          height: height,
          child: Stack(
            children: [
              Column(
                children: [
                  _row(context, first: true, bars: const [.46, .72]),
                  for (var i = 1; i < rows; i++)
                    _row(
                      context,
                      first: false,
                      bars: i == 1 ? const [.46, .72] : const [.34, .58],
                    ),
                ],
              ),
              // 맨 아래 60은 흰색으로 페이드한다.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 60,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00FFFFFF), Colors.white],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, {required bool first, required List<double> bars}) {
    return SizedBox(
      height: rowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            if (first)
              AudienceRing(
                restricted: true,
                size: 48,
                ringWidth: 2,
                innerGap: 1,
                borderRadius: BorderRadius.circular(12),
                child: _tiles(),
              )
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F2F2),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: first
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sampleTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 15,
                            height: 20 / 15,
                            fontWeight: FontWeight.w600,
                            color: _text,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: sampleRemaining,
                                style: const TextStyle(
                                  color: Color(0xFF9FBBE0),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: ' · $sampleMessage'),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 13,
                            height: 18 / 13,
                            color: _text,
                          ),
                        ),
                      ],
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) => Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (var i = 0; i < bars.length; i++) ...[
                            if (i > 0) const SizedBox(height: 8),
                            Container(
                              height: 10,
                              width: constraints.maxWidth * bars[i],
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F0F0),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tiles() {
    Widget tile() => Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF1F4),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return SizedBox(
      width: 42,
      height: 42,
      child: Center(
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          children: [tile(), tile(), tile(), tile()],
        ),
      ),
    );
  }
}
