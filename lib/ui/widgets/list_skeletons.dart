// lib/ui/widgets/list_skeletons.dart
// 목록 자리표시(모션 2부 D·F). 불러오는 동안 스피너 대신 실제 행과 같은 높이의
// 회색 모양을 보여 주어, 데이터가 오면 같은 자리에 내용이 들어선다.

import 'package:flutter/material.dart';

const Color kSkeletonFill = Color(0xFFF0F1F3);

Widget _bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: kSkeletonFill,
        borderRadius: BorderRadius.circular(height / 2),
      ),
    );

/// 댓글 줄 자리표시(아바타 30 둥근 네모 + 막대 2개). 높이는 댓글 한 개의
/// 평균 높이에 맞춰 데이터가 와도 위치가 튀지 않게 한다. 스크롤 안에 들어가므로
/// Column이다.
class CommentListSkeleton extends StatelessWidget {
  const CommentListSkeleton({super.key, this.rows = 3});

  final int rows;

  static const List<double> _widths = <double>[188, 132, 224, 156];

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('comment_list_skeleton'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: kSkeletonFill,
                      borderRadius: BorderRadius.circular(7.5),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bar(72, 10),
                      const SizedBox(height: 8),
                      _bar(_widths[i % _widths.length], 14),
                      const SizedBox(height: 14),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
