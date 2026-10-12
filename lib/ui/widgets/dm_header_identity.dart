// lib/ui/widgets/dm_header_identity.dart
// DM 상단바의 신원 영역(사진 + 이름 + 보조 줄). 세 갈래(로딩·익명 게시글·일반)가 함께 쓴다.

import 'package:flutter/material.dart';

import '../../l10n/ui_locale.dart';
import 'motion_press.dart';

/// DM 상단바 신원 영역: 사진 36 + 이름(16/21 w600) + 보조 줄(12/16 #707070).
/// 사진과 이름을 하나의 버튼으로 묶어 프로필을 연다(익명·탈퇴면 비활성).
class DmHeaderIdentity extends StatelessWidget {
  const DmHeaderIdentity({
    super.key,
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.semanticsLabel,
    required this.onTap,
    this.showSkeleton = false,
  });

  final Widget avatar;
  final String title;
  final String? subtitle;
  final String semanticsLabel;
  final VoidCallback? onTap;

  /// 이름이 준비되기 전(플리커 방지) 이름 자리 스켈레톤.
  final bool showSkeleton;

  @override
  Widget build(BuildContext context) {
    final zh = isChineseUi(context);
    final base = TextStyle(
      fontFamily: uiFontFamily(context, 'Inter'),
      fontFamilyFallback: const ['NotoSansKR'],
    );
    final sub = subtitle?.trim() ?? '';
    final enabled = onTap != null;
    return Semantics(
      button: enabled,
      label: enabled ? semanticsLabel : null,
      child: MotionPress(
        enabled: enabled,
        pressedScale: .99,
        child: GestureDetector(
          key: const ValueKey('dm_header_identity'),
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.3,
            child: Row(
              children: [
                SizedBox.square(dimension: 36, child: avatar),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showSkeleton)
                        Container(
                          width: 120,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE5E7EB),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        )
                      else
                        Text(
                          title,
                          key: const ValueKey('dm_header_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: base.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black,
                            height: zh ? 1.35 : 21 / 16,
                          ),
                        ),
                      if (sub.isNotEmpty)
                        Text(
                          sub,
                          key: const ValueKey('dm_header_subtitle'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: base.copyWith(
                            fontSize: 12,
                            color: const Color(0xFF707070),
                            height: zh ? 1.35 : 16 / 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
