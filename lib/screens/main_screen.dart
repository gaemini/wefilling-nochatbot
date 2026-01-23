// lib/screens/main_screen.dart
// 앱의 메인화면 구현
// 하단 탭 네비게이션 제공
// 게시판, 모임, 마이페이지 화면 통합

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/dm_service.dart';
import '../services/notification_service.dart';
import '../ui/widgets/app_icon_button.dart';
import '../utils/logger.dart';
import '../widgets/adaptive_bottom_navigation.dart';
import '../widgets/notification_badge.dart';
import 'ad_showcase_screen.dart';
import 'board_screen.dart';
import 'dm_list_screen.dart';
import 'friend_categories_screen.dart';
import 'home_screen.dart';
import 'mypage_screen.dart';
import 'notification_screen.dart';
import 'unified_search_screen.dart';

class MainScreen extends StatefulWidget {
  final int initialTabIndex;
  final String? initialMeetupId; // 알림에서 전달받을 모임 ID

  const MainScreen({
    Key? key,
    this.initialTabIndex = 0,
    this.initialMeetupId,
  }) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex; // 초기값은 initState에서 설정
  final NotificationService _notificationService = NotificationService();
  final DMService _dmService = DMService();
  late VoidCallback _cleanupCallback;
  String? _pendingMeetupId; // 알림으로 전달된 모임 ID (1회용)
  AuthProvider? _authProvider;

  @override
  void initState() {
    super.initState();

    // 초기 탭 인덱스 설정
    _selectedIndex = widget.initialTabIndex;
    // 알림으로 넘어온 모임 ID는 최초 1회만 사용하도록 보관
    _pendingMeetupId = widget.initialMeetupId;

    // 스트림 정리 콜백 등록
    _cleanupCallback = () {
      _notificationService.dispose();
    };

    // initState에서 listen:false로 읽는 것은 안전하며,
    // post-frame 콜백에서 (이미 dispose된) context를 조회하는 레이스를 제거한다.
    _authProvider = Provider.of<AuthProvider>(context, listen: false);
    _authProvider?.registerStreamCleanup(_cleanupCallback);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 로그인 실패(회원가입 필요) 후 메인으로 돌아온 경우 안내 표시
      if (_authProvider?.consumeSignupRequiredFlag() == true) {
        _showSignupRequiredBanner();
      }

      // Meetups 탭이 표시되고 알림 모임 ID가 남아있다면, 이번 렌더 이후에 소모 처리
      if (_selectedIndex == 1 && _pendingMeetupId != null) {
        // 한 번 전달 후 null로 만들어 재진입 시 자동 오픈 방지
        setState(() {
          _pendingMeetupId = null;
        });
      }
    });
  }

  @override
  void dispose() {
    // AuthProvider에서 콜백 제거
    // dispose에서는 context로 ancestor lookup을 하지 않는다.
    _authProvider?.unregisterStreamCleanup(_cleanupCallback);

    // 서비스 정리
    _notificationService.dispose();
    super.dispose();
  }

  // 화면 목록 - 검색어를 전달할 수 있도록 수정
  List<Widget> get _screens => [
        const BoardScreen(),
        // 알림에서 온 모임은 최초 1회만 자동 오픈되도록 전달
        MeetupHomePage(initialMeetupId: _pendingMeetupId),
        const FriendCategoriesScreen(),
        const MyPageScreen(),
        const DMListScreen(),
      ];
  // 프로덕션 배포: 디버그 헬퍼 제거
  // final FirebaseDebugHelper _firebaseDebugHelper = FirebaseDebugHelper();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });

    // Meetups 탭으로 이동하는 순간, 아직 소모되지 않은 모임 ID가 있다면 바로 소모 처리
    if (index == 1 && _pendingMeetupId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _pendingMeetupId = null;
          });
        }
      });
    }
  }

  void _navigateToSearchPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UnifiedSearchScreen(
          // 0: 이름, 1: 게시글, 2: 모임 ...
          initialTabIndex: _selectedIndex == 0 ? 1 : 2,
          initialQuery: null,
        ),
      ),
    );
  }

  /// 로고 위젯 빌더 - 실제 Wefilling 로고 (앱 아이콘 사용)
  Widget _buildLogo() {
    // 스플래시 화면과 동일한 실제 앱 아이콘 사용
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.asset(
          'assets/icons/app_logo.png',
          width: 28,
          height: 28,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            // 이미지 로드 실패 시 CustomPaint 로고 사용
            return CustomPaint(
              painter: WefillingLogoPainter(),
            );
          },
        ),
      ),
    );
  }

  void _showSignupRequiredBanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Material(
              borderRadius: BorderRadius.circular(12),
              color: Colors.orange.shade50,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.signupRequired,
                            style: const TextStyle(fontSize: 15, height: 1.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '한양메일 인증을 완료한 후 회원가입을 진행해주세요.',
                            style: TextStyle(
                                fontSize: 13, color: Colors.orange.shade900),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text(AppLocalizations.of(context)!.confirm),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black12,
        title: Row(
          children: [
            // Wefilling 로고 + 텍스트 (클릭 가능)
            GestureDetector(
              onTap: () {
                // 광고 쇼케이스 페이지로 이동
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AdShowcaseScreen(),
                  ),
                );
              },
              behavior: HitTestBehavior.opaque, // 투명한 영역도 터치 가능하게
              child: Row(
                mainAxisSize: MainAxisSize.min, // Row 크기를 내용물에 맞춤
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    child: _buildLogo(),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Wefilling',
                    style: TextStyle(
                      fontFamily: 'HancomMalrangmalrang',
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.pointColor, // 위필링 시그니처 파란색으로 통일
                      letterSpacing: -0.5,
                      shadows: [
                        Shadow(
                          offset: Offset(0.5, 0.5),
                          blurRadius: 0.5,
                          color: AppColors.pointColor,
                        ),
                      ],
                    ),
                  ),
                ],
            ),
          ),
            const Spacer(),
            // 돋보기 아이콘 (게시글/모임 탭에서만 표시)
            if (_selectedIndex <= 1) ...[
              AppIconButton(
                icon: Icons.search,
                onPressed: _navigateToSearchPage,
                semanticLabel: AppLocalizations.of(context)!.search,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
            // 마이페이지 탭일 때: 설정 버튼을 먼저 표시 (알림 아이콘과 위치 교체)
            if (_selectedIndex == 3) ...[
              const SizedBox(width: 4),
              AppIconButton(
                icon: Icons.settings_outlined,
                onPressed: () {
                  MyPageSettingsSheet.show(context);
                },
                semanticLabel: AppLocalizations.of(context)!.settings,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
            ],
            // 알림 아이콘
            StreamBuilder<int>(
              stream: _notificationService.getUnreadNotificationCount(),
              builder: (context, snapshot) {
                final unreadCount = snapshot.data ?? 0;

                return NotificationBadge(
                  count: unreadCount,
                  child: AppIconButton(
                    icon: Icons.notifications_outlined,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const NotificationScreen(),
                        ),
                      );
                    },
                    semanticLabel: AppLocalizations.of(context)!.notifications,
                    visualDensity: VisualDensity.compact,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: _screens[_selectedIndex],

      // 완전 반응형 하단 네비게이션 (갤럭시 S23 등 모든 기기 대응)
      bottomNavigationBar: StreamBuilder<int>(
        stream: _dmService.getTotalUnreadCount(),
        builder: (context, snapshot) {
          final l10n = AppLocalizations.of(context)!;
          Logger.log('📊 StreamBuilder 상태:');
          Logger.log('  - hasData: ${snapshot.hasData}');
          Logger.error('  - hasError: ${snapshot.hasError}');
          Logger.log('  - data: ${snapshot.data}');
          if (snapshot.hasError) {
            Logger.error('  - error: ${snapshot.error}');
          }

          final unreadDMCount = snapshot.data ?? 0;
          Logger.log('  - unreadDMCount: $unreadDMCount');

          return AdaptiveBottomNavigation(
            selectedIndex: _selectedIndex,
            onItemTapped: _onItemTapped,
            items: [
              BottomNavigationItem(
                icon: Icons.menu,
                selectedIcon: Icons.menu,
                label: l10n.board,
              ),
              BottomNavigationItem(
                icon: Icons.groups_outlined,
                selectedIcon: Icons.groups,
                label: l10n.meetup,
              ),
              BottomNavigationItem(
                icon: Icons.change_history_outlined,
                selectedIcon: Icons.change_history,
                label: l10n.category,
              ),
              BottomNavigationItem(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: l10n.myPage,
              ),
              BottomNavigationItem(
                icon: Icons.chat_bubble_outline,
                selectedIcon: Icons.chat_bubble,
                label: l10n.dm,
                badgeCount: unreadDMCount, // DM 읽지 않은 메시지 수 배지
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Wefilling 로고를 그리는 CustomPainter
/// 실제 Wefilling 로고와 동일한 파란색 꽃잎 5개 디자인
class WefillingLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.4;

    // 실제 Wefilling 로고 색상 (스플래시 화면과 동일)
    final petalColors = [
      const Color(0xFF1E88E5), // 메인 파란색
      const Color(0xFF42A5F5), // 밝은 파란색
      const Color(0xFF64B5F6), // 중간 파란색
      const Color(0xFF90CAF9), // 연한 파란색
      const Color(0xFFBBDEFB), // 가장 연한 파란색
    ];

    // 5개의 꽃잎을 72도씩 회전하며 그리기
    for (int i = 0; i < 5; i++) {
      final angle = (i * 72) * math.pi / 180;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      // 더 정확한 꽃잎 모양 (타원형 기반)
      final path = Path();

      // 꽃잎의 타원형 모양 생성
      final rect = Rect.fromCenter(
        center: Offset(0, -radius * 0.3),
        width: radius * 0.8,
        height: radius * 1.2,
      );

      path.addOval(rect);

      // 꽃잎 그리기 (그라데이션 효과)
      final paint = Paint()
        ..color = petalColors[i]
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, paint);

      // 약간의 투명도로 겹침 효과
      final overlayPaint = Paint()
        ..color = petalColors[i].withOpacity(0.6)
        ..style = PaintingStyle.fill;

      canvas.drawPath(path, overlayPaint);

      canvas.restore();
    }

    // 중앙 하이라이트 (더 작게)
    final centerPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius * 0.12, centerPaint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
