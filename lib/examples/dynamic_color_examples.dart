// lib/examples/dynamic_color_examples.dart
// 2024-2025 트렌드 Dynamic Colors (시간대별 변화) 사용 예제
// 실시간 색상 변화, 부드러운 전환, 시간 인식 UI

import 'package:flutter/material.dart';
import '../ui/widgets/dynamic_color_widget.dart';
import '../ui/widgets/animated_card.dart';
import '../constants/app_constants.dart';

/// 다이나믹 컬러 사용 예제 모음
class DynamicColorExamples {
  
  /// 기본 다이나믹 컬러 예제
  static Widget basicDynamicColorExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🌅 시간대별 다이나믹 컬러',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        Text(
          '현재 시간: ${AppTheme.getCurrentTimeLabel()}',
          style: AppTheme.titleMedium.copyWith(
            color: AppTheme.getDynamicPrimary(),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        
        // 실시간 색상 변화 데모
        Container(
          height: 120,
          decoration: BoxDecoration(
            gradient: AppTheme.getDynamicPrimaryGradient(),
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            boxShadow: [
              BoxShadow(
                color: AppTheme.getDynamicPrimary().withOpacity(0.3),
                offset: const Offset(0, 8),
                blurRadius: 24,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _getTimeIcon(),
                  color: Colors.white,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  '지금은 ${AppTheme.getCurrentTimeLabel()}',
                  style: AppTheme.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 20),
        
        // 시간 진행률 표시
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            border: Border.all(
              color: AppTheme.getDynamicPrimary().withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '시간대 진행률',
                style: AppTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: AppTheme.getTimeProgress(),
                backgroundColor: AppTheme.getDynamicPrimary().withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  AppTheme.getDynamicPrimary(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(AppTheme.getTimeProgress() * 100).toInt()}% 진행됨',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 다이나믹 컬러 카드 예제
  static Widget dynamicColorCardsExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🎴 다이나믹 컬러 카드',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        // 기본 다이나믹 카드
        DynamicColorCard(
          onTap: () => print('다이나믹 카드 클릭!'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: AppTheme.getDynamicPrimary(),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '자동 색상 변화',
                    style: AppTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '이 카드는 시간대에 따라 자동으로 색상이 변합니다. '
                '현재는 ${AppTheme.getCurrentTimeLabel()} 시간대의 색상을 표시하고 있습니다.',
                style: AppTheme.bodyMedium,
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // 강렬한 다이나믹 카드
        DynamicColorCard(
          useIntenseDynamicColors: true,
          onTap: () => print('강렬한 다이나믹 카드 클릭!'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.colorize_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '강렬한 다이나믹 효과',
                    style: AppTheme.titleMedium.copyWith(color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '더 강렬한 색상 변화를 원할 때 사용하는 카드입니다. '
                '완전한 그라디언트 배경으로 시각적 임팩트를 극대화합니다.',
                style: AppTheme.bodyMedium.copyWith(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 다이나믹 컬러 FAB 예제
  static Widget dynamicColorFabExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🚀 다이나믹 컬러 FAB',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 확장형 FAB
            DynamicColorFab(
              icon: Icons.add_rounded,
              label: '새 모임',
              onPressed: () => print('다이나믹 FAB 클릭!'),
            ),
            
            // 원형 FAB
            DynamicColorFab(
              icon: Icons.favorite_rounded,
              isExtended: false,
              onPressed: () => print('원형 다이나믹 FAB 클릭!'),
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        
        Text(
          'FAB의 색상도 시간대에 따라 자동으로 변화합니다. '
          '그림자와 글로우 효과도 함께 조정되어 일관된 경험을 제공합니다.',
          style: AppTheme.bodyMedium.copyWith(
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  /// 시간대별 색상 프리뷰
  static Widget timeColorPreviewExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '⏰ 시간대별 색상 프리뷰',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        const TimeColorPreview(),
        
        const SizedBox(height: 16),
        
        Text(
          '각 시간대마다 고유한 색상 조합을 사용합니다:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        
        _buildTimeDescription('새벽 (00-06)', '깊고 차분한 남색 계열', '휴식과 평온의 시간'),
        const SizedBox(height: 8),
        _buildTimeDescription('오전 (06-12)', '밝고 활기찬 파란색 계열', '시작과 활동의 시간'),
        const SizedBox(height: 8),
        _buildTimeDescription('오후 (12-18)', '따뜻하고 에너지 넘치는 핑크 계열', '활동과 창조의 시간'),
        const SizedBox(height: 8),
        _buildTimeDescription('저녁 (18-24)', '부드럽고 따뜻한 보라색 계열', '마무리와 휴식의 시간'),
      ],
    );
  }

  /// 다이나믹 컬러 설정 예제
  static Widget dynamicColorSettingsExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '⚙️ 다이나믹 컬러 설정',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        Container(
          decoration: BoxDecoration(
            color: AppTheme.backgroundSecondary,
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
          ),
          child: Column(
            children: [
              DynamicColorToggle(
                initialValue: true,
                onChanged: (enabled) {
                  print('다이나믹 컬러: ${enabled ? "활성화" : "비활성화"}');
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.schedule_rounded,
                  color: AppTheme.getDynamicSecondary(),
                ),
                title: Text(
                  '업데이트 주기',
                  style: AppTheme.titleMedium,
                ),
                subtitle: Text(
                  '1분마다 자동 확인',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                trailing: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: AppTheme.textSecondary,
                  size: 16,
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  Icons.battery_saver_rounded,
                  color: AppTheme.getDynamicAccent(),
                ),
                title: Text(
                  '배터리 절약 모드',
                  style: AppTheme.titleMedium,
                ),
                subtitle: Text(
                  '색상 변화 빈도 줄이기',
                  style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.textSecondary,
                  ),
                ),
                trailing: Switch(
                  value: false,
                  onChanged: (value) {
                    print('배터리 절약 모드: ${value ? "활성화" : "비활성화"}');
                  },
                  activeColor: AppTheme.getDynamicAccent(),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 전체 다이나믹 컬러 데모 페이지
  static Widget fullDynamicColorDemo(BuildContext context) {
    return DynamicColorWidget(
      showTimeInfo: true,
      child: Scaffold(
        appBar: DynamicColorAppBar(
          title: '다이나믹 컬러 데모',
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () {
                print('색상 새로고침!');
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              basicDynamicColorExample(),
              const SizedBox(height: 40),
              dynamicColorCardsExample(),
              const SizedBox(height: 40),
              dynamicColorFabExample(),
              const SizedBox(height: 40),
              timeColorPreviewExample(),
              const SizedBox(height: 40),
              dynamicColorSettingsExample(),
              const SizedBox(height: 40),
            ],
          ),
        ),
        floatingActionButton: DynamicColorFab(
          icon: Icons.palette_rounded,
          label: '컬러 변경',
          onPressed: () => print('컬러 변경!'),
        ),
      ),
    );
  }

  // Helper methods
  static IconData _getTimeIcon() {
    final hour = DateTime.now().hour;
    if (hour < 6) return Icons.bedtime_rounded; // 새벽
    if (hour < 12) return Icons.wb_sunny_rounded; // 오전
    if (hour < 18) return Icons.wb_twilight_rounded; // 오후
    return Icons.nights_stay_rounded; // 저녁
  }

  static Widget _buildTimeDescription(String time, String colors, String mood) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppTheme.radiusM),
        border: Border.all(
          color: AppTheme.getDynamicPrimary().withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: AppTheme.titleSmall.copyWith(
              color: AppTheme.getDynamicPrimary(),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            colors,
            style: AppTheme.bodyMedium,
          ),
          const SizedBox(height: 2),
          Text(
            mood,
            style: AppTheme.bodySmall.copyWith(
              color: AppTheme.textSecondary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

/// 다이나믹 컬러 통합 화면
class DynamicColorScreen extends StatefulWidget {
  const DynamicColorScreen({super.key});

  @override
  State<DynamicColorScreen> createState() => _DynamicColorScreenState();
}

class _DynamicColorScreenState extends State<DynamicColorScreen> {
  bool _dynamicColorsEnabled = true;

  @override
  Widget build(BuildContext context) {
    return DynamicColorWidget(
      enabled: _dynamicColorsEnabled,
      showTimeInfo: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            // 다이나믹 컬러 앱바
            SliverAppBar(
              expandedHeight: 200,
              floating: false,
              pinned: true,
              backgroundColor: Colors.transparent,
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  '위필링',
                  style: AppTheme.headlineMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                background: Container(
                  decoration: BoxDecoration(
                    gradient: AppTheme.getDynamicPrimaryGradient(),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        Icon(
                          DynamicColorExamples._getTimeIcon(),
                          color: Colors.white,
                          size: 64,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppTheme.getCurrentTimeLabel(),
                          style: AppTheme.titleLarge.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // 컨텐츠
            SliverList(
              delegate: SliverChildListDelegate([
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      DynamicColorExamples.basicDynamicColorExample(),
                      const SizedBox(height: 30),
                      DynamicColorExamples.dynamicColorCardsExample(),
                      const SizedBox(height: 30),
                      DynamicColorExamples.timeColorPreviewExample(),
                      const SizedBox(height: 30),
                      DynamicColorExamples.dynamicColorSettingsExample(),
                    ],
                  ),
                ),
              ]),
            ),
          ],
        ),
        floatingActionButton: DynamicColorFab(
          icon: Icons.auto_awesome_rounded,
          label: '다이나믹',
          onPressed: () {
            setState(() {
              _dynamicColorsEnabled = !_dynamicColorsEnabled;
            });
            AppTheme.setDynamicColors(_dynamicColorsEnabled);
          },
        ),
      ),
    );
  }
}

/// 다이나믹 컬러 사용법 가이드
class DynamicColorUsageGuide {
  static const String basicUsage = '''
// 2024-2025 트렌드 다이나믹 컬러 사용법

// 기본 시간대별 색상 가져오기
Color dynamicPrimary = AppTheme.getDynamicPrimary();
Color dynamicSecondary = AppTheme.getDynamicSecondary();
LinearGradient dynamicGradient = AppTheme.getDynamicPrimaryGradient();

// 자동 색상 변화 위젯
DynamicColorWidget(
  child: YourScreen(),
  showTimeInfo: true,  // 시간 정보 표시
)

// 다이나믹 컬러 카드
DynamicColorCard(
  child: YourContent(),
  useIntenseDynamicColors: true,  // 강렬한 효과
)

// 다이나믹 컬러 FAB
DynamicColorFab(
  icon: Icons.add,
  label: '새 모임',
  onPressed: () => createMeetup(),
)
''';

  static const String advancedUsage = '''
// 고급 사용법

// 다이나믹 컬러 활성화/비활성화
AppTheme.setDynamicColors(true);

// 현재 시간대 정보
String timeLabel = AppTheme.getCurrentTimeLabel();  // '오후'
double progress = AppTheme.getTimeProgress();       // 0.0-1.0

// 색상 보간 (부드러운 전환)
Color interpolated = AppTheme.getInterpolatedColor(
  startColor, 
  endColor, 
  progress
);

// 커스텀 다이나믹 위젯
AnimatedBuilder(
  animation: colorTimer,
  builder: (context, child) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.getDynamicPrimaryGradient(),
      ),
      child: child,
    );
  },
)
''';

  static const String integrationTips = '''
// 기존 앱 통합 팁

1. 점진적 적용:
   - 기존 primary/secondary 색상은 자동으로 다이나믹 적용
   - 새로운 위젯들을 선택적으로 도입
   - 사용자가 다이나믹 컬러를 끌 수 있는 옵션 제공

2. 성능 최적화:
   - 1분마다 색상 업데이트 (배터리 효율성)
   - 실제 색상 변화가 있을 때만 리빌드
   - 백그라운드에서도 과도한 계산 방지

3. 접근성 고려:
   - 색상 대비 WCAG AA 유지
   - 다이나믹 컬러 비활성화 옵션
   - 고대비 모드에서는 정적 색상 사용

4. UX 고려사항:
   - 부드러운 전환 애니메이션 (2초)
   - 시간 정보 표시로 사용자 인지도 향상
   - 브랜드 아이덴티티는 유지하면서 변화 적용
''';
}

