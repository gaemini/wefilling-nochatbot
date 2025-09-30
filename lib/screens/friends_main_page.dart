// lib/screens/friends_main_page.dart
// 친구 관련 메인 화면 (탭바로 구성)
// 사용자 검색, 친구요청, 친구 목록을 탭으로 관리

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/relationship_provider.dart';
import '../ui/widgets/app_fab.dart';
import 'search_users_page.dart';
import 'requests_page.dart';
import 'friends_page.dart';
import 'friend_categories_screen.dart';

class FriendsMainPage extends StatefulWidget {
  const FriendsMainPage({super.key});

  @override
  State<FriendsMainPage> createState() => _FriendsMainPageState();
}

class _FriendsMainPageState extends State<FriendsMainPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      setState(() {}); // FAB 표시 상태 업데이트
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('친구'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        actions: [
          if (_tabController.index == 2) // 친구 탭에서만 표시
            IconButton(
              icon: const Icon(Icons.category),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FriendCategoriesScreen(),
                  ),
                );
              },
              tooltip: '카테고리 관리',
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.blue,
          tabs: [
            const Tab(icon: Icon(Icons.search), text: '검색'),
            Tab(
              child: Consumer<RelationshipProvider>(
                builder: (context, provider, child) {
                  final incomingCount = provider.incomingRequests.length;
                  return Stack(
                    children: [
                      const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [Icon(Icons.mail), Text('요청')],
                      ),
                      if (incomingCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              incomingCount > 99
                                  ? '99+'
                                  : incomingCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Tab(
              child: Consumer<RelationshipProvider>(
                builder: (context, provider, child) {
                  final friendsCount = provider.friends.length;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.people),
                      Text('친구 ($friendsCount)'),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [SearchUsersPage(), RequestsPage(), FriendsPage()],
      ),
      // 친구 찾기 FAB (검색 탭에서만 표시)
      floatingActionButton:
          _tabController.index == 0
              ? AppFab.addFriend(
                onPressed: () {
                  // 검색 탭으로 포커스 이동 또는 검색 기능 실행
                  _tabController.animateTo(0);
                },
                heroTag: 'friends_search_fab',
              )
              : null,
    );
  }
}
