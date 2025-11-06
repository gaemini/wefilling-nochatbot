// lib/screens/user_meetups_screen.dart
// 마이페이지에서 모임 확인 용도

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/meetup.dart';
import '../l10n/app_localizations.dart';
import '../services/user_stats_service.dart';
import '../screens/meetup_detail_screen.dart';
import '../utils/error_handling_utils.dart';

class UserMeetupsScreen extends StatefulWidget {
  const UserMeetupsScreen({Key? key}) : super(key: key);

  @override
  State<UserMeetupsScreen> createState() => _UserMeetupsScreenState();
}

class _UserMeetupsScreenState extends State<UserMeetupsScreen>
    with SingleTickerProviderStateMixin {
  final UserStatsService _userStatsService = UserStatsService();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
        title: Text(AppLocalizations.of(context)?.myMeetups),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: AppLocalizations.of(context)?.hostedMeetups),
            Tab(text: AppLocalizations.of(context)?.joinedMeetups),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 주최한 모임 탭
          StreamBuilder<List<Meetup>>(
            stream: _userStatsService.getHostedMeetups(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return ErrorHandlingUtils.buildErrorWidget(
                  AppLocalizations.of(context)?.meetupLoadError,
                  () => setState(() {}),
                );
              }

              final meetups = snapshot.data ?? [];

              if (meetups.isEmpty) {
                return ErrorHandlingUtils.buildEmptyWidget(
                  AppLocalizations.of(context)?.hostedMeetupsEmpty,
                );
              }

              return _buildMeetupList(meetups);
            },
          ),

          // 참여했던 모임 탭 (사용자가 주최하지 않고 참여한 모임)
          StreamBuilder<List<Meetup>>(
            stream: _userStatsService.getJoinedMeetups(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return ErrorHandlingUtils.buildErrorWidget(
                  AppLocalizations.of(context)?.meetupLoadError,
                  () => setState(() {}),
                );
              }

              // null 체크를 명시적으로 수행
              final meetups = snapshot.data ?? [];

              // 빈 리스트 체크
              if (meetups.isEmpty) {
                return ErrorHandlingUtils.buildEmptyWidget(
                  AppLocalizations.of(context)?.joinedMeetupsEmpty,
                );
              }

              // 이 부분에서 안전하게 리스트가 있는지 확인
              return _buildMeetupList(meetups);
            },
          ),
        ],
      ),
    );
  }

  // 모임 목록 위젯
  Widget _buildMeetupList(List<Meetup> meetups) {
    // 빈 리스트 체크 추가
    if (meetups.isEmpty) {
      return ErrorHandlingUtils.buildEmptyWidget(AppLocalizations.of(context)?.noMeetupsYet);
    }

    // 날짜별로 모임 정렬 (최신순으로 변경)
    meetups.sort((a, b) => b.date.compareTo(a.date));

    return ListView.builder(
      itemCount: meetups.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final meetup = meetups[index];
        final formattedDate = DateFormat('yyyy-MM-dd').format(meetup.date);

        // 모임 상태 확인
        final String statusText = meetup.getStatus(
          languageCode: Localizations.localeOf(context).languageCode,
        );
        Color statusColor;

        // 상태에 따른 색상 설정
        switch (statusText) {
          case '예정':
          case 'Scheduled':
            statusColor = Colors.green;
            break;
          case '진행중':
          case 'Ongoing':
            statusColor = Colors.blue;
            break;
          case '종료':
          case 'Closed':
            statusColor = Colors.grey;
            break;
          default:
            statusColor = Colors.black;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => MeetupDetailScreen(
                    meetup: meetup,
                    meetupId: meetup.id,
                    onMeetupDeleted: () {
                      Navigator.pop(context);
                      setState(() {});
                    },
                  ),
                ),
              );
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 왼쪽 날짜와 시간
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withAlpha(26),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formattedDate,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              meetup.time,
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 4),
                            // 모임 상태 표시 추가
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: statusColor.withAlpha(51),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  color: statusColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(width: 16),

                      // 오른쪽 모임 정보
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              meetup.title,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    meetup.location,
                                    style: TextStyle(color: Colors.grey[600]),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${meetup.currentParticipants}/${meetup.maxParticipants}${AppLocalizations.of(context)?.peopleUnit}',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                                const SizedBox(width: 8),
                                // 모임 가득 참 표시
                                if (meetup.isFull())
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withAlpha(26),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: Colors.red.withAlpha(77),
                                      ),
                                    ),
                                    child: Text(
                                      AppLocalizations.of(context)?.fullShort,
                                      style: TextStyle(
                                        color: Colors.red[700],
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // 호스트 표시
                            Row(
                              children: [
                                Icon(
                                  Icons.face,
                                  size: 16,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${AppLocalizations.of(context)?.organizer}: ${meetup.host}',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
