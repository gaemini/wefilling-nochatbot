import 'package:flutter/material.dart';

import '../../constants/app_constants.dart';
import '../../l10n/ui_locale.dart';

const List<String> chatReactionEmojis = <String>[
  '👍',
  '❤️',
  '😂',
  '😮',
  '😢',
  '🙏',
];

class ChatReactionIcon extends StatelessWidget {
  const ChatReactionIcon(
    this.emoji, {
    super.key,
    this.size = 22,
  });

  final String emoji;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (emoji == '❤️') {
      return Icon(
        Icons.favorite_rounded,
        size: size,
        color: AppColors.pointColor,
      );
    }
    return SizedBox.square(
      dimension: size,
      child: Center(
        child: Text(
          emoji,
          strutStyle: StrutStyle(
            fontSize: size * .86,
            height: 1,
            forceStrutHeight: true,
          ),
          style: TextStyle(fontSize: size * .86, height: 1),
        ),
      ),
    );
  }
}

class ChatReactionPickerRow extends StatelessWidget {
  const ChatReactionPickerRow({
    super.key,
    required this.selectedReaction,
    required this.addLabel,
    required this.removeLabel,
    required this.onSelected,
  });

  final String? selectedReaction;
  final String addLabel;
  final String removeLabel;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: chatReactionEmojis.map((emoji) {
          final selected = selectedReaction == emoji;
          final semanticLabel = '${selected ? removeLabel : addLabel} $emoji';
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: semanticLabel,
              child: Tooltip(
                message: semanticLabel,
                child: InkResponse(
                  onTap: () => onSelected(emoji),
                  radius: 24,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.pointColor.withValues(alpha: .10)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: ChatReactionIcon(emoji),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}

class ChatReactionBar extends StatelessWidget {
  const ChatReactionBar({
    super.key,
    required this.counts,
    required this.myReaction,
    required this.onToggle,
    required this.onShowUsers,
    required this.isOutgoing,
    required this.addLabel,
    required this.removeLabel,
    required this.peopleLabel,
  });

  final Map<String, int> counts;
  final String? myReaction;
  final ValueChanged<String> onToggle;
  final ValueChanged<String> onShowUsers;
  final bool isOutgoing;
  final String addLabel;
  final String removeLabel;
  final String peopleLabel;

  @override
  Widget build(BuildContext context) {
    final visible = chatReactionEmojis
        .where((emoji) => (counts[emoji] ?? 0) > 0)
        .toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        children: visible.map((emoji) {
          final count = counts[emoji] ?? 0;
          final selected = myReaction == emoji;
          final action = selected ? removeLabel : addLabel;
          return Semantics(
            button: true,
            selected: selected,
            label: '$action $emoji, $peopleLabel $count',
            onLongPressHint: peopleLabel,
            child: Material(
              color: selected
                  ? AppColors.pointColor.withValues(alpha: .12)
                  : (isOutgoing
                      ? Colors.white.withValues(alpha: .12)
                      : const Color(0x0D344054)),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => onToggle(emoji),
                onLongPress: () => onShowUsers(emoji),
                borderRadius: BorderRadius.circular(14),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 30),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ChatReactionIcon(emoji, size: 17),
                        const SizedBox(width: 4),
                        Text(
                          '$count',
                          style: TextStyle(
                            fontFamily: uiFontFamily(context, 'Inter'),
                            fontFamilyFallback: const ['NotoSansKR'],
                            fontSize: 11.5,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w600,
                            color: isOutgoing
                                ? Colors.white
                                : const Color(0xFF344054),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
