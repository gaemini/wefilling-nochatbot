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
import '../constants/app_constants.dart';

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
      backgroundColor: const Color(0xFFEBEBEB),
      appBar: AppBar(
        toolbarHeight: 0,
        elevation: 0,
        backgroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: TabBar(
            controller: _tabController,
            isScrollable: false,
            labelColor: AppColors.pointColor,
            unselectedLabelColor: const Color(0xFF9CA3AF),
            labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            indicator: const BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.pointColor,
                  width: 2.5,
                ),
              ),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            tabs: [
            Tab(
              height: 52,
              child: Consumer<RelationshipProvider>(
                builder: (context, provider, child) {
                  final friendsCount = provider.friends.length;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.people_outline, size: 20),
                      const SizedBox(height: 2),
                      Flexible(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                AppLocalizations.of(context)!.friends,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 2),
                            if (friendsCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE5E7EB),
                                  borderRadius: BorderRadius.circular(7),
                                ),
                                child: Text(
                                  friendsCount > 99 ? '99+' : friendsCount.toString(),
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Tab(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_outlined, size: 20),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.search,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Tab(
              height: 52,
              child: Consumer<RelationshipProvider>(
                builder: (context, provider, child) {
                  final incomingCount = provider.incomingRequests.length;
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.mail_outline, size: 20),
                          const SizedBox(height: 2),
                          Text(
                            AppLocalizations.of(context)!.requests,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      if (incomingCount > 0)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 15,
                              minHeight: 15,
                            ),
                            child: Text(
                              incomingCount > 99 ? '99+' : incomingCount.toString(),
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
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
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.category_outlined, size: 20),
                  const SizedBox(height: 2),
                  Text(
                    AppLocalizations.of(context)!.groups,
                    style: const TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
          ),
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
