// lib/examples/animation_examples.dart
// 2024-2025 트렌드 Micro-interactions & Smooth Animations 사용 예제
// 버튼, 카드, 페이지 전환 애니메이션 가이드

import 'package:flutter/material.dart';
import '../ui/widgets/animated_button.dart';
import '../ui/widgets/animated_card.dart';
import '../ui/animations/page_transitions.dart';
import '../constants/app_constants.dart';

/// 애니메이션 사용 예제 모음
class AnimationExamples {
  
  /// 애니메이션 버튼 예제
  static Widget animatedButtonsExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '✨ 2024-2025 트렌드 애니메이션 버튼',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 20),
        
        // Primary 버튼
        AnimatedButton.primary(
          text: 'Primary Button',
          icon: Icons.star_rounded,
          onPressed: () {
            print('Primary 버튼 클릭!');
          },
        ),
        const SizedBox(height: 16),
        
        // Secondary 버튼
        AnimatedButton.secondary(
          text: 'Secondary Button',
          icon: Icons.favorite_rounded,
          onPressed: () {
            print('Secondary 버튼 클릭!');
          },
        ),
        const SizedBox(height: 16),
        
        // Success 버튼 (Emerald)
        AnimatedButton.success(
          text: 'Success Action',
          icon: Icons.check_circle_rounded,
          onPressed: () {
            print('Success 액션 실행!');
          },
        ),
        const SizedBox(height: 16),
        
        // 아웃라인 버튼
        AnimatedOutlinedButton(
          text: 'Outlined Button',
          icon: Icons.add_rounded,
          onPressed: () {
            print('Outlined 버튼 클릭!');
          },
        ),
      ],
    );
  }

  /// 애니메이션 카드 예제
  static Widget animatedCardsExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🎴 인터랙티브 애니메이션 카드',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 20),
        
        // 기본 애니메이션 카드
        AnimatedCard(
          onTap: () {
            print('기본 카드 클릭!');
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '기본 애니메이션 카드',
                    style: AppTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '터치하면 스케일과 그림자 효과가 적용됩니다. '
                '호버 시에도 부드러운 인터랙션을 경험할 수 있습니다.',
                style: AppTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // 글래스모피즘 카드
        AnimatedCard.glassmorphism(
          gradientType: 'primary',
          onTap: () {
            print('글래스모피즘 카드 클릭!');
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.blur_on_rounded,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Glassmorphism 카드',
                    style: AppTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '글래스모피즘 효과와 마이크로 인터랙션이 결합된 '
                '2024-2025 트렌드 카드입니다.',
                style: AppTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        
        // 그라디언트 카드
        AnimatedCard.gradient(
          gradientType: 'emerald',
          onTap: () {
            print('그라디언트 카드 클릭!');
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.gradient_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Gradient 카드',
                    style: AppTheme.titleMedium.copyWith(color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Emerald 그라디언트 배경에 화이트 텍스트가 조화롭게 '
                '어우러진 카드입니다.',
                style: AppTheme.bodyMedium.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 페이지 전환 예제
  static Widget pageTransitionsExample(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '🔄 페이지 전환 애니메이션',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 20),
        
        // Slide 전환
        AnimatedButton(
          text: 'Slide Transition',
          icon: Icons.swipe_right_rounded,
          style: 'primary',
          onPressed: () {
            Navigator.of(context).push(
              PageTransitions.slideTransition(
                page: _DemoPage(title: 'Slide Transition'),
                direction: SlideDirection.fromRight,
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        
        // Fade 전환
        AnimatedButton(
          text: 'Fade Transition',
          icon: Icons.fade_in_rounded,
          style: 'secondary',
          onPressed: () {
            Navigator.of(context).push(
              PageTransitions.fadeTransition(
                page: _DemoPage(title: 'Fade Transition'),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        
        // Scale 전환
        AnimatedButton(
          text: 'Scale Transition',
          icon: Icons.zoom_in_rounded,
          style: 'emerald',
          onPressed: () {
            Navigator.of(context).push(
              PageTransitions.scaleTransition(
                page: _DemoPage(title: 'Scale Transition'),
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        
        // Mixed 전환
        AnimatedButton(
          text: 'Mixed Transition',
          icon: Icons.auto_awesome_rounded,
          style: 'amber',
          onPressed: () {
            Navigator.of(context).push(
              PageTransitions.mixedTransition(
                page: _DemoPage(title: 'Mixed Transition'),
                direction: SlideDirection.fromBottom,
              ),
            );
          },
        ),
      ],
    );
  }

  /// 마이크로 인터랙션 예제
  static Widget microInteractionsExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '⚡ 마이크로 인터랙션',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 20),
        
        Text(
          '리스트 아이템 애니메이션:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        
        // 애니메이션 리스트 타일들
        AnimatedListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.primarySubtle,
            child: Icon(Icons.person_rounded, color: AppTheme.primary),
          ),
          title: Text('사용자 프로필', style: AppTheme.titleMedium),
          subtitle: Text('터치하면 스케일 애니메이션', style: AppTheme.bodyMedium),
          trailing: Icon(Icons.arrow_forward_ios_rounded, 
                        color: AppTheme.textSecondary, size: 16),
          onTap: () {
            print('프로필 리스트 아이템 클릭!');
          },
        ),
        const Divider(height: 1),
        
        AnimatedListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.secondarySubtle,
            child: Icon(Icons.settings_rounded, color: AppTheme.secondary),
          ),
          title: Text('설정', style: AppTheme.titleMedium),
          subtitle: Text('부드러운 터치 피드백', style: AppTheme.bodyMedium),
          trailing: Icon(Icons.arrow_forward_ios_rounded, 
                        color: AppTheme.textSecondary, size: 16),
          onTap: () {
            print('설정 리스트 아이템 클릭!');
          },
        ),
        const Divider(height: 1),
        
        AnimatedListTile(
          leading: CircleAvatar(
            backgroundColor: AppTheme.accentEmeraldLight,
            child: Icon(Icons.notifications_rounded, color: AppTheme.accentEmerald),
          ),
          title: Text('알림', style: AppTheme.titleMedium),
          subtitle: Text('120ms 빠른 반응속도', style: AppTheme.bodyMedium),
          trailing: Icon(Icons.arrow_forward_ios_rounded, 
                        color: AppTheme.textSecondary, size: 16),
          onTap: () {
            print('알림 리스트 아이템 클릭!');
          },
        ),
      ],
    );
  }

  /// 전체 데모 페이지
  static Widget fullAnimationDemo(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('2024-2025 애니메이션 트렌드'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              animatedButtonsExample(),
              const SizedBox(height: 40),
              animatedCardsExample(),
              const SizedBox(height: 40),
              pageTransitionsExample(context),
              const SizedBox(height: 40),
              microInteractionsExample(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

/// 데모용 페이지
class _DemoPage extends StatelessWidget {
  final String title;

  const _DemoPage({required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 80,
                color: AppTheme.primary,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: AppTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                '이 페이지는 $title 효과로 열렸습니다.\n'
                '뒤로 가기 버튼을 눌러 애니메이션을 확인해보세요.',
                style: AppTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              AnimatedButton.primary(
                text: '뒤로 가기',
                icon: Icons.arrow_back_rounded,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 애니메이션 사용법 가이드
class AnimationUsageGuide {
  static const String basicUsage = '''
// 2024-2025 트렌드 애니메이션 사용법

// 애니메이션 버튼
AnimatedButton.primary(
  text: 'Click Me',
  icon: Icons.star,
  onPressed: () => print('클릭!'),
)

// 애니메이션 카드
AnimatedCard(
  onTap: () => print('카드 클릭!'),
  child: Text('카드 내용'),
)

// 글래스모피즘 카드
AnimatedCard.glassmorphism(
  gradientType: 'primary',
  child: Text('글래스 효과'),
)

// 애니메이션 리스트 타일
AnimatedListTile(
  title: Text('제목'),
  subtitle: Text('부제목'),
  onTap: () => print('리스트 클릭!'),
)
''';

  static const String pageTransitionUsage = '''
// 페이지 전환 애니메이션

// 기본 슬라이드 전환
Navigator.push(context, PageTransitions.slideTransition(
  page: NextPage(),
  direction: SlideDirection.fromRight,
))

// 페이드 전환
Navigator.push(context, PageTransitions.fadeTransition(
  page: NextPage(),
))

// 스케일 전환
Navigator.push(context, PageTransitions.scaleTransition(
  page: NextPage(),
  alignment: Alignment.center,
))

// 확장 메서드 사용
NextPage().openWithSlide(context, direction: SlideDirection.fromBottom)
NextPage().openWithFade(context)
NextPage().openWithScale(context)
''';

  static const String performanceOptimization = '''
// 성능 최적화 팁

1. 애니메이션 기간 최적화:
   - 마이크로 인터랙션: 120-180ms
   - 페이지 전환: 300-350ms
   - 복잡한 애니메이션: 500ms 이하

2. 커브 선택:
   - 기본: Curves.easeInOutCubic
   - 탄성: Curves.elasticOut
   - 슬라이드: Curves.fastOutSlowIn

3. 메모리 관리:
   - AnimationController 적절한 dispose
   - 불필요한 애니메이션 중지
   - 화면 밖 위젯 애니메이션 방지

4. 접근성 고려:
   - MediaQuery.disableAnimationsOf(context) 확인
   - 시각 장애인을 위한 대체 피드백
   - 전정 장애인을 위한 애니메이션 줄이기 옵션
''';
}

