// lib/ui/widgets/empty_state.dart
// 콘텐츠 없음 상태에서 사용자 이탈을 줄이고 다음 행동을 유도하는 위젯
// 로고 스타일 일러스트 + 친절한 문구 + 주요 CTA 버튼

import 'package:flutter/material.dart';
import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';

/// 2024-2025 트렌드 기반 빈 상태 위젯
///
/// ✨ 새로운 특징:
/// - Vibrant gradient 아이콘 배경
/// - Modern typography with enhanced spacing
/// - Dynamic CTA buttons with gradients
/// - Gen Z 친화적 micro-interactions
/// - Enhanced visual hierarchy
class AppEmptyState extends StatelessWidget {
  /// 표시할 아이콘 (로고 스타일)
  final IconData icon;

  /// 메인 제목
  final String title;

  /// 설명 텍스트
  final String description;

  /// CTA 버튼 텍스트
  final String? ctaText;

  /// CTA 버튼 클릭 콜백
  final VoidCallback? onCtaPressed;

  /// CTA 버튼 아이콘
  final IconData? ctaIcon;

  /// 보조 액션 버튼 텍스트
  final String? secondaryCtaText;

  /// 보조 액션 버튼 클릭 콜백
  final VoidCallback? onSecondaryCtaPressed;

  /// 커스텀 일러스트 위젯
  final Widget? illustration;

  /// 배경색
  final Color? backgroundColor;

  /// 패딩
  final EdgeInsets padding;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.ctaText,
    this.onCtaPressed,
    this.ctaIcon,
    this.secondaryCtaText,
    this.onSecondaryCtaPressed,
    this.illustration,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(DesignTokens.s24),
  });

  /// 모임이 없을 때 표시하는 빈 상태 (프리셋)
  factory AppEmptyState.noMeetups({required BuildContext context, VoidCallback? onCreateMeetup}) {
    return AppEmptyState(
      icon: IconStyles.groups,
      title: AppLocalizations.of(context)!.wefillingMeaning,
      description: AppLocalizations.of(context)!.wefillingExplanation,
      // ctaText 및 onCtaPressed 제거하여 "Create Your First Meetup" 버튼 숨김
      secondaryCtaText: AppLocalizations.of(context)!.searchMeetups,
      // 위필링 로고를 표시
      illustration: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Image.asset(
            'assets/images/wefilling_logo.png',
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }

  /// 게시글이 없을 때 표시하는 빈 상태 (프리셋)
  factory AppEmptyState.noPosts({VoidCallback? onCreatePost}) {
    return AppEmptyState(
      icon: IconStyles.article,
      title: '첫 번째 이야기를 들려주세요',
      description: '당신의 경험과 생각을 다른 사람들과 나누어보세요.\n소중한 이야기가 누군가에게는 큰 도움이 될 수 있어요.',
      ctaText: '첫 글 쓰기',
      ctaIcon: IconStyles.edit,
      onCtaPressed: onCreatePost,
      secondaryCtaText: '인기 글 보기',
    );
  }

  /// 친구가 없을 때 표시하는 빈 상태 (프리셋)
  factory AppEmptyState.noFriends({required BuildContext context, VoidCallback? onSearchFriends}) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: IconStyles.group,
      title: l10n?.findFriends ?? "",
      description: l10n?.makeFriendsWithSameInterests ?? "",
      ctaText: l10n?.findFriendsAction ?? "",
      ctaIcon: IconStyles.search,
      onCtaPressed: onSearchFriends,
      secondaryCtaText: l10n?.viewRecommendedFriends ?? "",
    );
  }

  /// 검색 결과가 없을 때 표시하는 빈 상태 (프리셋)
  factory AppEmptyState.noSearchResults({
    required BuildContext context,
    String? searchQuery,
    VoidCallback? onClearSearch,
  }) {
    final l10n = AppLocalizations.of(context);
    return AppEmptyState(
      icon: Icons.search_off_outlined,
      title: l10n?.noSearchResults ?? "",
      description:
          searchQuery != null
              ? '\'$searchQuery\' ${l10n?.tryDifferentKeyword ?? ""}'
              : l10n?.tryDifferentKeyword ?? "",
      ctaText: l10n?.clearSearchQuery ?? "",
      ctaIcon: Icons.clear,
      onCtaPressed: onClearSearch,
    );
  }

  /// 네트워크 오류 상태 (프리셋)
  factory AppEmptyState.networkError({VoidCallback? onRetry}) {
    return AppEmptyState(
      icon: Icons.wifi_off_outlined,
      title: '연결에 문제가 있어요',
      description: '인터넷 연결을 확인하고\n다시 시도해주세요.',
      ctaText: '다시 시도',
      ctaIcon: Icons.refresh,
      onCtaPressed: onRetry,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      color: backgroundColor,
      child: SingleChildScrollView(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 일러스트 또는 아이콘
            _buildIllustration(colorScheme),

            const SizedBox(height: DesignTokens.s24),

            // 제목
            Text(
              title,
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: DesignTokens.s12),

            // 설명
            Text(
              description,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: DesignTokens.s24),

            // CTA 버튼들
            _buildActionButtons(theme, colorScheme),
          ],
        ),
      ),
    );
  }

  /// 일러스트 또는 아이콘 빌드
  Widget _buildIllustration(ColorScheme colorScheme) {
    if (illustration != null) {
      return illustration!;
    }

      // 일관된 디자인의 아이콘 컨테이너
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: BrandColors.primary.withOpacity(0.1),
        shape: BoxShape.circle,
        border: Border.all(
          color: BrandColors.primary.withOpacity(0.2),
          width: 2,
        ),
      ),
      child: Icon(icon, size: 48, color: BrandColors.primary),
    );
  }

  /// 액션 버튼들 빌드
  Widget _buildActionButtons(ThemeData theme, ColorScheme colorScheme) {
    final buttons = <Widget>[];

    // 주요 CTA 버튼
    if (ctaText != null && onCtaPressed != null) {
      buttons.add(
        ElevatedButton.icon(
          onPressed: onCtaPressed,
          icon:
              ctaIcon != null
                  ? Icon(ctaIcon!, size: 20)
                  : const SizedBox.shrink(),
          label: Text(ctaText!),
          style: ComponentStyles.primaryButton,
        ),
      );
    }

    // 보조 CTA 버튼
    if (secondaryCtaText != null && onSecondaryCtaPressed != null) {
      if (buttons.isNotEmpty) {
        buttons.add(const SizedBox(height: DesignTokens.s12));
      }

      buttons.add(
        OutlinedButton(
          onPressed: onSecondaryCtaPressed,
          style: ComponentStyles.secondaryButton,
          child: Text(secondaryCtaText!),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: buttons);
  }
}

/// 작은 빈 상태 위젯 (인라인 사용)
class AppEmptyStateCompact extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionText;
  final VoidCallback? onActionPressed;

  const AppEmptyStateCompact({
    super.key,
    required this.icon,
    required this.message,
    this.actionText,
    this.onActionPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(DesignTokens.s16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 32, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: DesignTokens.s8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          if (actionText != null && onActionPressed != null) ...[
            const SizedBox(height: DesignTokens.s12),
            TextButton(onPressed: onActionPressed, child: Text(actionText!)),
          ],
        ],
      ),
    );
  }
}

/// 에러 상태를 표시하는 위젯
class AppErrorState extends StatelessWidget {
  final String title;
  final String description;
  final VoidCallback? onRetry;
  final String? retryText;
  final IconData icon;

  const AppErrorState({
    super.key,
    this.title = '문제가 발생했어요',
    this.description = '잠시 후 다시 시도해주세요.',
    this.onRetry,
    this.retryText = '다시 시도',
    this.icon = Icons.error_outline,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.s24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 에러 아이콘
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.error.withOpacity(0.1),
                  colorScheme.error.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: colorScheme.error),
          ),

          const SizedBox(height: DesignTokens.s24),

          // 제목
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: DesignTokens.s12),

          // 설명
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          if (onRetry != null) ...[
            const SizedBox(height: DesignTokens.s24),

            // 재시도 버튼
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 20),
              label: Text(retryText!),
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                padding: const EdgeInsets.symmetric(
                  horizontal: DesignTokens.s20,
                  vertical: DesignTokens.s12,
                ),
                minimumSize: const Size(140, 48),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 권한 요청 상태를 표시하는 위젯
class AppPermissionState extends StatelessWidget {
  final String title;
  final String description;
  final String permissionText;
  final VoidCallback onRequestPermission;
  final IconData icon;

  const AppPermissionState({
    super.key,
    required this.title,
    required this.description,
    required this.permissionText,
    required this.onRequestPermission,
    this.icon = Icons.security,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(DesignTokens.s24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 권한 아이콘
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.secondary.withOpacity(0.1),
                  colorScheme.secondary.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: colorScheme.secondary),
          ),

          const SizedBox(height: DesignTokens.s24),

          // 제목
          Text(
            title,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: DesignTokens.s12),

          // 설명
          Text(
            description,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: DesignTokens.s24),

          // 권한 요청 버튼
          FilledButton.icon(
            onPressed: onRequestPermission,
            icon: const Icon(Icons.check_circle, size: 20),
            label: Text(permissionText),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.secondary,
              foregroundColor: colorScheme.onSecondary,
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.s20,
                vertical: DesignTokens.s12,
              ),
              minimumSize: const Size(160, 48),
            ),
          ),
        ],
      ),
    );
  }
}
