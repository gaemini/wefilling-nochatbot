// lib/screens/relationship_orbit_preview_screen.dart
// 개발용 프리뷰: 아바타 관계 노드를 상태별로 한 화면에서 본다.
// 디버그 빌드의 '/orbit-lab' 라우트로만 열린다.

import 'package:flutter/material.dart';

import '../models/relationship_orbit_state.dart';
import '../ui/widgets/relationship_orbit.dart';

class RelationshipOrbitPreviewScreen extends StatelessWidget {
  const RelationshipOrbitPreviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const sizes = <double>[36, 40, 44];
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Relationship node lab'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          for (final state in OrbitRelationshipState.values)
            _Section(
              title: state.name,
              children: [
                for (final size in sizes)
                  _Sample(
                    label: '${size.toInt()}',
                    child: RelationshipOrbit(
                      state: state,
                      size: size,
                      onRelationshipAction: () {},
                      child: _Avatar(size: size),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 36, runSpacing: 22, children: children),
        ],
      ),
    );
  }
}

class _Sample extends StatelessWidget {
  const _Sample({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(height: 72, child: Center(child: child)),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF667085)),
        ),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      color: const Color(0xFFE4E7EC),
      alignment: Alignment.center,
      child: Icon(Icons.person_outline_rounded,
          size: size * .5, color: const Color(0xFF667085)),
    );
  }
}
