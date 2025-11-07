// lib/screens/user_meetups_screen.dart
// 마이페이지에서 모임 확인 용도

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          AppLocalizations.of(context)!.myMeetups ?? "",
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Color(0xFF111827),
          ),
        ),
        centerTitle: false,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF111827),
          unselectedLabelColor: const Color(0xFF9CA3AF),
          indicatorColor: const Color(0xFF5865F2),
          indicatorWeight: 2.5,
          labelStyle: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
          tabs: [
            Tab(text: AppLocalizations.of(context)!.hostedMeetups),
            Tab(text: AppLocalizations.of(context)!.joinedMeetups),
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
                  AppLocalizations.of(context)!.meetupLoadError,
                  () => setState(() {}),
                );
              }

              final meetups = snapshot.data ?? [];

              if (meetups.isEmpty) {
                return ErrorHandlingUtils.buildEmptyWidget(
                  AppLocalizations.of(context)!.hostedMeetupsEmpty,
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
                  AppLocalizations.of(context)!.meetupLoadError,
                  () => setState(() {}),
                );
              }

              // null 체크를 명시적으로 수행
              final meetups = snapshot.data ?? [];

              // 빈 리스트 체크
              if (meetups.isEmpty) {
                return ErrorHandlingUtils.buildEmptyWidget(
                  AppLocalizations.of(context)!.joinedMeetupsEmpty,
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
      return ErrorHandlingUtils.buildEmptyWidget(AppLocalizations.of(context)!.noMeetupsYet);
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
        Color statusBgColor;

        // 상태에 따른 색상 설정
        switch (statusText) {
          case '예정':
          case 'Scheduled':
            statusColor = const Color(0xFF10B981);
            statusBgColor = const Color(0xFFD1FAE5);
            break;
          case '진행중':
          case 'Ongoing':
            statusColor = const Color(0xFF3B82F6);
            statusBgColor = const Color(0xFFDBEAFE);
            break;
          case '종료':
          case 'Closed':
            statusColor = const Color(0xFF6B7280);
            statusBgColor = const Color(0xFFF3F4F6);
            break;
          default:
            statusColor = const Color(0xFF111827);
            statusBgColor = const Color(0xFFF3F4F6);
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
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
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              formattedDate,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              meetup.time,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 6),
                            // 모임 상태 표시
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: statusBgColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                statusText,
                                style: TextStyle(
                                  fontFamily: 'Pretendard',
                                  color: statusColor,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11,
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
                                fontFamily: 'Pretendard',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF111827),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: _isUrl(meetup.location)
                                      ? GestureDetector(
                                          onTap: () => _openUrl(meetup.location),
                                          child: Text(
                                            meetup.location,
                                            style: const TextStyle(
                                              fontFamily: 'Pretendard',
                                              fontSize: 13,
                                              fontWeight: FontWeight.w400,
                                              color: Color(0xFF5865F2),
                                              decoration: TextDecoration.underline,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )
                                      : Text(
                                          meetup.location,
                                          style: const TextStyle(
                                            fontFamily: 'Pretendard',
                                            fontSize: 13,
                                            fontWeight: FontWeight.w400,
                                            color: Color(0xFF6B7280),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.people_outline,
                                  size: 16,
                                  color: Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${meetup.currentParticipants}/${meetup.maxParticipants}${AppLocalizations.of(context)!.peopleUnit}',
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF6B7280),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // 모임 가득 참 표시
                                if (meetup.isFull())
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      AppLocalizations.of(context)!.fullShort,
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        color: Color(0xFFEF4444),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // 호스트 표시
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_outline,
                                  size: 16,
                                  color: Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${AppLocalizations.of(context)!.organizer}: ${meetup.host}',
                                  style: const TextStyle(
                                    fontFamily: 'Pretendard',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    color: Color(0xFF6B7280),
                                  ),
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

  /// URL인지 확인하는 함수
  bool _isUrl(String text) {
    final urlPattern = RegExp(
      r'^(https?:\/\/)?(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text);
  }

  /// URL을 여는 함수
  Future<void> _openUrl(String urlString) async {
    try {
      // URL이 http:// 또는 https://로 시작하지 않으면 추가
      if (!urlString.startsWith('http://') && !urlString.startsWith('https://')) {
        urlString = 'https://$urlString';
      }

      final uri = Uri.parse(urlString);
      
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${AppLocalizations.of(context)!.error}: URL을 열 수 없습니다'),
              backgroundColor: const Color(0xFFEF4444),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${AppLocalizations.of(context)!.error}: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }
}
