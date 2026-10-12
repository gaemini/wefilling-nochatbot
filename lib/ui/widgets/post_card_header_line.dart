// lib/ui/widgets/post_card_header_line.dart
// 피드 포스트 카드 머리줄(이름 · 국기 · 시간 [· 공개 범위]) + 오른쪽 끝 버튼.
// 이름이 먼저 말줄임된다. 오른쪽 버튼은 머리줄의 45%를 넘지 않는다.

import 'package:flutter/material.dart';

class PostCardHeaderLine extends StatelessWidget {
  const PostCardHeaderLine({
    super.key,
    required this.name,
    required this.details,
    this.trailing,
  });

  /// 작성자 이름(한 줄 말줄임 위젯). 남는 폭 안에서 먼저 줄어든다.
  final Widget name;

  /// 이름 뒤의 국기·구분점·시간 등. 그대로 이어 붙인다.
  final List<Widget> details;

  /// 오른쪽 끝(친구 추가 버튼). 줄어들지 않는다.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final line = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Flexible(child: name),
        ...details,
      ],
    );
    final trailing = this.trailing;
    if (trailing == null) return line;
    // 아주 좁거나 글자가 크면 버튼은 머리줄의 45%까지만 쓰고(그 안에서 문구가
    // 말줄임), 나머지는 이름이 먼저 줄어드는 기존 머리줄에 준다.
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: line),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (constraints.maxWidth * .45).clamp(44.0, 240.0),
            ),
            child: trailing,
          ),
        ],
      ),
    );
  }
}
