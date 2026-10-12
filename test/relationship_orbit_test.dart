import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/relationship_orbit_state.dart';
import 'package:wefilling/models/relationship_status.dart';
import 'package:wefilling/ui/widgets/relationship_orbit.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(padding: const EdgeInsets.all(60), child: child),
      ),
    ),
  );
}

/// 시맨틱 트리 전체의 라벨을 모은다.
List<String> _semanticLabels(WidgetTester tester) {
  final root = tester.binding.pipelineOwner.semanticsOwner?.rootSemanticsNode;
  final labels = <String>[];
  void visit(SemanticsNode node) {
    final label = node.label;
    if (label.isNotEmpty) labels.add(label);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  if (root != null) visit(root);
  return labels;
}

Widget _avatar(double size) => SizedBox.square(
      dimension: size,
      child: const ColoredBox(color: Color(0xFFE4E7EC)),
    );

/// 포스트 카드 헤더와 같은 구조: 카드 전체 InkWell 안의 Row에
/// [관계 노드(프로필 탭 아바타)] [간격] [이름·본문 열].
Widget _postHeader({
  required VoidCallback onCard,
  required VoidCallback onProfile,
  required VoidCallback onRequest,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Material(
        child: InkWell(
          onTap: onCard,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RelationshipOrbit(
                  state: OrbitRelationshipState.notConnected,
                  size: 40,
                  onRelationshipAction: onRequest,
                  child: GestureDetector(
                    key: const ValueKey('profile'),
                    behavior: HitTestBehavior.opaque,
                    onTap: onProfile,
                    child: _avatar(40),
                  ),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('작성자'),
                      SizedBox(height: 120),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('관계 상태는 친구/요청 보냄/비친구 세 형태로 축약된다', () {
    expect(orbitStateFromRelationship(RelationshipStatus.friends),
        OrbitRelationshipState.friend);
    expect(orbitStateFromRelationship(RelationshipStatus.pendingOut),
        OrbitRelationshipState.requestSent);
    expect(orbitStateFromRelationship(RelationshipStatus.none),
        OrbitRelationshipState.notConnected);
    expect(
      orbitStateFromRelationship(RelationshipStatus.none,
          firstResponsePending: true),
      OrbitRelationshipState.requestSent,
    );
    expect(canRequestFriendship(RelationshipStatus.none), isTrue);
    expect(canRequestFriendship(RelationshipStatus.pendingIn), isFalse);
  });

  test('공통 맥락 조각은 최대 3개이며 중복을 제거한다', () {
    final signals = normalizeContextSignals([
      OrbitContextSignal.interest,
      OrbitContextSignal.interest,
      OrbitContextSignal.community,
      OrbitContextSignal.meetup,
      OrbitContextSignal.language,
    ]);
    expect(signals, [
      OrbitContextSignal.interest,
      OrbitContextSignal.community,
      OrbitContextSignal.meetup,
    ]);
  });

  test('링이 없으므로 레이아웃은 아바타 크기와 같고 + 노드는 40dp 기준 16dp다', () {
    expect(RelationshipOrbit.frameSizeFor(40), 40);
    expect(RelationshipOrbit.nodeVisualFor(40), 16);
    for (final size in <double>[32, 36, 44, 64]) {
      expect(RelationshipOrbit.nodeVisualFor(size), inInclusiveRange(14, 17));
    }
  });

  testWidgets('아바타 주변에 링을 그리지 않는다', (tester) async {
    for (final state in OrbitRelationshipState.values) {
      await tester.pumpWidget(_host(RelationshipOrbit(
        state: state,
        size: 40,
        onRelationshipAction: () {},
        child: _avatar(40),
      )));
      expect(
        find.descendant(
          of: find.byType(RelationshipOrbit),
          matching: find.byType(CustomPaint),
        ),
        findsNothing,
      );
      expect(tester.getSize(find.byType(RelationshipOrbit)), const Size(40, 40));
    }
  });

  testWidgets('포스트 헤더 구조에서 + 노드 탭은 친구 요청으로, 아바타 탭은 프로필로 간다',
      (tester) async {
    var card = 0, profile = 0, request = 0;
    await tester.pumpWidget(_postHeader(
      onCard: () => card++,
      onProfile: () => profile++,
      onRequest: () => request++,
    ));
    final node = find.byKey(RelationshipOrbit.nodeKey);
    expect(node, findsOneWidget);

    // 보이는 + 노드 중심.
    final plus = find.descendant(of: node, matching: find.byIcon(Icons.add_rounded));
    await tester.tap(plus);
    await tester.pump();
    expect(request, 1);
    expect(profile, 0);
    expect(card, 0);

    // 아바타 바깥 아래쪽(노드 탭 영역)도 요청으로 이어진다.
    final avatarRect = tester.getRect(find.byKey(const ValueKey('profile')));
    await tester.tapAt(avatarRect.bottomRight + const Offset(-6, 10));
    await tester.pump();
    expect(request, 2);

    // 아바타 가운데는 프로필.
    await tester.tapAt(avatarRect.center);
    await tester.pump();
    expect(profile, 1);
    expect(request, 2);
    expect(card, 0);
  });

  testWidgets('친구는 노드가 없고, 요청 보냄은 대기 표식만 보인다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(RelationshipOrbit(
      state: OrbitRelationshipState.friend,
      size: 40,
      onRelationshipAction: () {},
      child: _avatar(40),
    )));
    expect(find.byKey(RelationshipOrbit.nodeKey), findsNothing);
    expect(_semanticLabels(tester), isNot(contains('Send friend request')));

    await tester.pumpWidget(_host(RelationshipOrbit(
      state: OrbitRelationshipState.requestSent,
      size: 40,
      onRelationshipAction: () {},
      child: _avatar(40),
    )));
    expect(find.byKey(RelationshipOrbit.nodeKey), findsNothing);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
    expect(_semanticLabels(tester), contains('Friend request pending'));
    semantics.dispose();
  });

  testWidgets('비친구 + 노드는 접근성 라벨을 가진다', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(RelationshipOrbit(
      state: OrbitRelationshipState.notConnected,
      size: 40,
      onRelationshipAction: () {},
      child: _avatar(40),
    )));
    final labels = _semanticLabels(tester);
    expect(labels, contains('Send friend request'));
    expect(labels.any((l) => l.contains('Not connected yet')), isTrue);
    semantics.dispose();
  });
}
