import 'package:flutter/material.dart';

import '../constants/app_constants.dart';
import '../models/social_profile_data.dart';

class ProfileSectionHeading extends StatelessWidget {
  const ProfileSectionHeading({
    super.key,
    required this.title,
    this.description,
    this.trailing,
  });

  final String title;
  final String? description;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                  height: 1.3,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        if (description != null && description!.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            description!,
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Color(0xFF64748B),
              height: 1.45,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ],
    );
  }
}

class SocialProfileTagSelector extends StatelessWidget {
  const SocialProfileTagSelector({
    super.key,
    required this.options,
    required this.selectedIds,
    required this.onChanged,
    this.maxSelection = 5,
  });

  final List<SocialProfileOption> options;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;
  final int maxSelection;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;

    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: options.map((option) {
        final selected = selectedIds.contains(option.id);
        return FilterChip(
          selected: selected,
          showCheckmark: false,
          label: Text(option.label(languageCode)),
          labelStyle: TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 14,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : const Color(0xFF475569),
          ),
          backgroundColor: Colors.white,
          selectedColor: AppColors.pointColor,
          side: selected
              ? BorderSide.none
              : const BorderSide(color: Color(0xFFE2E8F0)),
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          onSelected: (value) {
            final next = List<String>.of(selectedIds);
            if (value) {
              if (next.length >= maxSelection) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      content: Text(
                        languageCode == 'ko'
                            ? '최대 $maxSelection개까지 선택할 수 있어요.'
                            : 'You can select up to $maxSelection.',
                      ),
                    ),
                  );
                return;
              }
              next.add(option.id);
            } else {
              next.remove(option.id);
            }
            onChanged(next);
          },
        );
      }).toList(growable: false),
    );
  }
}

class SocialProfilePromptField extends StatelessWidget {
  const SocialProfilePromptField({
    super.key,
    required this.controller,
    required this.suggestions,
    required this.title,
    required this.description,
    required this.hintText,
    this.maxLength = 50,
  });

  final TextEditingController controller;
  final List<SocialProfileOption> suggestions;
  final String title;
  final String description;
  final String hintText;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeading(title: title, description: description),
        const SizedBox(height: 14),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final text = suggestions[index].label(languageCode);
              return ActionChip(
                label: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                labelStyle: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF475569),
                ),
                backgroundColor: const Color(0xFFF8FAFC),
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onPressed: () {
                  controller
                    ..text = text
                    ..selection = TextSelection.collapsed(offset: text.length);
                },
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLength: maxLength,
          minLines: 1,
          maxLines: 2,
          decoration: socialProfileInputDecoration(hintText: hintText),
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: Color(0xFF0F172A),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

InputDecoration socialProfileInputDecoration({
  required String hintText,
  Widget? prefixIcon,
  String? helperText,
}) {
  return InputDecoration(
    hintText: hintText,
    helperText: helperText,
    prefixIcon: prefixIcon,
    hintStyle: const TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: Color(0xFF94A3B8),
    ),
    helperStyle: const TextStyle(
      fontFamily: 'Pretendard',
      fontSize: 12,
      color: Color(0xFF64748B),
    ),
    contentPadding: const EdgeInsets.symmetric(vertical: 13),
    enabledBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFE2E8F0)),
    ),
    focusedBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: AppColors.pointColor, width: 1.5),
    ),
    errorBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: const UnderlineInputBorder(
      borderSide: BorderSide(color: Color(0xFFDC2626), width: 1.5),
    ),
  );
}

class SocialProfilePreview extends StatelessWidget {
  const SocialProfilePreview({
    super.key,
    required this.nickname,
    required this.bio,
    required this.interests,
    required this.activities,
    required this.conversationStarter,
    required this.friendshipPrompt,
    this.avatar,
  });

  final String nickname;
  final String bio;
  final List<String> interests;
  final List<String> activities;
  final String conversationStarter;
  final String friendshipPrompt;
  final ImageProvider? avatar;

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    String label(String id, List<SocialProfileOption> options) =>
        SocialProfileCatalog.labelFor(id, options, languageCode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 34,
              backgroundColor: const Color(0xFFF1F5F9),
              backgroundImage: avatar,
              child: avatar == null
                  ? const Icon(Icons.person_rounded,
                      size: 32, color: Color(0xFF94A3B8))
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nickname.trim().isEmpty
                        ? (languageCode == 'ko' ? '나의 프로필' : 'My profile')
                        : nickname.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  if (bio.trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      bio.trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        color: Color(0xFF475569),
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (interests.isNotEmpty) ...[
          const SizedBox(height: 22),
          _PreviewSection(
            title: languageCode == 'ko' ? '요즘 관심 있는 것' : 'Into these days',
            values: interests
                .map((id) => label(id, SocialProfileCatalog.interests))
                .toList(growable: false),
          ),
        ],
        if (activities.isNotEmpty) ...[
          const SizedBox(height: 18),
          _PreviewSection(
            title: languageCode == 'ko' ? '같이 하고 싶은 것' : 'Let\'s do together',
            values: activities
                .map((id) => label(id, SocialProfileCatalog.activities))
                .toList(growable: false),
          ),
        ],
        if (friendshipPrompt.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Text(
            friendshipPrompt.trim(),
            style: const TextStyle(
              fontFamily: 'Pretendard',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
              height: 1.45,
            ),
          ),
        ],
        if (conversationStarter.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.chat_bubble_outline_rounded,
                  size: 18, color: AppColors.pointColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  conversationStarter.trim(),
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0F172A),
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _PreviewSection extends StatelessWidget {
  const _PreviewSection({required this.title, required this.values});

  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: values
              .map(
                (value) => Text(
                  '#$value',
                  style: const TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.pointColor,
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }
}
