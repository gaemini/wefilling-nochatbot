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
import '../l10n/app_localizations.dart';

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
    _tabController = TabController(length: 4, vsync: this);
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
        title: Text(AppLocalizations.of(context)!.friends ?? ""),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          labelColor: Colors.blue,
          unselectedLabelColor: Colors.grey,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8), // 상하 패딩 추가
          indicator: BoxDecoration(
            color: const Color(0xFFE8F0FE),
            borderRadius: BorderRadius.circular(10),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: [
            Tab(
              height: 64, // 탭 높이 증가
              child: Consumer<RelationshipProvider>(
                builder: (context, provider, child) {
                  final friendsCount = provider.friends.length;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people, size: 24), // 아이콘 크기 증가
                      const SizedBox(height: 4), // 간격 증가
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              AppLocalizations.of(context)!.friends,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), // 폰트 크기 증가
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              friendsCount > 99 ? '99+' : friendsCount.toString(),
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            Tab(
              height: 64, // 탭 높이 증가
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search, size: 24), // 아이콘 크기 증가
                  const SizedBox(height: 4), // 간격 증가
                  Text(
                    AppLocalizations.of(context)!.search,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), // 폰트 크기 증가
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Tab(
              height: 64, // 탭 높이 증가
              child: Consumer<RelationshipProvider>(
                builder: (context, provider, child) {
                  final incomingCount = provider.incomingRequests.length;
                  return Stack(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mail, size: 24), // 아이콘 크기 증가
                          const SizedBox(height: 4), // 간격 증가
                          Text(
                            AppLocalizations.of(context)!.requests,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), // 폰트 크기 증가
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
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
                              incomingCount > 99 ? '99+' : incomingCount.toString(),
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
              height: 64, // 탭 높이 증가
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.category, size: 24), // 아이콘 크기 증가
                  const SizedBox(height: 4), // 간격 증가
                  Text(
                    AppLocalizations.of(context)!.category,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), // 폰트 크기 증가
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FriendsPage(),
          SearchUsersPage(),
          RequestsPage(),
          FriendCategoriesScreen(),
        ],
      ),
      // 친구 찾기 FAB (검색 탭에서만 표시)
      floatingActionButton:
          _tabController.index == 1
              ? AppFab.addFriend(
                onPressed: () {
                  // 검색 탭으로 포커스 이동 또는 검색 기능 실행
                  _tabController.animateTo(1);
                },
                heroTag: 'friends_search_fab',
              )
              : null,
    );
  }
}
