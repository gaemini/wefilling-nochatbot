import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/meetup.dart';
import '../../utils/responsive_helper.dart';
import 'audience_ring.dart';

/// 포스트 피드용 밋업 요약.
/// 날짜를 고정된 레일로 분리하고 관련 정보를 한 덩어리로 묶어 빠르게 훑을 수 있게 한다.
class BoardMeetupCard extends StatelessWidget {
  final Meetup meetup;
  final int? currentParticipants;
  final VoidCallback onTap;
  final VoidCallback? onLocationTap;
  final Widget? trailingAction;

  const BoardMeetupCard({
    super.key,
    required this.meetup,
    required this.onTap,
    this.currentParticipants,
    this.onLocationTap,
    this.trailingAction,
  });

  bool _isKorean(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'ko';

  String _monthLabel(BuildContext context) {
    final localDate = meetup.date.toLocal();
    if (_isKorean(context)) return '${localDate.month}월';
    return DateFormat('MMM', 'en_US').format(localDate).toUpperCase();
  }

  String _dayLabel() => '${meetup.date.toLocal().day}';

  String _weekdayLabel(BuildContext context) {
    final localDate = meetup.date.toLocal();
    if (_isKorean(context)) {
      const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      return weekdays[localDate.weekday - 1];
    }
    return DateFormat('EEE', 'en_US').format(localDate).toUpperCase();
  }

  String _timeLabel(BuildContext context) {
    final raw = meetup.time.trim();
    if (raw.isEmpty || raw == '미정' || raw == 'Undecided' || raw == 'TBD') {
      return AppLocalizations.of(context)?.undecided ?? 'TBD';
    }
    // 피드에서는 시작 시각만 보여주고 전체 시간 범위는 상세 화면에 유지한다.
    return raw.split('~').first.trim();
  }

  @override
  Widget build(BuildContext context) {
    final participants = currentParticipants ?? meetup.currentParticipants;
    final horizontal = context.rs(16).clamp(14.0, 18.0).toDouble();
    final metaSize = context.rf(12.5).clamp(12.0, 13.0).toDouble();
    final metaStyle = TextStyle(
      fontFamily: 'Pretendard',
      fontSize: metaSize,
      fontWeight: FontWeight.w600,
      height: 1.18,
      color: const Color(0xFF667085),
    );

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Material(
        color: Colors.white,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontal, 9, horizontal, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AudienceRing(
                  restricted: meetup.visibility != 'public',
                  size: context.rs(66).clamp(66.0, 68.0).toDouble(),
                  innerGap: 1.5,
                  borderRadius: BorderRadius.circular(
                    context.rs(16).clamp(14.0, 18.0).toDouble(),
                  ),
                  semanticLabel: _isKorean(context)
                      ? '공개 범위가 제한된 모임'
                      : 'Limited audience meetup',
                  child: ColoredBox(
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '${_monthLabel(context)} · ${_weekdayLabel(context)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize:
                                context.rf(9.5).clamp(9.0, 10.0).toDouble(),
                            fontWeight: FontWeight.w800,
                            height: 1,
                            letterSpacing: 0.2,
                            color: const Color(0xFF667085),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _dayLabel(),
                          maxLines: 1,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize:
                                context.rf(23).clamp(21.0, 24.0).toDouble(),
                            fontWeight: FontWeight.w800,
                            height: 1,
                            letterSpacing: -0.5,
                            color: const Color(0xFF101828),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _timeLabel(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize:
                                context.rf(10.5).clamp(10.0, 11.0).toDouble(),
                            fontWeight: FontWeight.w700,
                            height: 1.05,
                            color: const Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: context.rs(14).clamp(12.0, 16.0).toDouble()),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              meetup.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: context
                                    .rf(15.5)
                                    .clamp(14.5, 16.0)
                                    .toDouble(),
                                fontWeight: FontWeight.w800,
                                height: 1.18,
                                letterSpacing: -0.2,
                                color: const Color(0xFF101828),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.chevron_right_rounded,
                            size: 19,
                            color: Color(0xFF98A2B3),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      _InlineMeta(
                        icon: Icons.location_on_outlined,
                        text: meetup.location,
                        style: metaStyle,
                        onTap: onLocationTap,
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 10,
                            backgroundColor: const Color(0xFFF2F4F7),
                            backgroundImage: meetup.hostPhotoURL.isNotEmpty
                                ? NetworkImage(meetup.hostPhotoURL)
                                : null,
                            child: meetup.hostPhotoURL.isEmpty
                                ? const Icon(
                                    Icons.person_outline,
                                    size: 11,
                                    color: Color(0xFF667085),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              meetup.hostNickname ??
                                  AppLocalizations.of(context)!.anonymous,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: metaStyle.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF344054),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(
                            Icons.people_outline_rounded,
                            size: 15,
                            color: Color(0xFF667085),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$participants / ${meetup.maxParticipants}',
                            maxLines: 1,
                            style: metaStyle.copyWith(
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF475467),
                            ),
                          ),
                          if (trailingAction != null) ...[
                            const SizedBox(width: 8),
                            trailingAction!,
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineMeta extends StatelessWidget {
  final IconData icon;
  final String text;
  final TextStyle style;
  final VoidCallback? onTap;

  const _InlineMeta({
    required this.icon,
    required this.text,
    required this.style,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Icon(
          icon,
          size: context.ri(15).clamp(14.0, 15.5).toDouble(),
          color: const Color(0xFF667085),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style.copyWith(
              decoration: onTap == null ? null : TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return content;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: content,
    );
  }
}
