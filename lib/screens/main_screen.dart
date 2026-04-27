// lib/screens/main_screen.dart
// 앱의 메인화면 구현
// 하단 탭 네비게이션 제공 (나눔 피드 / 그룹 / DM / 마이페이지)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../constants/app_constants.dart';
import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/dm_service.dart';
import '../services/notification_service.dart';
import '../services/post_service.dart';
import '../services/badge_service.dart';
import '../services/snack_chat_service.dart';
import '../ui/widgets/app_icon_button.dart';
import '../utils/logger.dart';
import '../widgets/adaptive_bottom_navigation.dart';
import '../widgets/notification_badge.dart';
import 'ad_showcase_screen.dart';
import 'board_screen.dart';
import 'dm_list_screen.dart';
import 'friend_categories_screen.dart';
import 'mypage_screen.dart';
import 'notification_screen.dart';
import 'unified_search_screen.dart';

class MainScreen extends StatefulWidget {
  // 하위 호환을 위해 레거시 파라미터를 받되, 현재는 단일 탭 인덱스(0/1/2/3)만 사용한다.
  // - 0: 나눔 피드 (BoardScreen)
  // - 1: 그룹 (FriendCategoriesScreen)
  // - 2: DM (DMListScreen)
  // - 3: 마이페이지 (MyPageScreen)
  final int initialTabIndex;
  final int initialGroupTabIndex;
  final String? initialMeetupId;

  const MainScreen({
    Key? key,
    this.initialTabIndex = 0,
    this.initialGroupTabIndex = 0,
    this.initialMeetupId,
  }) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  static const int _kTabCount = 4;

  late int _selectedIndex;
  final NotificationService _notificationService = NotificationService();
  final DMService _dmService = DMService();
  final SnackChatService _snackChatService = SnackChatService();
  late VoidCallback _cleanupCallback;
  AuthProvider? _authProvider;
  late final List<Widget?> _screenCache;

  // BoardScreen 스크롤 제어를 위한 GlobalKey
  final GlobalKey<BoardScreenState> _boardScreenKey =
      GlobalKey<BoardScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // 초기 탭 인덱스 설정 (레거시 인덱스 대비 보정)
    _selectedIndex = _normalizeInitialIndex(widget.initialTabIndex);
    _screenCache = List<Widget?>.filled(_kTabCount, null);
    _ensureScreenBuilt(_selectedIndex);

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

      // 실시간 배지 리스너 시작 (알림/DM 변경 시 자동 업데이트)
      BadgeService.startRealtimeBadgeSync().catchError((e) {
        Logger.error('실시간 배지 동기화 시작 실패', e);
      });
    });
  }

  // 레거시 호출부(모임 탭=1 등)가 범위를 벗어나지 않도록 보정.
  // 현재 스키마: 0=Board, 1=Groups, 2=DM, 3=MyPage.
  int _normalizeInitialIndex(int raw) {
    if (raw >= 0 && raw < _kTabCount) return raw;
    // 레거시(5탭) 매핑: Board(0)/Meetup(1)/Groups(2)/MyPage(3)/DM(4)
    if (raw == 4) return 2; // 레거시 DM
    return 0;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _authProvider?.unregisterStreamCleanup(_cleanupCallback);

    // 서비스 정리
    _notificationService.dispose();

    // 실시간 배지 리스너 중지
    BadgeService.stopRealtimeBadgeSync();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      BadgeService.syncAndroidBadgeOnResume();
      // 앱이 백그라운드에서 포그라운드로 돌아올 때, Firestore stream이 suspend 중
      // 일시적으로 끊겼을 수 있다. 현재 캐시 기준으로 즉시 재emit해 BoardScreen의
      // StreamBuilder가 waiting 상태에 고정되지 않게 한다.
      PostService.instance.requestReemitWithCurrentFilters();
    }
  }

  Widget _buildScreenForIndex(int index) {
    switch (index) {
      case 0:
        return BoardScreen(key: _boardScreenKey);
      case 1:
        return FriendCategoriesScreen(
          initialTabIndex: widget.initialGroupTabIndex,
        );
      case 2:
        return const DMListScreen();
      case 3:
        return const MyPageScreen();
      default:
        return const SizedBox.shrink();
    }
  }

  void _ensureScreenBuilt(int index) {
    if (index < 0 || index >= _kTabCount) return;
    if (_screenCache[index] != null) return;
    _screenCache[index] = _buildScreenForIndex(index);
  }

  void _onItemTapped(int index) {
    // 이미 선택된 Board 탭(index 0)을 다시 탭하면 맨 위로 스크롤
    if (index == 0 && _selectedIndex == 0) {
      _boardScreenKey.currentState?.scrollToTop();
      return;
    }

    setState(() {
      _selectedIndex = index;
      _ensureScreenBuilt(index);
    });

    // 실시간 리스너가 배지를 자동으로 업데이트하므로 수동 호출 불필요
  }

  void _navigateToSearchPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UnifiedSearchScreen(
          // 기본은 친구(이름) 검색 탭으로 시작
          initialTabIndex: 0,
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
                            '회원가입을 먼저 진행해주세요.',
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
            // 돋보기 아이콘 (나눔 피드 탭에서만 표시)
            if (_selectedIndex == 0) ...[
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
                          // 종 아이콘으로 알림 화면을 열면 즉시 "모두 읽음" 처리하여
                          // 배지(앱 아이콘/상단 뱃지)를 0으로 동기화한다.
                          builder: (_) => const NotificationScreen(
                            markAllAsReadOnOpen: true,
                          ),
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
      body: IndexedStack(
        index: _selectedIndex,
        children: List.generate(
          _kTabCount,
          (i) => _screenCache[i] ?? const SizedBox.shrink(),
        ),
      ),

      // 완전 반응형 하단 네비게이션 (나눔 피드 / 그룹 / DM / 마이페이지)
      bottomNavigationBar: StreamBuilder<int>(
        stream: _dmService.getTotalUnreadCount(),
        builder: (context, dmSnapshot) {
          return StreamBuilder<int>(
            stream: _snackChatService.getFavoritedUnreadCount(),
            builder: (context, scSnapshot) {
              final l10n = AppLocalizations.of(context)!;

              if (dmSnapshot.hasError) {
                Logger.error('DM 배지 스트림 오류', dmSnapshot.error);
              }
              if (scSnapshot.hasError) {
                Logger.error('스낵챗 배지 스트림 오류', scSnapshot.error);
              }

              final unreadDMCount = dmSnapshot.data ?? 0;
              final unreadSnackChatCount = scSnapshot.data ?? 0;
              final isKo = Localizations.localeOf(context).languageCode == 'ko';

              return AdaptiveBottomNavigation(
                selectedIndex: _selectedIndex,
                onItemTapped: _onItemTapped,
                items: [
                  BottomNavigationItem(
                    icon: Icons.volunteer_activism_outlined,
                    selectedIcon: Icons.volunteer_activism,
                    label: isKo ? '나눔' : 'Sharing',
                  ),
                  BottomNavigationItem(
                    icon: Icons.groups_outlined,
                    selectedIcon: Icons.groups,
                    label: l10n.groups,
                    badgeCount: unreadSnackChatCount,
                  ),
                  BottomNavigationItem(
                    icon: Icons.chat_bubble_outline_rounded,
                    selectedIcon: Icons.chat_bubble_rounded,
                    label: l10n.dm,
                    badgeCount: unreadDMCount,
                  ),
                  BottomNavigationItem(
                    icon: Icons.account_circle_outlined,
                    selectedIcon: Icons.account_circle,
                    label: l10n.myPage,
                  ),
                ],
              );
            },
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
