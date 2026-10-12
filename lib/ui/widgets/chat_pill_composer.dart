// lib/ui/widgets/chat_pill_composer.dart
// 스낵챗·DM 공용 입력창: 화면 아래에 떠 있는 어두운 알약 하나.
//   비어 있을 때: [카메라] 입력 [사진] [+]
//   글이 있을 때: [카메라] 입력 [전송]
// 입력 필드는 각 화면이 기존 설정(멘션·GIF·maxLength 등) 그대로 만들어 넘긴다.

import 'package:flutter/material.dart';

const Color chatComposerBackground = Color(0xFF252629);
const Color chatComposerAccent = Color(0xFF2C6BC0);
const Color chatComposerPlaceholder = Color(0xFF8A8D93);

class ChatPillComposer extends StatelessWidget {
  const ChatPillComposer({
    super.key,
    required this.textField,
    required this.showSend,
    required this.canSend,
    this.enabled = true,
    this.onCamera,
    this.onGallery,
    this.onAttach,
    this.onSend,
    this.attachIcon = Icons.add_circle_outline_rounded,
    required this.cameraLabel,
    required this.galleryLabel,
    required this.attachLabel,
    required this.sendLabel,
  });

  final Widget textField;

  /// true면 [전송], false면 [사진][+]를 보인다.
  final bool showSend;

  /// 전송 버튼 활성(각 화면의 기존 조건).
  final bool canSend;

  /// false면 알약 전체를 0.45로 흐리게 하고 모든 버튼을 막는다.
  final bool enabled;
  final VoidCallback? onCamera;
  final VoidCallback? onGallery;
  final VoidCallback? onAttach;
  final VoidCallback? onSend;

  /// 오른쪽 첨부 버튼 아이콘(DM은 파일 첨부만 있어 클립 아이콘).
  final IconData attachIcon;
  final String cameraLabel;
  final String galleryLabel;
  final String attachLabel;
  final String sendLabel;

  static const double minHeight = 52;
  static const double radius = 26;
  static const double button = 40;
  static const double touch = 44;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 120);

    final trailing = showSend
        ? _CircleButton(
            key: const ValueKey('chat-composer-send'),
            label: sendLabel,
            icon: Icons.arrow_upward_rounded,
            iconSize: 20,
            filled: true,
            onTap: enabled && canSend ? onSend : null,
          )
        : Row(
            key: const ValueKey('chat-composer-tools'),
            mainAxisSize: MainAxisSize.min,
            children: [
              _CircleButton(
                key: const ValueKey('chat-composer-gallery'),
                label: galleryLabel,
                icon: Icons.photo_outlined,
                iconSize: 24,
                onTap: enabled ? onGallery : null,
              ),
              _CircleButton(
                key: const ValueKey('chat-composer-attach'),
                label: attachLabel,
                icon: attachIcon,
                iconSize: 24,
                onTap: enabled ? onAttach : null,
              ),
            ],
          );

    return Opacity(
      opacity: enabled ? 1 : .45,
      child: Container(
        key: const ValueKey('chat-composer-pill'),
        constraints: const BoxConstraints(minHeight: minHeight),
        // 안쪽 여백 6에서 버튼 터치 상자(44)가 위아래로 2씩 들어가도록 4를 쓴다.
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: chatComposerBackground,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Row(
          // 여러 줄이면 알약이 위로 커지고 버튼은 아래에 붙는다.
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _CircleButton(
              key: const ValueKey('chat-composer-camera'),
              label: cameraLabel,
              icon: Icons.photo_camera_rounded,
              iconSize: 20,
              filled: true,
              onTap: enabled ? onCamera : null,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: touch),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: textField,
                  ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: duration,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .85, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: trailing,
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    super.key,
    required this.label,
    required this.icon,
    required this.iconSize,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final double iconSize;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: ChatPillComposer.touch / 2,
          child: SizedBox.square(
            dimension: ChatPillComposer.touch,
            child: Center(
              child: Container(
                width: ChatPillComposer.button,
                height: ChatPillComposer.button,
                decoration: filled
                    ? const BoxDecoration(
                        color: chatComposerAccent,
                        shape: BoxShape.circle,
                      )
                    : null,
                child: Icon(icon, size: iconSize, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
