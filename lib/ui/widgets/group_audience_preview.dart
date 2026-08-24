import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../utils/responsive_helper.dart';
import 'user_avatar.dart';

class GroupAudiencePreview extends StatelessWidget {
  const GroupAudiencePreview({
    super.key,
    required this.members,
    required this.loading,
  });

  final List<UserProfile> members;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final isKorean =
        Localizations.localeOf(context).languageCode.toLowerCase() == 'ko';

    return Padding(
      padding: EdgeInsets.only(
        top: context.rs(2).clamp(2, 4).toDouble(),
        bottom: context.rs(10).clamp(8, 12).toDouble(),
      ),
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loading
                  ? (isKorean ? '포함된 사람' : 'People included')
                  : isKorean
                      ? '포함된 사람 ${members.length}명'
                      : '${members.length} ${members.length == 1 ? 'person' : 'people'} included',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: context.rf(11.5).clamp(11, 12.5).toDouble(),
                fontWeight: FontWeight.w700,
                color: const Color(0xFF667085),
                height: 1.25,
              ),
            ),
            const SizedBox(height: 7),
            if (loading)
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              )
            else if (members.isEmpty)
              Text(
                isKorean
                    ? '이 그룹에 포함된 친구가 없어요.'
                    : 'There are no friends in this group.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(12).clamp(11.5, 13).toDouble(),
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF98A2B3),
                  height: 1.35,
                ),
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final itemWidth = constraints.maxWidth < 280
                      ? constraints.maxWidth
                      : ((constraints.maxWidth - 12) / 2).clamp(120.0, 190.0);
                  return Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: members
                        .map(
                          (member) => SizedBox(
                            width: itemWidth,
                            child: Row(
                              children: [
                                UserAvatar(
                                  uid: member.uid,
                                  photoUrl: member.photoURL ?? '',
                                  photoVersion: 0,
                                  isAnonymous: false,
                                  size: 26,
                                  placeholderColor: const Color(0xFFF2F4F7),
                                  placeholderIcon: Icons.person_outline_rounded,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    member.displayNameOrNickname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Inter',
                                      fontFamilyFallback: const ['NotoSansKR'],
                                      fontSize: context
                                          .rf(12.5)
                                          .clamp(12, 13.5)
                                          .toDouble(),
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF344054),
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                        .toList(growable: false),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}
