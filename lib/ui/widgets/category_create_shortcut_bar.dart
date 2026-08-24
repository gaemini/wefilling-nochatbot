import 'package:flutter/material.dart';

import '../../utils/responsive_helper.dart';

class CategoryCreateShortcutBar extends StatelessWidget {
  const CategoryCreateShortcutBar({
    super.key,
    required this.postLabel,
    required this.meetupLabel,
    required this.snackChatLabel,
    required this.createPostLabel,
    required this.createMeetupLabel,
    required this.createSnackChatLabel,
    required this.onCreatePost,
    required this.onCreateMeetup,
    required this.onCreateSnackChat,
  });

  final String postLabel;
  final String meetupLabel;
  final String snackChatLabel;
  final String createPostLabel;
  final String createMeetupLabel;
  final String createSnackChatLabel;
  final VoidCallback onCreatePost;
  final VoidCallback onCreateMeetup;
  final VoidCallback onCreateSnackChat;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 360 ? 12.0 : 16.0;
        return Padding(
          padding: EdgeInsets.fromLTRB(horizontal, 6, horizontal, 8),
          child: Row(
            children: [
              Expanded(
                child: _CategoryCreateShortcut(
                  key: const ValueKey('create_post_shortcut'),
                  icon: Icons.article_outlined,
                  label: postLabel,
                  semanticLabel: createPostLabel,
                  onTap: onCreatePost,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _CategoryCreateShortcut(
                  key: const ValueKey('create_meetup_shortcut'),
                  icon: Icons.groups_outlined,
                  label: meetupLabel,
                  semanticLabel: createMeetupLabel,
                  onTap: onCreateMeetup,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _CategoryCreateShortcut(
                  key: const ValueKey('create_snack_chat_shortcut'),
                  icon: Icons.forum_outlined,
                  label: snackChatLabel,
                  semanticLabel: createSnackChatLabel,
                  onTap: onCreateSnackChat,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryCreateShortcut extends StatelessWidget {
  const _CategoryCreateShortcut({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.15,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: context.ri(21).clamp(20, 23).toDouble(),
                        color: const Color(0xFF667085),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontFamilyFallback: const ['NotoSansKR'],
                          fontSize: context.rf(12.5).clamp(11.5, 13).toDouble(),
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF344054),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
