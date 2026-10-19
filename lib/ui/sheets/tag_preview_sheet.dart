import 'package:flutter/material.dart';

import '../../services/interest_tag_service.dart';
import '../interest/tag_detail_sheet.dart';
import '../widgets/user_avatar.dart';

/// 프로필의 태그를 누르면 보이는 시트. v4 공통 태그 시트를 쓴다.
Future<void> showTagPreviewSheet(BuildContext context,
        {required String tagId}) =>
    showTagDetailSheet(context, tagId: tagId);

/// 겹친 얼굴(최대 4).
class TagFaces extends StatelessWidget {
  const TagFaces(
      {super.key, required this.people, this.size = 28, this.max = 4});

  final List<TagPerson> people;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(max).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final step = size * .72;
    return SizedBox(
      width: size + step * (shown.length - 1),
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: step * i,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: UserAvatar(
                  uid: shown[i].uid,
                  photoUrl: shown[i].photoURL,
                  photoVersion: 0,
                  isAnonymous: false,
                  size: size - 4,
                  placeholderColor: const Color(0xFFF2F4F7),
                  placeholderIcon: Icons.person_outline_rounded,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
