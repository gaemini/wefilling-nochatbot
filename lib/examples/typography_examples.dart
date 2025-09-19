// lib/examples/typography_examples.dart
// 2024-2025 트렌드 타이포그래피 사용 예제
// Extra Large Headlines, Dynamic sizing, Better readability

import 'package:flutter/material.dart';
import '../constants/app_constants.dart';

/// 타이포그래피 사용 예제 모음
class TypographyExamples {
  
  /// Extra Large Headlines 예제
  static Widget extraLargeHeadlineExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '2024-2025 트렌드',
          style: AppTheme.displayExtraLarge,
        ),
        const SizedBox(height: 8),
        Text(
          '큰 제목으로 강한 임팩트 전달',
          style: AppTheme.captionEmphasis,
        ),
      ],
    );
  }

  /// Dynamic Sizing 예제
  static Widget dynamicSizingExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dynamic Headlines',
          style: AppTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Improved Typography',
          style: AppTheme.headlineMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Enhanced readability with better spacing',
          style: AppTheme.titleEnhanced,
        ),
      ],
    );
  }

  /// Better Readability 예제
  static Widget betterReadabilityExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enhanced Readability',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        Text(
          '기존 16px에서 18px로 확대된 본문 텍스트는 더 나은 가독성을 제공합니다. '
          '1.6의 넉넉한 행간과 함께 장시간 읽기에도 피로감을 줄여줍니다.',
          style: AppTheme.bodyLarge,
        ),
        const SizedBox(height: 12),
        Text(
          '보조 텍스트도 16px로 확대되어 계층적 구조를 유지하면서도 '
          '가독성을 향상시켰습니다.',
          style: AppTheme.bodyMedium,
        ),
      ],
    );
  }

  /// Responsive Typography 예제
  static Widget responsiveTypographyExample(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Responsive Text',
          style: AppTheme.getResponsiveHeadlineLarge(context),
        ),
        const SizedBox(height: 16),
        Text(
          '화면 크기에 따라 자동으로 조정되는 반응형 타이포그래피입니다. '
          '작은 화면에서는 10% 축소, 큰 화면에서는 5% 확대됩니다.',
          style: AppTheme.getResponsiveBodyLarge(context),
        ),
      ],
    );
  }

  /// Gradient Text 예제
  static Widget gradientTextExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTheme.gradientText(
          text: 'Gradient Text',
          style: AppTheme.headlineLarge,
          gradient: AppTheme.primaryGradient,
        ),
        const SizedBox(height: 16),
        AppTheme.gradientText(
          text: '2024-2025 트렌드 그라디언트 텍스트',
          style: AppTheme.titleEnhanced,
          gradient: AppTheme.secondaryGradient,
        ),
      ],
    );
  }

  /// Color Headlines 예제
  static Widget colorHeadlinesExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Primary Headline',
          style: AppTheme.primaryHeadline,
        ),
        const SizedBox(height: 12),
        Text(
          'Secondary Headline',
          style: AppTheme.secondaryHeadline,
        ),
        const SizedBox(height: 12),
        Text(
          'Success Headline',
          style: AppTheme.emeraldHeadline,
        ),
      ],
    );
  }

  /// Typography Hierarchy 예제
  static Widget typographyHierarchyExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Extra Large Display',
          style: AppTheme.displayExtraLarge,
        ),
        const SizedBox(height: 16),
        Text(
          'Headline Large (32px)',
          style: AppTheme.headlineLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Headline Medium (24px)',
          style: AppTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        Text(
          'Enhanced Title (22px)',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 12),
        Text(
          'Title Medium (18px)',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Text(
          'Body Large (18px) - 향상된 가독성을 위한 크기와 행간',
          style: AppTheme.bodyLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Body Medium (16px) - 보조 정보 표시',
          style: AppTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Body Readable (17px) - 긴 텍스트를 위한 특별한 가독성',
          style: AppTheme.bodyReadable,
        ),
        const SizedBox(height: 12),
        Text(
          'Caption Emphasis (13px)',
          style: AppTheme.captionEmphasis,
        ),
        const SizedBox(height: 6),
        Text(
          'Micro Text (11px)',
          style: AppTheme.micro,
        ),
      ],
    );
  }

  /// 실제 카드에서 타이포그래피 적용 예제
  static Widget cardTypographyExample() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppTheme.backgroundGradient,
        borderRadius: BorderRadius.circular(AppTheme.radiusL),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withOpacity(0.1),
            offset: const Offset(0, 8),
            blurRadius: 24,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 카드 제목 - Enhanced Title 사용
          Text(
            '모던 타이포그래피 카드',
            style: AppTheme.titleEnhanced,
          ),
          const SizedBox(height: 8),
          
          // 메타 정보 - Caption Emphasis 사용
          Text(
            '2024년 12월 19일 • 디자인 트렌드',
            style: AppTheme.captionEmphasis,
          ),
          const SizedBox(height: 16),
          
          // 본문 - Body Large 사용
          Text(
            '2024-2025 트렌드에 맞춘 타이포그래피는 더 나은 가독성과 '
            '시각적 임팩트를 제공합니다. 18px 본문 크기와 1.6 행간으로 '
            '편안한 읽기 경험을 선사합니다.',
            style: AppTheme.bodyLarge,
          ),
          const SizedBox(height: 12),
          
          // 보조 정보 - Body Medium 사용
          Text(
            '추가 정보는 16px 크기로 계층적 구조를 유지합니다.',
            style: AppTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          
          // 액션 버튼 텍스트
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AppTheme.radiusM),
            ),
            child: Text(
              '자세히 보기',
              style: AppTheme.labelLarge.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// 타이포그래피 사용법 가이드
class TypographyUsageGuide {
  static const String basicUsage = '''
// 2024-2025 트렌드 타이포그래피 사용법

// Extra Large Headlines (40px)
Text('Hero Title', style: AppTheme.displayExtraLarge)

// Dynamic Headlines (32px, 24px)
Text('Main Title', style: AppTheme.headlineLarge)    // w800
Text('Sub Title', style: AppTheme.headlineMedium)    // w700

// Enhanced readability (18px)
Text('Body content', style: AppTheme.bodyLarge)     // 16px → 18px
Text('Secondary', style: AppTheme.bodyMedium)       // 14px → 16px

// New typography styles
Text('Card Title', style: AppTheme.titleEnhanced)   // 22px w700
Text('Long article', style: AppTheme.bodyReadable)  // 17px h1.7
Text('Emphasized', style: AppTheme.captionEmphasis) // 13px w600
Text('Legal text', style: AppTheme.micro)           // 11px
''';

  static const String responsiveUsage = '''
// 반응형 타이포그래피
Text(
  'Responsive Title',
  style: AppTheme.getResponsiveHeadlineLarge(context)
)

// 그라디언트 텍스트
AppTheme.gradientText(
  text: 'Gradient Text',
  style: AppTheme.headlineLarge,
  gradient: AppTheme.primaryGradient,
)

// 컬러 제목
Text('Primary', style: AppTheme.primaryHeadline)
Text('Secondary', style: AppTheme.secondaryHeadline)
Text('Success', style: AppTheme.emeraldHeadline)
''';

  static const String migrationGuide = '''
// 기존 → 새로운 스타일 마이그레이션

// 제목
TextStyle(fontSize: 24, fontWeight: FontWeight.w600)
↓
AppTheme.headlineMedium  // w700, 더 강한 hierarchy

// 본문
TextStyle(fontSize: 16, fontWeight: FontWeight.w400)
↓
AppTheme.bodyLarge      // 18px w500, 1.6 height

// 카드 제목
TextStyle(fontSize: 18, fontWeight: FontWeight.w600)
↓
AppTheme.titleEnhanced  // 22px w700, -0.2 spacing
''';
}

