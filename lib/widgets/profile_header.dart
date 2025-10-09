// lib/widgets/profile_header.dart
// 프로필 헤더 컴포넌트
// Avatar, 이름, 통계, 액션 버튼 포함
// Material 3 디자인 적용

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_profile.dart';
import '../services/feature_flag_service.dart';

class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final Map<String, int> stats;
  final bool isOwnProfile;
  final VoidCallback? onEditProfile;
  final VoidCallback? onFollow;
  final VoidCallback? onMessage;

  const ProfileHeader({
    Key? key,
    required this.profile,
    required this.stats,
    required this.isOwnProfile,
    this.onEditProfile,
    this.onFollow,
    this.onMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Feature Flag 체크
    if (!FeatureFlagService().isFeatureEnabled(FeatureFlagService.FEATURE_PROFILE_GRID)) {
      return Container(
        padding: const EdgeInsets.all(16),
        child: const Text(
          '프로필 그리드 기능이 비활성화되어 있습니다.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Avatar와 기본 정보
          Row(
            children: [
              // 88dp 원형 아바타
              _buildAvatar(),
              const SizedBox(width: 16),
              // 이름과 통계
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 이름 (18sp bold)
                    Text(
                      profile.displayNameOrNickname,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    
                    // 서브텍스트 (14sp muted)
                    if (profile.nationality != null && profile.nationality!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        profile.nationality!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 14,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                    
                    const SizedBox(height: 12),
                    
                    // 통계 (3칸 레이아웃)
                    _buildStats(context),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // 액션 버튼
          _buildActionButtons(context),
        ],
      ),
    );
  }

  /// 88dp 원형 아바타 구성
  Widget _buildAvatar() {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.grey.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: ClipOval(
        child: profile.hasProfileImage
            ? CachedNetworkImage(
                imageUrl: profile.photoURL!,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => _buildDefaultAvatar(),
              )
            : _buildDefaultAvatar(),
      ),
    );
  }

  /// 기본 아바타 (프로필 이미지가 없을 때)
  Widget _buildDefaultAvatar() {
    return Container(
      color: Colors.grey[200],
      child: Icon(
        Icons.person,
        size: 44,
        color: Colors.grey[400],
      ),
    );
  }

  /// 통계 표시 (posts, participationCount, writtenPosts)
  Widget _buildStats(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final statItems = [
      {'label': '게시글', 'value': stats['posts'] ?? 0},
      {'label': '참여', 'value': stats['participationCount'] ?? 0},
      {'label': '작성글', 'value': stats['writtenPosts'] ?? 0},
    ];

    return Row(
      children: statItems.map((item) {
        return Expanded(
          child: Column(
            children: [
              // 숫자 (16sp bold)
              Text(
                '${item['value']}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              
              const SizedBox(height: 2),
              
              // 라벨 (12sp muted)
              Text(
                item['label'] as String,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 12,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  /// 액션 버튼들 (프로필 편집, 팔로우, 메시지)
  Widget _buildActionButtons(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (isOwnProfile) {
      // 본인 프로필인 경우: 프로필 편집 버튼만 표시
      return SizedBox(
        width: double.infinity,
        height: 36, // 36dp 높이
        child: OutlinedButton(
          onPressed: onEditProfile,
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18), // 18dp radius
            ),
            side: BorderSide(
              color: colorScheme.outline,
              width: 1,
            ),
            minimumSize: const Size(0, 36), // 최소 터치 타깃 확보
          ),
          child: Text(
            '프로필 편집',
            style: theme.textTheme.labelMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      );
    } else {
      // 다른 사용자 프로필: 팔로우 및 메시지 버튼
      return Row(
        children: [
          // 팔로우 버튼
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: onFollow,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                  minimumSize: const Size(0, 36),
                ),
                child: Text(
                  '팔로우',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colorScheme.onPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
          
          const SizedBox(width: 8),
          
          // 메시지 버튼
          Expanded(
            flex: 1,
            child: SizedBox(
              height: 36,
              child: OutlinedButton(
                onPressed: onMessage,
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  side: BorderSide(
                    color: colorScheme.outline,
                    width: 1,
                  ),
                  minimumSize: const Size(0, 36),
                ),
                child: Icon(
                  Icons.message_outlined,
                  size: 16,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      );
    }
  }
}
