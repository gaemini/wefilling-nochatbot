// lib/widgets/profile_action_buttons.dart
// 프로필 액션 버튼 컴포넌트
// 프로필 편집, 팔로우, 메시지, 공유 등의 액션 버튼 제공
// 접근성 지원 (최소 48dp 터치 타깃)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/feature_flag_service.dart';

class ProfileActionButtons extends StatelessWidget {
  final bool isOwnProfile;
  final bool isFollowing;
  final VoidCallback? onEditProfile;
  final VoidCallback? onFollow;
  final VoidCallback? onUnfollow;
  final VoidCallback? onMessage;
  final VoidCallback? onShare;
  final VoidCallback? onMoreActions;

  const ProfileActionButtons({
    Key? key,
    required this.isOwnProfile,
    this.isFollowing = false,
    this.onEditProfile,
    this.onFollow,
    this.onUnfollow,
    this.onMessage,
    this.onShare,
    this.onMoreActions,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Feature Flag 체크
    if (!FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: isOwnProfile ? _buildOwnProfileButtons(context) : _buildOtherProfileButtons(context),
    );
  }

  /// 본인 프로필 버튼들
  Widget _buildOwnProfileButtons(BuildContext context) {
    return Row(
      children: [
        // 프로필 편집 버튼
        Expanded(
          flex: 3,
          child: _buildActionButton(
            context,
            label: '프로필 편집',
            icon: Icons.edit_outlined,
            onTap: onEditProfile,
            isPrimary: false,
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 공유 버튼
        Expanded(
          flex: 1,
          child: _buildIconButton(
            context,
            icon: Icons.share_outlined,
            onTap: onShare,
            semanticLabel: '프로필 공유',
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 더보기 버튼
        Expanded(
          flex: 1,
          child: _buildIconButton(
            context,
            icon: Icons.more_horiz,
            onTap: onMoreActions,
            semanticLabel: '더보기 옵션',
          ),
        ),
      ],
    );
  }

  /// 다른 사용자 프로필 버튼들
  Widget _buildOtherProfileButtons(BuildContext context) {
    return Row(
      children: [
        // 팔로우/언팔로우 버튼
        Expanded(
          flex: 2,
          child: _buildActionButton(
            context,
            label: isFollowing ? '팔로잉' : '팔로우',
            icon: isFollowing ? Icons.person_remove_outlined : Icons.person_add_outlined,
            onTap: isFollowing ? onUnfollow : onFollow,
            isPrimary: !isFollowing,
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 메시지 버튼
        Expanded(
          flex: 2,
          child: _buildActionButton(
            context,
            label: '메시지',
            icon: Icons.message_outlined,
            onTap: onMessage,
            isPrimary: false,
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 공유 버튼
        Expanded(
          flex: 1,
          child: _buildIconButton(
            context,
            icon: Icons.share_outlined,
            onTap: onShare,
            semanticLabel: '프로필 공유',
          ),
        ),
        
        const SizedBox(width: 8),
        
        // 더보기 버튼
        Expanded(
          flex: 1,
          child: _buildIconButton(
            context,
            icon: Icons.more_horiz,
            onTap: onMoreActions,
            semanticLabel: '더보기 옵션',
          ),
        ),
      ],
    );
  }

  /// 액션 버튼 (텍스트 + 아이콘)
  Widget _buildActionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback? onTap,
    required bool isPrimary,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 48, // 최소 48dp 터치 타깃
      child: isPrimary
          ? ElevatedButton.icon(
              onPressed: () {
                _handleButtonTap(onTap);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          : OutlinedButton.icon(
              onPressed: () {
                _handleButtonTap(onTap);
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: colorScheme.onSurface,
                side: BorderSide(
                  color: colorScheme.outline,
                  width: 1,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: Icon(icon, size: 18),
              label: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
    );
  }

  /// 아이콘 버튼 (아이콘만)
  Widget _buildIconButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onTap,
    required String semanticLabel,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SizedBox(
      height: 48, // 최소 48dp 터치 타깃
      width: 48,
      child: OutlinedButton(
        onPressed: () {
          _handleButtonTap(onTap);
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: colorScheme.onSurface,
          side: BorderSide(
            color: colorScheme.outline,
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Semantics(
          label: semanticLabel,
          button: true,
          child: Icon(
            icon,
            size: 20,
          ),
        ),
      ),
    );
  }

  /// 버튼 탭 처리 (햅틱 피드백 포함)
  void _handleButtonTap(VoidCallback? onTap) {
    if (onTap != null) {
      // 햅틱 피드백
      HapticFeedback.lightImpact();
      onTap();
    }
  }
}

/// 프로필 더보기 액션 시트
class ProfileMoreActionsSheet extends StatelessWidget {
  final bool isOwnProfile;
  final VoidCallback? onBlock;
  final VoidCallback? onReport;
  final VoidCallback? onCopyLink;
  final VoidCallback? onSettings;

  const ProfileMoreActionsSheet({
    Key? key,
    required this.isOwnProfile,
    this.onBlock,
    this.onReport,
    this.onCopyLink,
    this.onSettings,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들바
          Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 액션 리스트
          ..._buildActionItems(context),
        ],
      ),
    );
  }

  List<Widget> _buildActionItems(BuildContext context) {
    final theme = Theme.of(context);
    final items = <Widget>[];

    // 공통 액션
    items.add(_buildActionItem(
      context,
      icon: Icons.link,
      title: '링크 복사',
      onTap: onCopyLink,
    ));

    if (isOwnProfile) {
      // 본인 프로필 액션
      items.add(_buildActionItem(
        context,
        icon: Icons.settings_outlined,
        title: '설정',
        onTap: onSettings,
      ));
    } else {
      // 다른 사용자 프로필 액션
      items.add(_buildActionItem(
        context,
        icon: Icons.block_outlined,
        title: '차단',
        onTap: onBlock,
        isDestructive: true,
      ));
      
      items.add(_buildActionItem(
        context,
        icon: Icons.report_outlined,
        title: '신고',
        onTap: onReport,
        isDestructive: true,
      ));
    }

    return items;
  }

  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback? onTap,
    bool isDestructive = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? colorScheme.error : colorScheme.onSurface,
      ),
      title: Text(
        title,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isDestructive ? colorScheme.error : colorScheme.onSurface,
        ),
      ),
      onTap: () {
        Navigator.pop(context);
        HapticFeedback.lightImpact();
        onTap?.call();
      },
    );
  }

  /// 액션 시트 표시
  static void show(
    BuildContext context, {
    required bool isOwnProfile,
    VoidCallback? onBlock,
    VoidCallback? onReport,
    VoidCallback? onCopyLink,
    VoidCallback? onSettings,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => ProfileMoreActionsSheet(
        isOwnProfile: isOwnProfile,
        onBlock: onBlock,
        onReport: onReport,
        onCopyLink: onCopyLink,
        onSettings: onSettings,
      ),
    );
  }
}
