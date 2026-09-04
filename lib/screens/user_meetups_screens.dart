// 마이페이지의 통합 모임 목록

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/meetup.dart';
import '../services/user_stats_service.dart';
import '../ui/widgets/meetup_home_card.dart';
import 'meetup_detail_screen.dart';

/// 주최/참여 목록을 하나로 합치고 동일한 모임은 한 번만 표시한다.
List<Meetup> mergeMyMeetups(
  Iterable<Meetup> hosted,
  Iterable<Meetup> joined,
) {
  final byId = <String, Meetup>{};
  for (final meetup in [...hosted, ...joined]) {
    final key = meetup.id.trim();
    if (key.isEmpty) continue;
    byId[key] = meetup;
  }
  return byId.values.toList(growable: false)
    ..sort((a, b) => b.date.compareTo(a.date));
}

/// 마이페이지 탭 안에서 사용하는 내 모임 목록.
///
/// 주최/참여를 별도 탭으로 나누지 않으며 메인 밋업 화면과 같은 카드를 쓴다.
class UserMeetupsView extends StatefulWidget {
  const UserMeetupsView({super.key});

  @override
  State<UserMeetupsView> createState() => _UserMeetupsViewState();
}

class _UserMeetupsViewState extends State<UserMeetupsView> {
  final UserStatsService _userStatsService = UserStatsService();

  void _openMeetup(Meetup meetup) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MeetupDetailScreen(
          meetup: meetup,
          meetupId: meetup.id,
          onMeetupDeleted: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.white,
      child: StreamBuilder<List<Meetup>>(
        stream: _userStatsService.getHostedMeetups(),
        builder: (context, hostedSnapshot) {
          return StreamBuilder<List<Meetup>>(
            stream: _userStatsService.getJoinedMeetups(),
            builder: (context, joinedSnapshot) {
              final hosted = hostedSnapshot.data ?? const <Meetup>[];
              final joined = joinedSnapshot.data ?? const <Meetup>[];
              final isLoading = !hostedSnapshot.hasData &&
                  !joinedSnapshot.hasData &&
                  (hostedSnapshot.connectionState == ConnectionState.waiting ||
                      joinedSnapshot.connectionState ==
                          ConnectionState.waiting);

              if (isLoading) return _buildLoadingState();

              final hasUnavailableSource =
                  (hostedSnapshot.hasError && !hostedSnapshot.hasData) ||
                      (joinedSnapshot.hasError && !joinedSnapshot.hasData);
              if (hasUnavailableSource && hosted.isEmpty && joined.isEmpty) {
                return _buildErrorState();
              }

              final meetups = mergeMyMeetups(hosted, joined);
              if (meetups.isEmpty) return _buildEmptyState();
              return _buildMeetupList(meetups);
            },
          );
        },
      ),
    );
  }

  Widget _buildMeetupList(List<Meetup> meetups) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ListView.builder(
      key: const PageStorageKey('mypage_my_meetups_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(0, 6, 0, bottomInset + 20),
      itemCount: meetups.length,
      itemBuilder: (context, index) {
        final meetup = meetups[index];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: MeetupHomeCard(
                meetup: meetup,
                onTap: () => _openMeetup(meetup),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF2E90FA)),
    );
  }

  Widget _buildEmptyState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.event_available_outlined,
              size: 40,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.noMeetupsYet,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF475467),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 38,
              color: Color(0xFF98A2B3),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.meetupLoadError,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontFamilyFallback: ['NotoSansKR'],
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF667085),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {}),
              child: Text(l10n.retryAction),
            ),
          ],
        ),
      ),
    );
  }
}
