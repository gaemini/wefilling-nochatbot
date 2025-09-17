// lib/ui/widgets/optimized_meetup_card.dart
// 성능 최적화된 모임 카드 위젯
// const 생성자, 메모이제이션, 이미지 최적화

import 'package:flutter/material.dart';
import '../../models/meetup.dart';
import '../../utils/image_utils.dart';
import '../../design/tokens.dart';

/// 최적화된 모임 카드
class OptimizedMeetupCard extends StatelessWidget {
  final Meetup meetup;
  final int index;
  final VoidCallback onTap;
  final bool preloadImage;

  const OptimizedMeetupCard({
    super.key,
    required this.meetup,
    required this.index,
    required this.onTap,
    this.preloadImage = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline.withOpacity(0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 카테고리 뱃지
              _buildCategoryBadge(meetup.category, colorScheme),

              const SizedBox(height: 12),

              // 모임 제목
              Text(
                meetup.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              const SizedBox(height: 8),

              // 모임 설명
              if (meetup.description.isNotEmpty) ...[
                Text(
                  meetup.description,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
              ],

              // 모임 정보 (날짜, 시간, 장소)
              _buildMeetupInfo(meetup, theme, colorScheme),

              const SizedBox(height: 12),

              // 참가자 정보
              _buildParticipantInfo(meetup, theme, colorScheme),

              // 모임 이미지 (있는 경우만 표시)
              if (_hasImage(meetup)) ...[
                const SizedBox(height: 12),
                _buildMeetupImage(meetup),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 카테고리 뱃지 빌드
  Widget _buildCategoryBadge(String category, ColorScheme colorScheme) {
    Color badgeColor;
    switch (category) {
      case '스터디':
        badgeColor = Colors.blue.shade700;
        break;
      case '식사':
        badgeColor = Colors.orange.shade700;
        break;
      case '취미':
        badgeColor = Colors.green.shade700;
        break;
      case '문화':
        badgeColor = Colors.purple.shade700;
        break;
      default:
        badgeColor = colorScheme.primary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.3), width: 1),
      ),
      child: Text(
        category,
        style: TextStyle(
          color: badgeColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 모임 정보 빌드 (날짜, 시간, 장소)
  Widget _buildMeetupInfo(
    Meetup meetup,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        // 날짜와 시간
        _buildInfoRow(
          icon: Icons.schedule_outlined,
          text: '${meetup.date} ${meetup.time}',
          theme: theme,
          colorScheme: colorScheme,
        ),

        const SizedBox(height: 6),

        // 장소
        _buildInfoRow(
          icon: Icons.location_on_outlined,
          text: meetup.location,
          theme: theme,
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  /// 정보 행 빌드
  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  /// 참가자 정보 빌드
  Widget _buildParticipantInfo(
    Meetup meetup,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    // 안전한 참가자 정보 추출
    final current = meetup.currentParticipants;
    final max = meetup.maxParticipants;

    return Row(
      children: [
        // 작성자 아바타 - 기본 아이콘 사용
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: colorScheme.surfaceVariant,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.person_outline,
            size: 16,
            color: colorScheme.onSurfaceVariant,
            ),
          ),

        const SizedBox(width: 8),

        // 참가자 수 (안전한 표시)
        if (max > 0)
          Text(
            '$current/$max명',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),

        const Spacer(),

        // 모집 상태
        _buildStatusChip(current, max, theme, colorScheme),
      ],
    );
  }

  /// 참가자 아바타들 빌드
  Widget _buildParticipantAvatars(
    List<dynamic> participants,
    ColorScheme colorScheme,
  ) {
    const maxAvatars = 3;
    final displayCount =
        participants.length > maxAvatars ? maxAvatars : participants.length;

    if (participants.isEmpty) {
      return Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.person_outline,
          size: 16,
          color: colorScheme.onSurfaceVariant,
        ),
      );
    }

    return SizedBox(
      width: displayCount * 20.0 + 4,
      height: 24,
      child: Stack(
        children: [
          for (int i = 0; i < displayCount; i++)
            Positioned(
              left: i * 16.0,
              child: OptimizedAvatarImage(
                imageUrl: participants[i]['profileImageUrl'],
                size: 24,
                fallbackText: participants[i]['displayName'] ?? '',
                preload: index < 3, // 상위 3개 카드만 프리로드
              ),
            ),

          // 더 많은 참가자가 있는 경우 "+N" 표시
          if (participants.length > maxAvatars)
            Positioned(
              left: maxAvatars * 16.0,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.primary.withOpacity(0.3),
                    width: 1,
                  ),
                ),
                child: Center(
                  child: Text(
                    '+${participants.length - maxAvatars}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 모집 상태 칩 빌드
  Widget _buildStatusChip(
    int current,
    int max,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (max == 0) return const SizedBox.shrink(); // 최대값이 없으면 표시하지 않음

    final isOpen = current < max;
    final statusColor = isOpen ? Colors.green : Colors.red;
    final statusText = isOpen ? '모집중' : '마감';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        statusText,
        style: theme.textTheme.labelSmall?.copyWith(
          color: statusColor,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 이미지가 있는지 확인
  bool _hasImage(Meetup meetup) {
    return (meetup.imageUrl?.isNotEmpty == true) ||
           (meetup.thumbnailImageUrl?.isNotEmpty == true);
  }

  /// 모임 이미지 빌드 (조건부 크기 조정)
  Widget _buildMeetupImage(Meetup meetup) {
    // 우선순위: imageUrl > thumbnailImageUrl
    final String? imageUrl = meetup.imageUrl?.isNotEmpty == true 
        ? meetup.imageUrl 
        : meetup.thumbnailImageUrl?.isNotEmpty == true 
            ? meetup.thumbnailImageUrl 
            : null;
    
    if (imageUrl == null) return const SizedBox.shrink();

    // 리스트에서는 작은 크기로, 상세 페이지에서는 큰 크기로 표시
    const double imageHeight = 120; // 리스트에서는 120px로 축소
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: OptimizedNetworkImage(
        imageUrl: imageUrl,
        targetSize: const Size(double.infinity, imageHeight),
        fit: BoxFit.cover,
        preload: index < 3, // 상위 3개 카드만 프리로드
        lazy: index >= 3, // 하위 카드들은 지연 로딩
        semanticLabel: '모임 이미지',
        placeholder: Container(
          height: imageHeight,
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Icon(Icons.image_outlined, size: 32, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is OptimizedMeetupCard &&
        other.meetup.id == meetup.id &&
        other.index == index;
  }

  @override
  int get hashCode => Object.hash(meetup.id, index);
}
