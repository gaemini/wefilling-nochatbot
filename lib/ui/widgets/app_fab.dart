// lib/ui/widgets/app_fab.dart
// 앱 전체에서 사용하는 일관된 FAB (Floating Action Button)
// 통일된 디자인 시스템 적용

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design/tokens.dart';
import '../../constants/app_constants.dart';

/// 통일된 디자인 시스템을 적용한 FAB
/// - 일관된 브랜드 컬러 사용 (Primary Blue)
/// - 통일된 아이콘 스타일 (Outlined)
/// - 간단하고 명확한 역할 정의
class AppFab extends StatelessWidget {
  /// FAB 아이콘
  final IconData icon;

  /// 클릭 콜백
  final VoidCallback? onPressed;

  /// 툴팁 텍스트
  final String? tooltip;

  /// 스크린 리더용 시맨틱 라벨 (필수)
  final String semanticLabel;

  /// 확장형 FAB일 때 표시할 라벨
  final String? label;

  /// 히어로 태그 (페이지 전환 시 애니메이션용)
  final Object? heroTag;

  /// 비활성화 여부
  final bool enabled;

  /// 미니 FAB 여부
  final bool mini;

  /// 확장형 FAB 여부
  final bool extended;

  const AppFab({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.tooltip,
    this.label,
    this.heroTag,
    this.enabled = true,
    this.mini = false,
    this.extended = false,
  }) : assert(!extended || label != null, 'Extended FAB requires a label');

  /// 글쓰기 FAB
  factory AppFab.write({
    required VoidCallback onPressed,
    Object? heroTag,
    bool enabled = true,
  }) {
    return AppFab(
      // 게시글 작성 버튼은 "+" 형태로 (요구사항)
      icon: IconStyles.add,
      onPressed: onPressed,
      semanticLabel: '새 글 작성하기',
      tooltip: '글쓰기',
      heroTag: heroTag ?? 'write_fab',
      enabled: enabled,
    );
  }

  /// 새 모임 만들기 FAB
  factory AppFab.createMeetup({
    required VoidCallback onPressed,
    Object? heroTag,
    bool enabled = true,
  }) {
    return AppFab(
      icon: IconStyles.add,
      onPressed: onPressed,
      semanticLabel: '새 모임 만들기',
      tooltip: '모임 만들기',
      heroTag: heroTag ?? 'create_meetup_fab',
      enabled: enabled,
    );
  }

  /// 친구 추가 FAB
  factory AppFab.addFriend({
    required VoidCallback onPressed,
    Object? heroTag,
    bool enabled = true,
  }) {
    return AppFab(
      icon: IconStyles.add,
      onPressed: onPressed,
      semanticLabel: '친구 추가하기',
      tooltip: '친구 추가',
      heroTag: heroTag ?? 'add_friend_fab',
      enabled: enabled,
    );
  }

  /// 확장형 FAB
  factory AppFab.extended({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required String semanticLabel,
    Object? heroTag,
    bool enabled = true,
  }) {
    return AppFab(
      icon: icon,
      label: label,
      onPressed: onPressed,
      semanticLabel: semanticLabel,
      heroTag: heroTag,
      enabled: enabled,
      extended: true,
    );
  }

  void _handleTap() {
    if (!enabled || onPressed == null) return;

    // 햅틱 피드백
    HapticFeedback.lightImpact();

    // 콜백 실행
    onPressed!();
  }

  @override
  Widget build(BuildContext context) {
    if (extended) {
      // 확장형 FAB
      return FloatingActionButton.extended(
        onPressed: enabled ? _handleTap : null,
        icon: Icon(
          icon,
          size: DesignTokens.icon,
        ),
        label: Text(
          label!,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: AppColors.pointColor,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevation3,
        heroTag: heroTag,
        tooltip: tooltip,
        shape: RoundedRectangleBorder(
          borderRadius: DesignTokens.radiusL,
        ),
      );
    } else {
      // 일반 FAB
      return FloatingActionButton(
        onPressed: enabled ? _handleTap : null,
        backgroundColor: AppColors.pointColor,
        foregroundColor: Colors.white,
        elevation: DesignTokens.elevation3,
        mini: mini,
        heroTag: heroTag,
        tooltip: tooltip,
        shape: const CircleBorder(),
        child: Icon(
          icon,
          size: mini ? 20 : DesignTokens.icon,
        ),
      );
    }
  }
}