// lib/screens/main_screen.dart
// 앱의 메인화면 구현
// 하단 탭 네비게이션 제공
// 게시판, 모임, 마이페이지 화면 통합

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:math' as math;
import '../constants/app_constants.dart';
import '../services/notification_service.dart';
import '../widgets/notification_badge.dart';
import '../ui/widgets/app_icon_button.dart';
import '../design/tokens.dart';
import '../providers/auth_provider.dart';
import 'board_screen.dart';
import 'mypage_screen.dart';
import 'notification_screen.dart';
import 'home_screen.dart'; // MeetupHomePage 클래스가 있는 파일
import 'friends_main_page.dart';
import 'search_result_page.dart';
import 'ad_showcase_screen.dart';
import 'dm_list_screen.dart';

import '../utils/firebase_debug_helper.dart';
import 'firebase_security_rules_helper.dart';
import '../widgets/adaptive_bottom_navigation.dart';
import '../l10n/app_localizations.dart';

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
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  late VoidCallback _cleanupCallback;
  String? _pendingMeetupId; // 알림으로 전달된 모임 ID (1회용)

  @override
  void initState() {
    super.initState();
    
    // 초기 탭 인덱스 설정
    _selectedIndex = widget.initialTabIndex;
    // 알림으로 넘어온 모임 ID는 최초 1회만 사용하도록 보관
    _pendingMeetupId = widget.initialMeetupId;
    
    // Firebase Storage 테스트
    _testFirebaseStorage();
    
    // 스트림 정리 콜백 등록
    _cleanupCallback = () {
      _notificationService.dispose();
    };
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.registerStreamCleanup(_cleanupCallback);
      
      // 로그인 실패(회원가입 필요) 후 메인으로 돌아온 경우 안내 표시
      if (authProvider.consumeSignupRequiredFlag()) {
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
    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      authProvider.unregisterStreamCleanup(_cleanupCallback);
    } catch (e) {
      print('MainScreen AuthProvider 콜백 제거 오류: $e');
    }
    
    // 서비스 정리
    _notificationService.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // 화면 목록 - 검색어를 전달할 수 있도록 수정
  List<Widget> get _screens => [
    BoardScreen(searchQuery: _searchController.text),
    // 알림에서 온 모임은 최초 1회만 자동 오픈되도록 전달
    MeetupHomePage(initialMeetupId: _pendingMeetupId),
    const DMListScreen(),
    const MyPageScreen(),
    const FriendsMainPage(),
  ];
  final FirebaseDebugHelper _firebaseDebugHelper = FirebaseDebugHelper();

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


  void _onSearchChanged() {
    setState(() {
      _isSearching = _searchController.text.isNotEmpty;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
    });
  }

  String _getSearchHint() {
    switch (_selectedIndex) {
      case 0:
        return AppLocalizations.of(context)!.enterSearchQuery ?? "";
      case 1:
        return AppLocalizations.of(context)!.enterSearchQuery ?? "";
      default:
        return AppLocalizations.of(context)!.search ?? "";
    }
  }

  String _getBoardType() {
    switch (_selectedIndex) {
      case 0:
        return 'info'; // 게시판
      case 1:
        return 'meeting'; // 모임
      default:
        return 'info';
    }
  }

  void _navigateToSearchPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SearchResultPage(
          boardType: _getBoardType(),
          initialQuery: _searchController.text,
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

  Future<void> _testFirebaseStorage() async {
    try {
      print('=========== Firebase Storage 진단 시작 ===========');
      final storageTest = await _firebaseDebugHelper.testFirebaseStorage();
      print('Storage 버킷: ${storageTest['storage_bucket']}');
      print('앱 이름: ${storageTest['app_name']}');

      // 루트 리스트 테스트 결과
      final listTest = storageTest['tests']['list_root'];
      if (listTest != null) {
        if (listTest['success'] == true) {
          print('스토리지 접근 권한: 성공');
          print('- 아이템 수: ${listTest['items_count']}');
          print('- 폴더 수: ${listTest['prefixes_count']}');
        } else {
          print('스토리지 접근 권한: 실패');
          print('- 오류: ${listTest['error']}');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showStorageSecurityAlert();
            }
          });
        }
      }

      // 업로드 테스트 결과
      final uploadTest = storageTest['tests']['upload_test'];
      if (uploadTest != null) {
        if (uploadTest['success'] == true) {
          print('파일 업로드 테스트: 성공');
          print('- 경로: ${uploadTest['path']}');
          print('- 다운로드 URL: ${uploadTest['download_url']}');

          // 테스트 URL의 유효성 테스트
          final testUrl = uploadTest['download_url'];
          if (testUrl != null) {
            final urlTest = await _firebaseDebugHelper.testImageUrl(testUrl);
            final httpResponse = urlTest['http_response'];
            if (httpResponse != null && httpResponse['success'] == true) {
              print('URL 접근 테스트: 성공 (상태 코드: ${httpResponse['status_code']})');
            } else {
              print('URL 접근 테스트: 실패');
              if (httpResponse != null && httpResponse['error'] != null) {
                print('- 오류: ${httpResponse['error']}');
              }
            }
          }
        } else {
          print('파일 업로드 테스트: 실패');
          print('- 오류: ${uploadTest['error']}');
        }
      }

      // 보안 규칙 테스트
      final securityTest = await _firebaseDebugHelper.testSecurityRules();
      print('보안 규칙 테스트: ${securityTest ? '성공' : '실패'}');

      // Firebase Storage 보안 규칙 수정 안내
      if (!securityTest) {
        // Firebase 프로젝트 ID 가져오기
        final projectId = _firebaseDebugHelper.projectId;

        print('\n=== 중요: Firebase Storage 보안 규칙 수정 필요 ===');
        print('Firebase Console에서 다음과 같이 Storage 규칙을 수정하세요:');
        print('''
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /{allPaths=**} {
      allow read: if true;  // 모든 사용자에게 읽기 권한 허용
      allow write: if request.auth != null;  // 인증된 사용자에게만 쓰기 권한 허용
    }
  }
}''');
        print(
          'Firebase 콘솔 주소: https://console.firebase.google.com/project/$projectId/storage/rules',
        );
      }

      print('=========== Firebase Storage 진단 완료 ===========');
    } catch (e) {
      print('Firebase Storage 진단 중 오류 발생: $e');
    }
  }

  // Firebase Storage 보안 규칙 문제 알림 표시
  void _showStorageSecurityAlert() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.amber),
                SizedBox(width: 10),
                Text('이미지 표시 문제 감지'),
              ],
            ),
            content: Text(
              '게시글 이미지가 표시되지 않는 문제가 감지되었습니다.\n'
              '이 문제는 Firebase Storage 보안 규칙 설정 때문일 가능성이 높습니다.\n\n'
              '문제 해결 안내 화면으로 이동하시겠습니까?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('나중에'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder:
                          (context) => FirebaseSecurityRulesHelper(
                            projectId: _firebaseDebugHelper.projectId,
                          ),
                    ),
                  );
                },
                child: Text('문제 해결하기'),
              ),
            ],
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                            style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('확인'),
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
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5865F2), // 위필링 시그니처 파란색으로 통일
                      letterSpacing: -0.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // 검색창 (가변 폭) - 정보게시판용
            Expanded(
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.grey.shade200,
                    width: 0.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: GestureDetector(
                  onTap: () => _navigateToSearchPage(),
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F6F8),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(
                          Icons.search,
                          color: Colors.black54,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getSearchHint(),
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
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
                  semanticLabel: '알림',
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _screens[_selectedIndex],

      // 완전 반응형 하단 네비게이션 (갤럭시 S23 등 모든 기기 대응)
      bottomNavigationBar: AdaptiveBottomNavigation(
        selectedIndex: _selectedIndex,
        onItemTapped: _onItemTapped,
        items: [
          BottomNavigationItem(
            icon: Icons.article_outlined, // 게시판 아이콘 변경 (DM과 구분)
            selectedIcon: Icons.article,
            label: AppLocalizations.of(context)!.board ?? '게시판',
          ),
          BottomNavigationItem(
            icon: Icons.groups_outlined,
            selectedIcon: Icons.groups,
            label: AppLocalizations.of(context)!.meetup ?? '모임',
          ),
          BottomNavigationItem(
            icon: Icons.chat_bubble_outline,
            selectedIcon: Icons.chat_bubble,
            label: AppLocalizations.of(context)!.dm ?? 'DM',
          ),
          BottomNavigationItem(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: AppLocalizations.of(context)!.myPage ?? '마이페이지',
          ),
          BottomNavigationItem(
            icon: Icons.people_outline,
            selectedIcon: Icons.people,
            label: AppLocalizations.of(context)!.friends ?? '친구',
          ),
        ],
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
