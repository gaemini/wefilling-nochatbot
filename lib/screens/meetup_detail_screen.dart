// lib/screens/meetup_detail_screen.dart
// 모임 상세화면, 모임 정보 표시
// 모임 참여 및 취소 기능

import 'dart:math';
import 'package:flutter/material.dart';
import '../models/meetup.dart';
import '../services/meetup_service.dart';
import '../widgets/country_flag_circle.dart';

class MeetupDetailScreen extends StatefulWidget {
  final Meetup meetup;
  final String meetupId;
  final Function onMeetupDeleted;

  const MeetupDetailScreen({
    Key? key,
    required this.meetup,
    required this.meetupId,
    required this.onMeetupDeleted,
  }) : super(key: key);

  @override
  State<MeetupDetailScreen> createState() => _MeetupDetailScreenState();
}

class _MeetupDetailScreenState extends State<MeetupDetailScreen> {
  final MeetupService _meetupService = MeetupService();
  bool _isLoading = false;
  bool _isHost = false;

  @override
  void initState() {
    super.initState();
    _checkIfUserIsHost();
  }

  Future<void> _checkIfUserIsHost() async {
    final isHost = await _meetupService.isUserHostOfMeetup(widget.meetupId);
    if (mounted) {
      setState(() {
        _isHost = isHost;
      });
    }
  }

  Future<void> _deleteMeetup() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _meetupService.deleteMeetup(widget.meetupId);

      if (success) {
        if (mounted) {
          // 콜백 호출하여 부모 화면 업데이트
          widget.onMeetupDeleted();

          Navigator.of(context).pop();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('모임이 취소되었습니다.')));
        }
      } else if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('모임 취소에 실패했습니다. 다시 시도해주세요.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.meetup.getStatus();
    final isUpcoming = status == '예정';
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: Colors.white,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxWidth: min(500, size.width - 40),
          maxHeight: size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 헤더
            Container(
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          status,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.meetup.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${widget.meetup.date.month}월 ${widget.meetup.date.day}일',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(width: 16),
                      const Icon(
                        Icons.access_time,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        widget.meetup.time,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 내용
            Flexible(
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  _buildInfoItem(
                    Icons.calendar_today,
                    Colors.blue,
                    '날짜 및 시간',
                    '${widget.meetup.date.month}월 ${widget.meetup.date.day}일 (${widget.meetup.getFormattedDayOfWeek()}) ${widget.meetup.time}',
                  ),
                  _buildInfoItem(
                    Icons.location_on,
                    Colors.red,
                    '모임 장소',
                    widget.meetup.location,
                  ),
                  _buildInfoItem(
                    Icons.people,
                    Colors.amber,
                    '참가 인원',
                    '${widget.meetup.currentParticipants}/${widget.meetup.maxParticipants}명',
                  ),
                  _buildInfoItem(
                    Icons.person,
                    Colors.green,
                    '주최자',
                    "${widget.meetup.host} (국적: ${widget.meetup.hostNationality.isEmpty ? '없음' : widget.meetup.hostNationality})",
                    suffix:
                        widget.meetup.hostNationality.isNotEmpty
                            ? CountryFlagCircle(
                              nationality: widget.meetup.hostNationality,
                              size: 20,
                            )
                            : null,
                  ),
                  _buildInfoItem(
                    Icons.category,
                    _getCategoryColor(widget.meetup.category),
                    '카테고리',
                    widget.meetup.category,
                  ),

                  // 모임 설명
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '모임 설명',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.meetup.description,
                          style: const TextStyle(fontSize: 14),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 하단 버튼
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child:
                  _isHost
                      ? ElevatedButton(
                        onPressed: _isLoading ? null : _deleteMeetup,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child:
                            _isLoading
                                ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                                : const Text('모임 취소'),
                      )
                      : ElevatedButton(
                        onPressed:
                            isUpcoming && !widget.meetup.isFull()
                                ? () async {
                                  await _meetupService.joinMeetup(
                                    widget.meetupId,
                                  );
                                  if (mounted) {
                                    Navigator.of(context).pop();
                                  }
                                }
                                : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: Text(
                          widget.meetup.isFull() ? '참여 불가 (정원 초과)' : '참여하기',
                        ),
                      ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(
    IconData icon,
    Color color,
    String title,
    String content, {
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Row(
                  children: [
                    Text(
                      content,
                      style: const TextStyle(fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (suffix != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8.0),
                        child: suffix,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 카테고리별 색상 반환 메서드
  Color _getCategoryColor(String category) {
    switch (category) {
      case '스터디':
        return Colors.blue;
      case '식사':
        return Colors.orange;
      case '취미':
        return Colors.green;
      case '문화':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }
}
