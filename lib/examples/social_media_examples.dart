// lib/examples/social_media_examples.dart
// 2024-2025 트렌드 Social Media Inspired UI 사용 예제
// 스토리 카테고리, Enhanced FAB, 소셜 인터랙션 가이드

import 'package:flutter/material.dart';
import '../ui/widgets/story_categories.dart';
import '../ui/widgets/enhanced_fab.dart';
import '../ui/widgets/social_interactions.dart';
import '../ui/widgets/animated_card.dart';
import '../constants/app_constants.dart';

/// 소셜 미디어 스타일 UI 예제 모음
class SocialMediaExamples {
  
  /// 스토리 카테고리 예제
  static Widget storyCategoriesExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '📱 Instagram/TikTok 스타일 카테고리',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        Text(
          '기본 카테고리:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        
        // 기본 스토리 카테고리
        StoryCategories.defaultCategories(
          selectedIndex: 0,
          onCategorySelected: (index) {
            print('카테고리 $index 선택됨');
          },
        ),
        
        const SizedBox(height: 24),
        
        Text(
          '커스텀 카테고리:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        
        // 커스텀 카테고리
        StoryCategories(
          categories: [
            CategoryItem(
              id: 'trending',
              title: '트렌딩',
              icon: Icons.trending_up_rounded,
              gradient: LinearGradient(
                colors: [Color(0xFFFF6B6B), Color(0xFFFFE66D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            CategoryItem(
              id: 'nearby',
              title: '내 근처',
              icon: Icons.location_on_rounded,
              gradient: LinearGradient(
                colors: [Color(0xFF4ECDC4), Color(0xFF44A08D)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            CategoryItem(
              id: 'live',
              title: '라이브',
              icon: Icons.radio_button_checked_rounded,
              gradient: LinearGradient(
                colors: [Color(0xFFE84393), Color(0xFF6C5CE7)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ],
          selectedIndex: 1,
          onCategorySelected: (index) {
            print('커스텀 카테고리 $index 선택됨');
          },
        ),
      ],
    );
  }

  /// Enhanced FAB 예제
  static Widget enhancedFabExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🚀 Enhanced FAB 컬렉션',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        Text(
          '기본 Enhanced FAB들:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        
        // FAB 예제들을 Row로 배치
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            // 새 모임 FAB
            EnhancedFab.createMeetup(
              onPressed: () => print('새 모임 생성!'),
              usePulseAnimation: true,
            ),
            
            // 글쓰기 FAB
            EnhancedFab.write(
              onPressed: () => print('글쓰기!'),
            ),
            
            // 채팅 FAB
            EnhancedFab.chat(
              onPressed: () => print('채팅 시작!'),
            ),
            
            // 카메라 FAB
            EnhancedFab.camera(
              onPressed: () => print('카메라 실행!'),
            ),
          ],
        ),
        
        const SizedBox(height: 24),
        
        Text(
          '원형 FAB들:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 20),
        
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            // 원형 FAB들
            EnhancedFab.circular(
              icon: Icons.add_rounded,
              onPressed: () => print('추가!'),
              gradientType: 'primary',
            ),
            
            EnhancedFab.circular(
              icon: Icons.favorite_rounded,
              onPressed: () => print('좋아요!'),
              gradientType: 'secondary',
              usePulseAnimation: true,
            ),
            
            EnhancedFab.circular(
              icon: Icons.share_rounded,
              onPressed: () => print('공유!'),
              gradientType: 'emerald',
            ),
          ],
        ),
      ],
    );
  }

  /// 소셜 인터랙션 예제
  static Widget socialInteractionsExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '💖 소셜 미디어 인터랙션',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        Text(
          '개별 액션 버튼들:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        
        // 개별 액션 버튼들
        Container(
          padding: const EdgeInsets.all(20),
          decoration: AppTheme.modernCardDecoration,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              SocialActionButton.like(
                count: 128,
                isActive: true,
                onTap: () => print('좋아요!'),
              ),
              SocialActionButton.comment(
                count: 24,
                onTap: () => print('댓글!'),
              ),
              SocialActionButton.share(
                count: 8,
                onTap: () => print('공유!'),
              ),
              SocialActionButton.bookmark(
                isActive: false,
                onTap: () => print('북마크!'),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        Text(
          '통합 액션 바:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        
        // 통합 액션 바
        Container(
          decoration: AppTheme.modernCardDecoration,
          child: SocialActionBar(
            likeData: SocialActionData(
              count: 256,
              isActive: true,
              onTap: () => print('좋아요 토글!'),
            ),
            commentData: SocialActionData(
              count: 47,
              onTap: () => print('댓글 보기!'),
            ),
            shareData: SocialActionData(
              count: 12,
              onTap: () => print('공유하기!'),
            ),
            bookmarkData: SocialActionData(
              isActive: true,
              onTap: () => print('북마크 토글!'),
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        Text(
          '댓글 입력창:',
          style: AppTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        
        // 댓글 입력창
        SocialCommentInput(
          hintText: '이 모임에 대한 의견을 남겨보세요...',
          onSend: (comment) => print('댓글 전송: $comment'),
        ),
      ],
    );
  }

  /// 소셜 미디어 스타일 카드 예제
  static Widget socialMediaCardExample() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '🎴 소셜 미디어 스타일 카드',
          style: AppTheme.titleEnhanced,
        ),
        const SizedBox(height: 16),
        
        // 인스타그램 스타일 포스트 카드
        AnimatedCard.gradient(
          gradientType: 'primary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더 (프로필 정보)
              Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppTheme.primarySubtle,
                    child: Icon(
                      Icons.person_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '홍길동',
                          style: AppTheme.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '2시간 전',
                          style: AppTheme.bodySmall.copyWith(
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => print('더보기'),
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // 컨텐츠
              Text(
                '오늘 스터디 카페에서 정말 알찬 시간 보냈어요! 🤓\n'
                '다음 주에 또 모여서 프로젝트 마무리하겠습니다.',
                style: AppTheme.bodyLarge.copyWith(
                  color: Colors.white,
                  height: 1.6,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 이미지 플레이스홀더
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    Icons.image_rounded,
                    color: Colors.white70,
                    size: 48,
                  ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // 소셜 액션
              SocialActionBar(
                likeData: SocialActionData(
                  count: 42,
                  isActive: true,
                  onTap: () => print('좋아요!'),
                ),
                commentData: SocialActionData(
                  count: 8,
                  onTap: () => print('댓글!'),
                ),
                shareData: SocialActionData(
                  count: 3,
                  onTap: () => print('공유!'),
                ),
                size: SocialActionSize.small,
                mainAxisAlignment: MainAxisAlignment.start,
                spacing: 32.0,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 전체 소셜 미디어 데모 페이지
  static Widget fullSocialMediaDemo(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('소셜 미디어 스타일 UI'),
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
              storyCategoriesExample(),
              const SizedBox(height: 40),
              enhancedFabExample(),
              const SizedBox(height: 40),
              socialInteractionsExample(),
              const SizedBox(height: 40),
              socialMediaCardExample(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
      // 멀티 FAB 예제
      floatingActionButton: _buildMultiFabExample(),
    );
  }

  /// 멀티 FAB 예제
  static Widget _buildMultiFabExample() {
    return SocialMediaFab(
      mainFab: EnhancedFab.createMeetup(
        onPressed: () => print('메인 FAB 클릭!'),
      ),
      subFabs: [
        EnhancedFab.circular(
          icon: Icons.camera_alt_rounded,
          onPressed: () => print('카메라!'),
          gradientType: 'amber',
        ),
        EnhancedFab.circular(
          icon: Icons.edit_rounded,
          onPressed: () => print('글쓰기!'),
          gradientType: 'secondary',
        ),
        EnhancedFab.circular(
          icon: Icons.people_rounded,
          onPressed: () => print('친구 초대!'),
          gradientType: 'emerald',
        ),
      ],
    );
  }
}

/// 소셜 미디어 UI 통합 위젯
class SocialMediaScreen extends StatefulWidget {
  const SocialMediaScreen({super.key});

  @override
  State<SocialMediaScreen> createState() => _SocialMediaScreenState();
}

class _SocialMediaScreenState extends State<SocialMediaScreen> {
  int _selectedCategoryIndex = 0;
  bool _isFabOpen = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: CustomScrollView(
          slivers: [
            // 앱바
            SliverAppBar(
              expandedHeight: 180,
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
                    gradient: AppTheme.primaryGradient,
                  ),
                ),
              ),
            ),
            
            // 스토리 카테고리
            SliverToBoxAdapter(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: StoryCategories.defaultCategories(
                  selectedIndex: _selectedCategoryIndex,
                  onCategorySelected: (index) {
                    setState(() => _selectedCategoryIndex = index);
                  },
                ),
              ),
            ),
            
            // 컨텐츠 리스트
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: _buildContentCard(index),
                  );
                },
                childCount: 10,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: SocialMediaFab(
        isOpen: _isFabOpen,
        onToggle: (isOpen) => setState(() => _isFabOpen = isOpen),
        mainFab: EnhancedFab.createMeetup(
          onPressed: () => print('새 모임 생성!'),
          usePulseAnimation: true,
        ),
        subFabs: [
          EnhancedFab.circular(
            icon: Icons.camera_alt_rounded,
            onPressed: () => print('카메라!'),
            gradientType: 'amber',
          ),
          EnhancedFab.circular(
            icon: Icons.edit_rounded,
            onPressed: () => print('글쓰기!'),
            gradientType: 'secondary',
          ),
          EnhancedFab.circular(
            icon: Icons.people_rounded,
            onPressed: () => print('친구 초대!'),
            gradientType: 'emerald',
          ),
        ],
      ),
    );
  }

  Widget _buildContentCard(int index) {
    return AnimatedCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사용자 정보
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppTheme.primarySubtle,
                child: Text('${index + 1}'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '사용자 ${index + 1}',
                      style: AppTheme.titleMedium,
                    ),
                    Text(
                      '${index + 1}시간 전',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 컨텐츠
          Text(
            '이것은 샘플 포스트 내용입니다. 소셜 미디어 스타일의 '
            '인터랙티브한 UI를 확인해보세요! #위필링 #대학생모임',
            style: AppTheme.bodyLarge,
          ),
          
          const SizedBox(height: 16),
          
          // 이미지 플레이스홀더
          Container(
            height: 200,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.primary.withOpacity(0.1),
                  AppTheme.secondary.withOpacity(0.1),
                ],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                Icons.image_rounded,
                color: AppTheme.textSecondary,
                size: 48,
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 소셜 액션
          SocialActionBar(
            likeData: SocialActionData(
              count: (index + 1) * 12,
              isActive: index % 3 == 0,
              onTap: () => print('좋아요 $index'),
            ),
            commentData: SocialActionData(
              count: (index + 1) * 3,
              onTap: () => print('댓글 $index'),
            ),
            shareData: SocialActionData(
              count: index + 1,
              onTap: () => print('공유 $index'),
            ),
            bookmarkData: SocialActionData(
              isActive: index % 4 == 0,
              onTap: () => print('북마크 $index'),
            ),
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          ),
        ],
      ),
    );
  }
}

/// 소셜 미디어 UI 사용법 가이드
class SocialMediaUsageGuide {
  static const String basicUsage = '''
// 2024-2025 트렌드 소셜 미디어 UI 사용법

// 스토리 카테고리
StoryCategories.defaultCategories(
  selectedIndex: 0,
  onCategorySelected: (index) => print('카테고리 \$index'),
)

// Enhanced FAB
EnhancedFab.createMeetup(
  onPressed: () => createMeetup(),
  usePulseAnimation: true,
)

// 소셜 액션 바
SocialActionBar(
  likeData: SocialActionData(count: 42, isActive: true),
  commentData: SocialActionData(count: 8),
  shareData: SocialActionData(count: 3),
)

// 댓글 입력
SocialCommentInput(
  onSend: (comment) => sendComment(comment),
)
''';

  static const String advancedUsage = '''
// 고급 사용법

// 멀티 FAB
SocialMediaFab(
  mainFab: EnhancedFab.createMeetup(onPressed: () {}),
  subFabs: [
    EnhancedFab.circular(icon: Icons.camera_alt, onPressed: () {}),
    EnhancedFab.circular(icon: Icons.edit, onPressed: () {}),
  ],
)

// 커스텀 카테고리
StoryCategories(
  categories: [
    CategoryItem(
      id: 'custom',
      title: '커스텀',
      icon: Icons.star,
      gradient: LinearGradient(colors: [Colors.red, Colors.blue]),
    ),
  ],
)

// 애니메이션 카드 + 소셜 액션 조합
AnimatedCard.gradient(
  gradientType: 'primary',
  child: Column(
    children: [
      // 컨텐츠
      Text('포스트 내용'),
      // 소셜 액션
      SocialActionBar(...),
    ],
  ),
)
''';

  static const String integrationTips = '''
// 기존 앱 통합 팁

1. 점진적 적용:
   - 기존 카테고리 → StoryCategories로 교체
   - 기존 FAB → EnhancedFab으로 업그레이드
   - 기존 액션 버튼 → SocialActionButton으로 변경

2. 성능 최적화:
   - 카테고리 스크롤 시 lazyLoading 활용
   - FAB 애니메이션은 필요시에만 활성화
   - 소셜 액션은 debounce 적용

3. 접근성 고려:
   - 모든 버튼에 적절한 semanticLabel 설정
   - 색상 대비 WCAG AA 준수
   - 애니메이션 감소 설정 반영

4. 디자인 일관성:
   - AppTheme의 색상 시스템 활용
   - 일관된 간격과 크기 사용
   - 브랜드 아이덴티티 유지
''';
}

