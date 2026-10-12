// lib/ui/widgets/relationship_orbit.dart
// 아바타 오른쪽 아래의 작은 관계 노드.
//
// 아바타 주변 링은 그리지 않는다. 비친구에게는 `+` 노드(친구 요청),
// 요청을 보낸 뒤에는 작은 시계 표식을 보이고, 친구에게는 아무것도 보이지 않는다.
// 노드는 아바타의 탭 영역(프로필 열기)과 겹쳐 중첩되지 않도록 형제로 배치되며,
// 아바타 프레임 밖까지 뻗은 탭 영역도 실제로 동작한다.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../design/tokens.dart';
import '../../l10n/relationship_strings.dart';
import '../../models/relationship_orbit_state.dart';

class RelationshipOrbit extends StatelessWidget {
  const RelationshipOrbit({
    super.key,
    required this.state,
    required this.size,
    required this.child,
    this.showNode = true,
    this.onRelationshipAction,
    this.actionInFlight = false,
    this.semanticsLabel,
    this.nodeSemanticsLabel,
  });

  /// 관계 상태.
  final OrbitRelationshipState state;

  /// 아바타(자식) 크기. 레이아웃은 이 크기만 차지한다.
  final double size;

  /// 아바타 위젯. 프로필 열기 같은 자체 탭 동작을 가질 수 있다.
  final Widget child;

  /// `+` 노드 표시 여부. 비친구라도 요청을 보낼 수 없으면 숨긴다.
  final bool showNode;

  /// `+` 노드 탭 시 기존 친구 요청 흐름으로 연결한다.
  final VoidCallback? onRelationshipAction;

  /// 요청 전송 중 노드에 작은 진행 표시를 보인다.
  final bool actionInFlight;

  /// 스크린리더용 관계 상태 라벨. 없으면 로케일 기본 문구를 쓴다.
  final String? semanticsLabel;

  /// `+` 노드의 접근성 라벨. 없으면 '친구 요청 보내기'.
  final String? nodeSemanticsLabel;

  /// `+` 노드의 실제 탭 영역 키(테스트용).
  static const Key nodeKey = ValueKey<String>('relationship-orbit-node');

  /// 레이아웃 크기. 링이 없으므로 아바타 크기와 같다.
  static double frameSizeFor(double size) => size;

  /// `+` 노드의 시각 크기. 40dp 아바타에서 16dp.
  static double nodeVisualFor(double size) =>
      (size * .4).clamp(14.0, 17.0).toDouble();

  /// 노드 탭 영역 한 변.
  static const double nodeHitSize = 40;

  @override
  Widget build(BuildContext context) {
    final strings = RelationshipStrings.of(context);
    final visual = nodeVisualFor(size);
    // 노드는 아바타 오른쪽 아래 모서리에 살짝 걸친다.
    final nodeLeft = size - visual * .82;
    final nodeTop = size - visual * .82;
    // 탭 영역은 아바타 바깥(오른쪽·아래)으로 뻗어 프로필 탭과 거의 겹치지 않는다.
    final hitLeft = nodeLeft - 4;
    final hitTop = nodeTop - 4;
    final overflow = hitLeft + nodeHitSize - size;

    final showPlusNode = state == OrbitRelationshipState.notConnected &&
        showNode &&
        onRelationshipAction != null;
    final showPendingMark = state == OrbitRelationshipState.requestSent;

    return _OrbitHitRegion(
      frame: size,
      overflow: overflow,
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: semanticsLabel ?? strings.orbitState(state),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              top: 0,
              width: size,
              height: size,
              child: ClipOval(child: child),
            ),
            if (showPendingMark)
              Positioned(
                left: nodeLeft,
                top: nodeTop,
                child: Semantics(
                  label: nodeSemanticsLabel ?? strings.friendRequestPending,
                  child: _PendingMark(size: visual),
                ),
              ),
            if (showPlusNode)
              Positioned(
                left: hitLeft,
                top: hitTop,
                width: nodeHitSize,
                height: nodeHitSize,
                child: Semantics(
                  button: true,
                  enabled: !actionInFlight,
                  label: nodeSemanticsLabel ?? strings.sendFriendRequest,
                  child: GestureDetector(
                    key: nodeKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: actionInFlight ? null : onRelationshipAction,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: _PlusNode(size: visual, inFlight: actionInFlight),
                      ),
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

class _PlusNode extends StatelessWidget {
  const _PlusNode({required this.size, required this.inFlight});

  final double size;
  final bool inFlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: OrbitTokens.nodeBackground,
        shape: BoxShape.circle,
        border: Border.all(color: OrbitTokens.nodeHalo, width: 1.5),
      ),
      child: inFlight
          ? Padding(
              padding: EdgeInsets.all(size * .25),
              child: const CircularProgressIndicator(
                strokeWidth: 1.4,
                color: OrbitTokens.nodeForeground,
              ),
            )
          : Icon(
              Icons.add_rounded,
              size: size * .8,
              color: OrbitTokens.nodeForeground,
            ),
    );
  }
}

class _PendingMark extends StatelessWidget {
  const _PendingMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: OrbitTokens.pending, width: 1.2),
      ),
      child: Icon(
        Icons.schedule_rounded,
        size: size * .7,
        color: OrbitTokens.pending,
      ),
    );
  }
}

/// 레이아웃은 [frame] 크기로 하되, 자식은 [overflow]만큼 더 큰 영역을 차지하고
/// 그 영역 전체에서 히트 테스트를 받는다. 노드 탭 영역이 아바타 밖까지 닿게 한다.
/// 이 위젯이 Row 등의 직접 자식일 때 바깥 영역 탭이 실제로 전달된다.
class _OrbitHitRegion extends SingleChildRenderObjectWidget {
  const _OrbitHitRegion({
    required this.frame,
    required this.overflow,
    required Widget super.child,
  });

  final double frame;
  final double overflow;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderOrbitHitRegion(frame: frame, overflow: overflow);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderOrbitHitRegion renderObject,
  ) {
    renderObject
      ..frame = frame
      ..overflow = overflow;
  }
}

class _RenderOrbitHitRegion extends RenderShiftedBox {
  _RenderOrbitHitRegion({required double frame, required double overflow})
      : _frame = frame,
        _overflow = overflow,
        super(null);

  double _frame;
  double get frame => _frame;
  set frame(double value) {
    if (_frame == value) return;
    _frame = value;
    markNeedsLayout();
  }

  double _overflow;
  double get overflow => _overflow;
  set overflow(double value) {
    if (_overflow == value) return;
    _overflow = value;
    markNeedsLayout();
  }

  double get _extent => frame + (overflow > 0 ? overflow : 0);

  @override
  double computeMinIntrinsicWidth(double height) => frame;
  @override
  double computeMaxIntrinsicWidth(double height) => frame;
  @override
  double computeMinIntrinsicHeight(double width) => frame;
  @override
  double computeMaxIntrinsicHeight(double width) => frame;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(Size.square(frame));

  @override
  void performLayout() {
    size = constraints.constrain(Size.square(frame));
    final child = this.child;
    if (child == null) return;
    child.layout(BoxConstraints.tight(Size.square(_extent)));
    (child.parentData! as BoxParentData).offset = Offset.zero;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // 프레임 경계 검사를 생략해 노드 탭 영역이 프레임 밖까지 닿는다.
    if (hitTestChildren(result, position: position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }
}
