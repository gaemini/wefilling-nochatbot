// lib/ui/widgets/post_card_header_line.dart
// 피드 포스트 카드 머리줄(이름 · 국기 · 시간 [· 공개 범위]) + 오른쪽 끝 버튼.
// 이름이 먼저 말줄임된다. 오른쪽 버튼은 머리줄의 45%를 넘지 않는다.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class PostCardHeaderLine extends StatelessWidget {
  const PostCardHeaderLine({
    super.key,
    required this.name,
    required this.details,
    this.trailing,
    this.reserveTrailingHeight = false,
  });

  /// 작성자 이름(한 줄 말줄임 위젯). 남는 폭 안에서 먼저 줄어든다.
  final Widget name;

  /// 이름 뒤의 국기·구분점·시간 등. 그대로 이어 붙인다.
  final List<Widget> details;

  /// 오른쪽 끝(친구 추가 버튼). 줄어들지 않는다.
  final Widget? trailing;

  /// true면 줄 높이를 버튼 높이까지 넓힌다. 본문 글 없이 사진·링크가 바로
  /// 이어지는 카드에서 버튼이 사진에 닿지 않게 한다(글이 있으면 겹쳐 그림).
  final bool reserveTrailingHeight;

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
    // 줄 높이는 이름 줄만으로 정한다. 친구 추가 버튼(터치 44)은 줄 가운데에
    // 겹쳐 그려, 버튼이 있는 카드와 없는 카드의 아래 간격이 같다.
    return _HeaderLineLayout(
      gap: 4,
      reserveTrailingHeight: reserveTrailingHeight,
      line: line,
      trailing: trailing,
    );
  }
}

/// [line]의 높이만 차지하고, [trailing]은 오른쪽 끝·세로 가운데에 겹쳐 둔다.
class _HeaderLineLayout extends MultiChildRenderObjectWidget {
  _HeaderLineLayout({
    required Widget line,
    required Widget trailing,
    required this.gap,
    required this.reserveTrailingHeight,
  }) : super(children: <Widget>[line, trailing]);

  final double gap;
  final bool reserveTrailingHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeaderLine(
      gap: gap, reserveTrailingHeight: reserveTrailingHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderHeaderLine renderObject,
  ) {
    renderObject
      ..gap = gap
      ..reserveTrailingHeight = reserveTrailingHeight;
  }
}

class _HeaderLineParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeaderLine extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeaderLineParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeaderLineParentData> {
  _RenderHeaderLine({required double gap, required bool reserveTrailingHeight})
      : _gap = gap,
        _reserveTrailingHeight = reserveTrailingHeight;

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  bool _reserveTrailingHeight;
  set reserveTrailingHeight(bool value) {
    if (value == _reserveTrailingHeight) return;
    _reserveTrailingHeight = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeaderLineParentData) {
      child.parentData = _HeaderLineParentData();
    }
  }

  double _trailingMaxWidth(double maxWidth) =>
      (maxWidth * .45).clamp(44.0, 240.0);

  @override
  void performLayout() {
    final line = firstChild!;
    final trailing = childAfter(line)!;
    final maxWidth = constraints.maxWidth;
    trailing.layout(
      BoxConstraints(maxWidth: _trailingMaxWidth(maxWidth)),
      parentUsesSize: true,
    );
    final lineWidth =
        (maxWidth - _gap - trailing.size.width).clamp(0.0, maxWidth);
    line.layout(
      BoxConstraints(minWidth: lineWidth, maxWidth: lineWidth),
      parentUsesSize: true,
    );
    // 이름 줄과 버튼 위치는 그대로(버튼은 이름 줄 가운데). 예약하면 버튼이
    // 이름 줄 아래로 나온 만큼만 높이를 늘린다.
    final lineHeight = line.size.height;
    final trailingTop = (lineHeight - trailing.size.height) / 2;
    final trailingBottom = trailingTop + trailing.size.height;
    final height = _reserveTrailingHeight && trailingBottom > lineHeight
        ? trailingBottom
        : lineHeight;
    size = constraints.constrain(Size(maxWidth, height));
    (line.parentData! as _HeaderLineParentData).offset = Offset.zero;
    (trailing.parentData! as _HeaderLineParentData).offset = Offset(
      size.width - trailing.size.width,
      trailingTop,
    );
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild!.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild!.getMaxIntrinsicHeight(width);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  // 버튼이 줄 높이 밖으로 나와도 그 부분을 누를 수 있게 한다.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

