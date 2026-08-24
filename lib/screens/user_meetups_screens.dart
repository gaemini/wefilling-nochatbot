// lib/screens/user_meetups_screen.dart
// 마이페이지에서 모임 확인 용도

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/meetup.dart';
import '../l10n/app_localizations.dart';
import '../services/user_stats_service.dart';
import '../screens/meetup_detail_screen.dart';
import '../utils/responsive_helper.dart';

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
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        toolbarHeight: width < 360 ? 52 : 56,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Color(0xFF111827),
          ),
          iconSize: 22,
          onPressed: () => Navigator.pop(context),
        ),
        title: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Text(
            AppLocalizations.of(context)!.myMeetups,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Inter',
              fontFamilyFallback: const ['NotoSansKR'],
              fontSize: context.rf(18).clamp(17, 19).toDouble(),
              fontWeight: FontWeight.w700,
              color: const Color(0xFF111827),
            ),
          ),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(width < 360 ? 46 : 48),
          child: SizedBox(
            height: width < 360 ? 46 : 48,
            child: MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.2,
              child: TabBar(
                controller: _tabController,
                labelColor: const Color(0xFF111827),
                unselectedLabelColor: const Color(0xFF98A2B3),
                indicatorColor: const Color(0xFF344054),
                indicatorWeight: 2,
                indicatorSize: TabBarIndicatorSize.label,
                dividerColor: const Color(0xFFEAECF0),
                labelPadding:
                    EdgeInsets.symmetric(horizontal: width < 360 ? 6 : 10),
                labelStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(14).clamp(13, 15).toDouble(),
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(14).clamp(13, 15).toDouble(),
                  fontWeight: FontWeight.w500,
                ),
                tabs: [
                  Tab(text: AppLocalizations.of(context)!.hostedMeetups),
                  Tab(text: AppLocalizations.of(context)!.joinedMeetups),
                ],
              ),
            ),
          ),
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
                return _buildLoadingState();
              }

              if (snapshot.hasError) {
                return _buildErrorState(
                  AppLocalizations.of(context)!.meetupLoadError,
                );
              }

              final meetups = snapshot.data ?? [];

              if (meetups.isEmpty) {
                return _buildEmptyState(
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
                return _buildLoadingState();
              }

              if (snapshot.hasError) {
                return _buildErrorState(
                  AppLocalizations.of(context)!.meetupLoadError,
                );
              }

              // null 체크를 명시적으로 수행
              final meetups = snapshot.data ?? [];

              // 빈 리스트 체크
              if (meetups.isEmpty) {
                return _buildEmptyState(
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
    if (meetups.isEmpty) {
      return _buildEmptyState(AppLocalizations.of(context)!.noMeetupsYet);
    }

    meetups.sort((a, b) => b.date.compareTo(a.date));
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return ListView.separated(
      itemCount: meetups.length,
      padding: EdgeInsets.only(bottom: bottomInset + 12),
      separatorBuilder: (_, __) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final meetup = meetups[index];
        return _buildMeetupRow(meetup);
      },
    );
  }

  Widget _buildMeetupRow(Meetup meetup) {
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 360;
    final horizontalPadding = isCompact ? 12.0 : (width < 600 ? 16.0 : 24.0);
    final dateWidth = isCompact ? 74.0 : 88.0;
    final formattedDate = DateFormat('yyyy.MM.dd').format(meetup.date);
    final statusText = meetup.getStatus(
      languageCode: Localizations.localeOf(context).languageCode,
    );
    final l10n = AppLocalizations.of(context)!;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.white,
              child: InkWell(
                onTap: () => _openMeetup(meetup),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    isCompact ? 10 : 12,
                    horizontalPadding - 4,
                    isCompact ? 10 : 12,
                  ),
                  child: MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.2,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: dateWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                formattedDate,
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: context
                                      .rf(12.5)
                                      .clamp(11.5, 13)
                                      .toDouble(),
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF344054),
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                meetup.time,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF8B93A1),
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF667085),
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: isCompact ? 8 : 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                meetup.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  fontFamilyFallback: const ['NotoSansKR'],
                                  fontSize:
                                      context.rf(14).clamp(13, 15).toDouble(),
                                  fontWeight: FontWeight.w700,
                                  color: const Color(0xFF111827),
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 7),
                              _buildInfoLine(
                                icon: Icons.location_on_outlined,
                                child: _buildLocation(meetup.location),
                              ),
                              const SizedBox(height: 4),
                              _buildInfoLine(
                                icon: Icons.people_outline_rounded,
                                child: Text(
                                  '${meetup.currentParticipants}/${meetup.maxParticipants} ${l10n.peopleUnit.trim()}'
                                  '${meetup.isFull() ? ' · ${l10n.fullShort}' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _metadataStyle,
                                ),
                              ),
                              const SizedBox(height: 4),
                              _buildInfoLine(
                                icon: Icons.person_outline_rounded,
                                child: Text(
                                  '${l10n.organizer}: ${meetup.host}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _metadataStyle,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 2),
                        const SizedBox.square(
                          dimension: 32,
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 19,
                            color: Color(0xFF98A2B3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              indent: horizontalPadding + dateWidth + (isCompact ? 8 : 12),
              endIndent: horizontalPadding,
              color: const Color(0xFFEAECF0),
            ),
          ],
        ),
      ),
    );
  }

  TextStyle get _metadataStyle => const TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: const ['NotoSansKR'],
        fontSize: 12.5,
        fontWeight: FontWeight.w500,
        color: Color(0xFF667085),
        height: 1.2,
      );

  Widget _buildInfoLine({required IconData icon, required Widget child}) {
    return Row(
      children: [
        Icon(icon, size: 15, color: const Color(0xFF8B93A1)),
        const SizedBox(width: 5),
        Expanded(child: child),
      ],
    );
  }

  Widget _buildLocation(String location) {
    final text = Text(
      location,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: _metadataStyle.copyWith(
        decoration: _isUrl(location) ? TextDecoration.underline : null,
        decorationColor: const Color(0xFF667085),
      ),
    );
    if (!_isUrl(location)) return text;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openUrl(location),
      child: text,
    );
  }

  void _openMeetup(Meetup meetup) {
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
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF667085)),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.event_available_outlined,
              size: 32,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 34,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {}),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF344054),
              ),
              child: Text(AppLocalizations.of(context)!.retryAction),
            ),
          ],
        ),
      ),
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
      if (!urlString.startsWith('http://') &&
          !urlString.startsWith('https://')) {
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
              content:
                  Text('${AppLocalizations.of(context)!.error}: URL을 열 수 없습니다'),
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
