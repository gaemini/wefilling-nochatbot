import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../constants/app_constants.dart';
import '../../models/meetup.dart';

/// 게시글(Today)에서만 사용하는 **간단한 모임 카드**.
/// - 참여/나가기 버튼 없음 (탭하면 상세로 이동)
/// - 참여자 수는 외부에서 스트림으로 주입받아 실시간 반영
class BoardMeetupCard extends StatelessWidget {
  final Meetup meetup;
  final int? currentParticipants;
  final VoidCallback onTap;

  const BoardMeetupCard({
    super.key,
    required this.meetup,
    required this.onTap,
    this.currentParticipants,
  });

  String _startTimeLabel(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '미정';
    if (t == '미정') return '미정';
    if (!t.contains(':')) return t; // 예: "오후 2시" 같은 포맷도 그대로
    return t.split('~').first.trim();
  }

  Color _categoryColor(String category) {
    switch (category) {
      case '스터디':
        return const Color(0xFF4F46E5); // indigo
      case '식사':
        return const Color(0xFFEA580C); // orange
      case '카페':
        return const Color(0xFF0EA5E9); // sky
      case '술':
        return const Color(0xFFEF4444); // red
      case '문화':
        return const Color(0xFFEC4899); // pink
      default:
        return AppColors.pointColor;
    }
  }

  String _dateLabel(BuildContext context, DateTime date) {
    final code = Localizations.localeOf(context).languageCode;
    final locale = code == 'ko' ? 'ko_KR' : 'en_US';
    final local = date.toLocal();
    return code == 'ko'
        ? DateFormat('M월 d일 (E)', locale).format(local)
        : DateFormat('MMM d (EEE)', locale).format(local);
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now().toLocal();
    final d = date.toLocal();
    return now.year == d.year && now.month == d.month && now.day == d.day;
  }

  String _compactDateForCard(BuildContext context, DateTime date) {
    final code = Localizations.localeOf(context).languageCode;
    final local = date.toLocal();
    if (code == 'ko') {
      return '${local.month}월 ${local.day}일';
    }
    return '${local.month}/${local.day}';
  }

  @override
  Widget build(BuildContext context) {
    final participants = currentParticipants ?? meetup.currentParticipants;
    final timeLabel = _startTimeLabel(meetup.time);
    final isTimeUndecided = timeLabel == '미정' || timeLabel.trim().isEmpty;
    final categoryColor = _categoryColor(meetup.category);
    final isToday = _isToday(meetup.date);
    final dateLabel =
        isToday ? 'Today' : _compactDateForCard(context, meetup.date);
    final remainingSlots = (meetup.maxParticipants - participants);
    final isAlmostFull = remainingSlots == 1;
    final countColor = isAlmostFull ? const Color(0xFFEF4444) : const Color(0xFF6B7280);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 날짜/시간(핵심 정보) 강조
                  Container(
                    width: 86,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                    decoration: BoxDecoration(
                      color: isToday ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 날짜/Today: 박스 폭에 맞게 자동 축소(줄바꿈/깨짐 방지)
                        SizedBox(
                          height: 22,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              dateLabel,
                              style: const TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111827),
                                height: 1.1,
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          timeLabel,
                          style: TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: isTimeUndecided ? 12 : 13,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B7280),
                            height: 1.15,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                meetup.title,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF111827),
                                  height: 1.25,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.chevron_right_rounded,
                              size: 22,
                              color: Color(0xFF9CA3AF),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(
                              Icons.location_on_outlined,
                              size: 16,
                              color: Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                meetup.location,
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.people_outline,
                              size: 16,
                              color: Color(0xFF6B7280),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '$participants/${meetup.maxParticipants}명',
                              style: TextStyle(
                                fontFamily: 'Pretendard',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: countColor,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFFE5E7EB),
                    backgroundImage: meetup.hostPhotoURL.isNotEmpty
                        ? NetworkImage(meetup.hostPhotoURL)
                        : null,
                    child: meetup.hostPhotoURL.isEmpty
                        ? const Icon(
                            Icons.person,
                            size: 16,
                            color: Color(0xFF6B7280),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      meetup.hostNickname ?? '익명',
                      style: const TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: categoryColor.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: categoryColor.withOpacity(0.32),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      meetup.category,
                      style: TextStyle(
                        fontFamily: 'Pretendard',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: categoryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

