// lib/widgets/meetup_card.dart
// 모임 카드 위젯 구현
// 모임 정보 표시 및 참여 버튼 제공

import 'package:flutter/material.dart';
import '../models/meetup.dart';
import '../constants/app_constants.dart';
import '../screens/meetup_detail_screen.dart';

class MeetupCard extends StatelessWidget {
  final Meetup meetup;
  final Function(Meetup) onJoinMeetup;
  final String meetupId; // 이미 String 타입
  final Function onMeetupDeleted;

  const MeetupCard({
    Key? key,
    required this.meetup,
    required this.onJoinMeetup,
    required this.meetupId, // 이미 String으로 정의됨
    required this.onMeetupDeleted,
  }) : super(key: key);

  String _getStatusButton() {
    final isFull = meetup.currentParticipants >= meetup.maxParticipants;
    return isFull ? AppConstants.FULL : AppConstants.JOIN;
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case '스터디':
        return Colors.blue.shade700;
      case '식사':
        return Colors.orange.shade700;
      case '취미':
        return Colors.green.shade700;
      case '문화':
        return Colors.purple.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _getStatusButton();
    final isFull = meetup.currentParticipants >= meetup.maxParticipants;

    return InkWell(
      onTap: () {
        // 모임 상세 화면 표시
        showDialog(
          context: context,
          builder:
              (context) => MeetupDetailScreen(
                meetup: meetup,
                meetupId: meetupId, // meetup.id.toString() 변환 제거
                onMeetupDeleted: onMeetupDeleted,
              ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // 시간 컬럼 - 원형 시간 표시로 개선
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue.shade200, width: 2),
                ),
                child: Center(
                  child: Text(
                    meetup.time.split('~')[0].trim(), // 시작 시간만 표시
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // 모임 내용 컬럼
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 모임 제목
                    Text(
                      meetup.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 모임 위치
                    Row(
                      children: [
                        Icon(
                          Icons.location_on,
                          size: 14,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            meetup.location,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 참가자 정보
                    Row(
                      children: [
                        Icon(
                          Icons.person,
                          size: 14,
                          color: Colors.blue.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${meetup.currentParticipants}/${meetup.maxParticipants}명',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.blue.shade700,
                          ),
                        ),
                        const SizedBox(width: 8),

                        // 주최자 정보
                        Icon(Icons.star, size: 14, color: Colors.amber[600]),
                        const SizedBox(width: 4),
                        Text(
                          meetup.host,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: _getCategoryColor(
                          meetup.category,
                        ).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _getCategoryColor(
                            meetup.category,
                          ).withOpacity(0.5),
                          width: 1,
                        ),
                      ),
                      child: Text(
                        meetup.category,
                        style: TextStyle(
                          fontSize: 12,
                          color: _getCategoryColor(meetup.category),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              SizedBox(
                width: 70,
                child: ElevatedButton(
                  onPressed:
                      isFull
                          ? null
                          : () {
                            onJoinMeetup(meetup);
                          },
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        isFull ? Colors.grey[300] : Colors.blue.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    status,
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
