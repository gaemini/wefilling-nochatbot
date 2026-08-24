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
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
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
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
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
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
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

class SocialProfilePromptField extends StatefulWidget {
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
  State<SocialProfilePromptField> createState() =>
      _SocialProfilePromptFieldState();
}

class _SocialProfilePromptFieldState extends State<SocialProfilePromptField> {
  bool _showCustomInput = false;
  bool _updatingController = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleControllerChanged);
    final value = widget.controller.text.trim();
    _showCustomInput = value.isNotEmpty && !_matchesSuggestion(value);
  }

  @override
  void didUpdateWidget(covariant SocialProfilePromptField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleControllerChanged);
      widget.controller.addListener(_handleControllerChanged);
      final value = widget.controller.text.trim();
      _showCustomInput = value.isNotEmpty && !_matchesSuggestion(value);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleControllerChanged);
    super.dispose();
  }

  bool _matchesSuggestion(String value) {
    return widget.suggestions.any(
      (option) => option.ko == value || option.en == value,
    );
  }

  void _handleControllerChanged() {
    if (!mounted || _updatingController) return;
    final value = widget.controller.text.trim();
    final matchesSuggestion = _matchesSuggestion(value);
    final shouldShowCustom =
        matchesSuggestion ? false : value.isNotEmpty || _showCustomInput;
    if (shouldShowCustom != _showCustomInput) {
      setState(() => _showCustomInput = shouldShowCustom);
    } else {
      setState(() {});
    }
  }

  void _setControllerText(String value) {
    _updatingController = true;
    widget.controller
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
    _updatingController = false;
  }

  void _selectSuggestion(String text) {
    setState(() {
      _showCustomInput = false;
      _setControllerText(text);
    });
  }

  void _selectCustomInput() {
    final current = widget.controller.text.trim();
    setState(() {
      _showCustomInput = true;
      if (_matchesSuggestion(current)) _setControllerText('');
    });
  }

  Widget _optionRow({
    required String text,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 20,
                  color:
                      selected ? AppColors.pointColor : const Color(0xFFCBD5E1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
                    fontSize: 15,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected
                        ? const Color(0xFF0F172A)
                        : const Color(0xFF475569),
                    height: 1.42,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageCode = Localizations.localeOf(context).languageCode;
    final currentValue = widget.controller.text.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileSectionHeading(
          title: widget.title,
          description: widget.description,
        ),
        const SizedBox(height: 14),
        Column(
          children: [
            for (final suggestion in widget.suggestions)
              _optionRow(
                text: suggestion.label(languageCode),
                selected: (currentValue == suggestion.ko ||
                        currentValue == suggestion.en) &&
                    !_showCustomInput,
                onTap: () => _selectSuggestion(suggestion.label(languageCode)),
              ),
            _optionRow(
              text: languageCode == 'ko'
                  ? '직접 입력 (선택)'
                  : 'Write my own (optional)',
              selected: _showCustomInput,
              onTap: _selectCustomInput,
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !_showCustomInput
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextFormField(
                    controller: widget.controller,
                    maxLength: widget.maxLength,
                    minLines: 1,
                    maxLines: 2,
                    autofocus: false,
                    decoration: socialProfileInputDecoration(
                      hintText: widget.hintText,
                    ),
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF0F172A),
                      height: 1.45,
                    ),
                  ),
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
      fontFamily: 'Inter',
      fontFamilyFallback: const ['NotoSansKR'],
      fontSize: 15,
      fontWeight: FontWeight.w400,
      color: Color(0xFF94A3B8),
    ),
    helperStyle: const TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: const ['NotoSansKR'],
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
                      fontFamily: 'Inter',
                      fontFamilyFallback: const ['NotoSansKR'],
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
                        fontFamily: 'Inter',
                        fontFamilyFallback: const ['NotoSansKR'],
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
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
              height: 1.45,
            ),
          ),
        ],
        if (conversationStarter.trim().isNotEmpty) ...[
          const SizedBox(height: 18),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                languageCode == 'ko' ? '그대에게 물어보고 싶어요' : "I'd like to ask you",
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                conversationStarter.trim(),
                style: const TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: ['NotoSansKR'],
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0F172A),
                  height: 1.45,
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
            fontFamily: 'Inter',
            fontFamilyFallback: const ['NotoSansKR'],
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
                    fontFamily: 'Inter',
                    fontFamilyFallback: const ['NotoSansKR'],
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
