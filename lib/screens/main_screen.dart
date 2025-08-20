// lib/screens/main_screen.dart
// 앱의 메인화면 구현
// 하단 탭 네비게이션 제공
// 게시판, 모임, 마이페이지 화면 통합

import 'package:flutter/material.dart';
import '../constants/app_constants.dart';
import '../services/notification_service.dart';
import '../widgets/notification_badge.dart';
import 'board_screen.dart';
import 'mypage_screen.dart';
import 'notification_screen.dart';
import 'home_screen.dart';  // MeetupHomePage 클래스가 있는 파일

import '../utils/firebase_debug_helper.dart';
import 'firebase_security_rules_helper.dart';
import 'chatbot_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0; // 기본값으로 게시판 탭 선택
  final NotificationService _notificationService = NotificationService();

  // 화면 목록
  late final List<Widget> _screens = [
    const BoardScreen(),
    const MeetupHomePage(),
    const MyPageScreen(),
    const ChatbotScreen(),
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
    super.dispose();
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
        print('Firebase 콘솔 주소: https://console.firebase.google.com/project/$projectId/storage/rules');
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
      builder: (context) => AlertDialog(
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
                  builder: (context) => FirebaseSecurityRulesHelper(
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
        title: Text(
          'Wefilling',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.blueAccent,
          ),
        ),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          // 알림 버튼
          StreamBuilder<int>(
            stream: _notificationService.getUnreadNotificationCount(),
            builder: (context, snapshot) {
              final unreadCount = snapshot.data ?? 0;

              return NotificationBadge(
                count: unreadCount,
                child: IconButton(
                  icon: const Icon(Icons.notifications_none),
                  onPressed: () {
                    // 알림 화면으로 이동
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const NotificationScreen()),
                    );
                  },
                  tooltip: '알림',
                ),
              );
            },
          ),
        ],
      ),
      body: _screens[_selectedIndex],

      // 표준 하단 네비게이션 바로 변경 (ConvexAppBar 대신 BottomNavigationBar 사용)
      bottomNavigationBar: BottomNavigationBar(
        items: <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: const Icon(Icons.forum),
            label: AppConstants.BOARD,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.groups),
            label: AppConstants.MEETUP,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: AppConstants.MYPAGE,
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.smart_toy),
            label: '챗봇',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.blue,
        unselectedItemColor: Colors.grey,
        backgroundColor: Colors.white,
        elevation: 8,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}