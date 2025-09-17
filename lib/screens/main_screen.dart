// lib/screens/main_screen.dart
// 앱의 메인화면 구현
// 하단 탭 네비게이션 제공
// 게시판, 모임, 마이페이지 화면 통합

import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../constants/app_constants.dart';
import '../services/notification_service.dart';
import '../widgets/notification_badge.dart';
import '../ui/widgets/app_icon_button.dart';
import '../design/tokens.dart';
import 'board_screen.dart';
import 'mypage_screen.dart';
import 'notification_screen.dart';
import 'home_screen.dart'; // MeetupHomePage 클래스가 있는 파일
import 'friends_main_page.dart';
import 'search_result_page.dart';

import '../utils/firebase_debug_helper.dart';
import 'firebase_security_rules_helper.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // 기본값으로 게시판 탭 선택
  final NotificationService _notificationService = NotificationService();
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

  // 화면 목록 - 검색어를 전달할 수 있도록 수정
  List<Widget> get _screens => [
    BoardScreen(searchQuery: _searchController.text),
    const MeetupHomePage(),
    const MyPageScreen(),
    const FriendsMainPage(),
  ];
  final FirebaseDebugHelper _firebaseDebugHelper = FirebaseDebugHelper();

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  void initState() {
    super.initState();
    _testFirebaseStorage();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
        return '게시글 검색...';
      case 1:
        return '모임 검색...';
      default:
        return '검색...';
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
            // Wefilling 로고 + 텍스트
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  child: _buildLogo(),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Wefilling',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4A90E2), // 브랜드 파란색
                    letterSpacing: -0.5,
                  ),
                ),
              ],
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

      // 접근성 기준을 준수하는 하단 네비게이션 바
      bottomNavigationBar: Container(
        height: DesignTokens.bottomNavHeight,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: DesignTokens.shadowMedium,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // 16dp 이상 간격 확보를 위해 Expanded 사용
            Expanded(
              child: AppBottomNavItem(
                icon: Icons.forum_outlined,
                selectedIcon: Icons.forum,
                label: AppConstants.BOARD,
                isSelected: _selectedIndex == 0,
                onTap: () => _onItemTapped(0),
              ),
            ),
            Expanded(
              child: AppBottomNavItem(
                icon: Icons.groups_outlined,
                selectedIcon: Icons.groups,
                label: AppConstants.MEETUP,
                isSelected: _selectedIndex == 1,
                onTap: () => _onItemTapped(1),
              ),
            ),
            Expanded(
              child: AppBottomNavItem(
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
                label: AppConstants.MYPAGE,
                isSelected: _selectedIndex == 2,
                onTap: () => _onItemTapped(2),
              ),
            ),
            Expanded(
              child: AppBottomNavItem(
                icon: Icons.people_outline,
                selectedIcon: Icons.people,
                label: '친구',
                isSelected: _selectedIndex == 3,
                onTap: () => _onItemTapped(3),
              ),
            ),
          ],
        ),
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
