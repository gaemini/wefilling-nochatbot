// lib/examples/glassmorphism_examples.dart
// 2024-2025 트렌드 Glassmorphism 스타일 사용 예제
// 개발자들이 쉽게 적용할 수 있도록 하는 가이드

import 'package:flutter/material.dart';
import '../ui/widgets/glassmorphism_container.dart';
import '../widgets/meetup_card.dart';
import '../ui/widgets/optimized_post_card.dart';
import '../constants/app_constants.dart';

/// Glassmorphism 스타일 사용 예제 모음
class GlassmorphismExamples {
  
  /// 기본 Glassmorphism 컨테이너 사용 예제
  static Widget basicGlassmorphismExample() {
    return GlassmorphismContainer(
      width: 300,
      height: 200,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '✨ Glassmorphism Card',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '2024-2025 트렌드 글래스모피즘 효과가 적용된 모던한 카드입니다.',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Primary 스타일 Glassmorphism 예제
  static Widget primaryGlassmorphismExample() {
    return GlassmorphismContainer.primary(
      width: 300,
      height: 150,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            Icons.star_rounded,
            color: AppTheme.primary,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Primary Style',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Indigo 글래스모피즘 스타일',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Secondary 스타일 Glassmorphism 예제
  static Widget secondaryGlassmorphismExample() {
    return GlassmorphismContainer.secondary(
      width: 300,
      height: 150,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            Icons.favorite_rounded,
            color: AppTheme.secondary,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Secondary Style',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Pink 글래스모피즘 스타일',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Emerald 스타일 Glassmorphism 예제
  static Widget emeraldGlassmorphismExample() {
    return GlassmorphismContainer.emerald(
      width: 300,
      height: 150,
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(
            Icons.eco_rounded,
            color: AppTheme.accentEmerald,
            size: 32,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Emerald Style',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  'Emerald 글래스모피즘 스타일',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 클릭 가능한 Glassmorphism 카드 예제
  static Widget interactiveGlassmorphismExample() {
    return GlassmorphismContainer(
      width: 300,
      height: 120,
      padding: const EdgeInsets.all(20),
      onTap: () {
        // 클릭 이벤트 처리
        print('Glassmorphism 카드가 클릭되었습니다!');
      },
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.touch_app_rounded,
              color: AppTheme.primary,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              '클릭해보세요!',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Glassmorphism Card 위젯 사용 예제
  static Widget glassmorphismCardExample() {
    return GlassmorphismCard(
      style: 'primary',
      onTap: () {
        print('Glassmorphism Card 클릭!');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.primarySubtle,
                child: Icon(
                  Icons.person_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Glassmorphism Card',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    Text(
                      '2024-2025 트렌드 스타일',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'BackdropFilter를 활용한 모던한 글래스 효과로 '
            '사용자 경험을 한층 업그레이드했습니다.',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  /// 기존 컴포넌트에서 Glassmorphism 사용 예제
  static Widget existingComponentGlassmorphismExample() {
    // 예제용 더미 데이터는 실제 사용 시 제거 필요
    return Column(
      children: [
        Text(
          '기존 컴포넌트에 Glassmorphism 적용 예제',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 20),
        
        // 기존 스타일
        Text(
          '기존 스타일:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            'MeetupCard() // 기존 스타일',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: AppTheme.textSecondary,
            ),
          ),
        ),
        
        const SizedBox(height: 20),
        
        // Glassmorphism 스타일
        Text(
          'Glassmorphism 스타일:',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            'MeetupCard.glassmorphism() // 글래스모피즘 스타일',
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: AppTheme.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Glassmorphism 사용법 가이드
class GlassmorphismUsageGuide {
  static const String basicUsage = '''
// 기본 사용법
GlassmorphismContainer(
  padding: const EdgeInsets.all(20),
  child: Text('Glassmorphism 효과'),
)

// 스타일별 사용법
GlassmorphismContainer.primary()   // Indigo 글래스모피즘
GlassmorphismContainer.secondary() // Pink 글래스모피즘  
GlassmorphismContainer.emerald()   // Emerald 글래스모피즘

// 기존 컴포넌트에 적용
MeetupCard.glassmorphism()         // 모임 카드
OptimizedPostCard.glassmorphism()  // 게시글 카드
''';

  static const String advancedUsage = '''
// 고급 사용법
GlassmorphismContainer(
  width: 300,
  height: 200,
  blurStrength: 15.0,           // 블러 강도 조정
  style: 'primary',             // 스타일 지정
  onTap: () => print('클릭!'),  // 클릭 이벤트
  borderRadius: BorderRadius.circular(20), // 커스텀 반지름
  child: // 콘텐츠
)
''';
}

