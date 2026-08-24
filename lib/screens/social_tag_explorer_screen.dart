import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/social_profile_data.dart';
import '../utils/responsive_helper.dart';
import 'social_tag_people_screen.dart';

class SocialTagExplorerScreen extends StatelessWidget {
  const SocialTagExplorerScreen({super.key});

  bool _isKorean(BuildContext context) =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ko';

  void _openPeople(
    BuildContext context,
    SocialProfileOption option,
    SocialProfileTagKind kind,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialTagPeopleScreen(tagId: option.id, kind: kind),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isKorean = _isKorean(context);
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 360
        ? 14.0
        : width < 600
            ? 18.0
            : 28.0;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: context.rh(56, min: 54, max: 60),
        leadingWidth: 48,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: Icon(
            Icons.arrow_back_rounded,
            size: context.ri(22).clamp(21, 24).toDouble(),
            color: const Color(0xFF111827),
          ),
        ),
        titleSpacing: 2,
        title: Text(
          isKorean ? '태그로 친구 찾기' : 'Find friends by tag',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(17).clamp(16, 18).toDouble(),
            fontWeight: FontWeight.w700,
            color: const Color(0xFF111827),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.25,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  context.rs(14).clamp(12, 18).toDouble(),
                  horizontalPadding,
                  context.rs(28).clamp(24, 36).toDouble(),
                ),
                children: [
                  Text(
                    isKorean
                        ? '관심 있는 태그를 누르면 같은 태그를 선택한 사람을 볼 수 있어요.'
                        : 'Choose a tag to meet people who selected it.',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: context.rf(13).clamp(12, 14).toDouble(),
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF667085),
                      height: 1.45,
                    ),
                  ),
                  SizedBox(height: context.rs(24).clamp(20, 28).toDouble()),
                  _TagSection(
                    title: isKorean ? '관심사' : 'Interests',
                    options: SocialProfileCatalog.interests,
                    kind: SocialProfileTagKind.interest,
                    onPressed: (option) => _openPeople(
                      context,
                      option,
                      SocialProfileTagKind.interest,
                    ),
                  ),
                  SizedBox(height: context.rs(28).clamp(24, 34).toDouble()),
                  _TagSection(
                    title: isKorean ? '함께 하고 싶은 활동' : 'Activities',
                    options: SocialProfileCatalog.activities,
                    kind: SocialProfileTagKind.activity,
                    onPressed: (option) => _openPeople(
                      context,
                      option,
                      SocialProfileTagKind.activity,
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
}

class _TagSection extends StatelessWidget {
  const _TagSection({
    required this.title,
    required this.options,
    required this.kind,
    required this.onPressed,
  });

  final String title;
  final List<SocialProfileOption> options;
  final SocialProfileTagKind kind;
  final ValueChanged<SocialProfileOption> onPressed;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
            fontSize: context.rf(16).clamp(15, 17).toDouble(),
            fontWeight: FontWeight.w800,
            color: const Color(0xFF111827),
          ),
        ),
        SizedBox(height: context.rs(11).clamp(9, 13).toDouble()),
        Wrap(
          spacing: context.rs(7).clamp(6, 9).toDouble(),
          runSpacing: context.rs(8).clamp(7, 10).toDouble(),
          children: options.map((option) {
            final label = option.label(languageCode);
            return Semantics(
              button: true,
              label: label,
              hint: kind == SocialProfileTagKind.interest
                  ? 'interest tag'
                  : 'activity tag',
              child: Material(
                color: const Color(0xFFF4F6F8),
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onPressed(option),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: context.rs(12).clamp(10, 14).toDouble(),
                      vertical: context.rs(8).clamp(7, 9).toDouble(),
                    ),
                    child: Text(
                      '#$label',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
                        fontSize: context.rf(13).clamp(12, 14).toDouble(),
                        fontWeight: FontWeight.w700,
                        color: AppColors.pointColor,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
}
