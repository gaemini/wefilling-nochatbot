// lib/widgets/meetup_card.dart
// 모임 카드 위젯 구현
// 모임 정보 표시 및 참여 버튼 제공

import 'package:flutter/material.dart';
import '../models/meetup.dart';
import '../constants/app_constants.dart';
import '../screens/meetup_detail_screen.dart';
import '../ui/widgets/glassmorphism_container.dart';

class MeetupCard extends StatelessWidget {
  final Meetup meetup;
  final Function(Meetup) onJoinMeetup;
  final String meetupId; // 이미 String 타입
  final Function onMeetupDeleted;
  
  /// 2024-2025 트렌드: Glassmorphism 스타일 사용 여부
  final bool useGlassmorphism;

  const MeetupCard({
    Key? key,
    required this.meetup,
    required this.onJoinMeetup,
    required this.meetupId, // 이미 String으로 정의됨
    required this.onMeetupDeleted,
    this.useGlassmorphism = false, // 기본값은 false (기존 디자인 유지)
  }) : super(key: key);

  /// ✨ Glassmorphism 스타일 팩토리 메서드
  factory MeetupCard.glassmorphism({
    Key? key,
    required Meetup meetup,
    required Function(Meetup) onJoinMeetup,
    required String meetupId,
    required Function onMeetupDeleted,
  }) {
    return MeetupCard(
      key: key,
      meetup: meetup,
      onJoinMeetup: onJoinMeetup,
      meetupId: meetupId,
      onMeetupDeleted: onMeetupDeleted,
      useGlassmorphism: true,
    );
  }

  String _getStatusButton() {
    final isFull = meetup.currentParticipants >= meetup.maxParticipants;
    return isFull ? AppConstants.FULL : AppConstants.JOIN;
  }

  // 2024-2025 트렌드: Modern vibrant category colors
  Color _getCategoryColor(String category) {
    switch (category) {
      case '스터디':
        return AppTheme.primary; // Modern indigo
      case '식사':
        return AppTheme.accentAmber; // Vibrant amber
      case '취미':
        return AppTheme.accentEmerald; // Vibrant emerald
      case '문화':
        return AppTheme.secondary; // Modern pink
      default:
        return AppTheme.primary;
    }
  }

  // 2024-2025 트렌드: Category gradient
  LinearGradient _getCategoryGradient(String category) {
    switch (category) {
      case '스터디':
        return AppTheme.primaryGradient;
      case '식사':
        return AppTheme.amberGradient;
      case '취미':
        return AppTheme.emeraldGradient;
      case '문화':
        return AppTheme.secondaryGradient;
      default:
        return AppTheme.primaryGradient;
    }
  }

  // 글래스모피즘 스타일 선택
  String _getGlassmorphismStyle(String category) {
    switch (category) {
      case '스터디':
        return 'primary';
      case '식사':
        return 'default'; // Amber는 아직 glassmorphism variant 없음
      case '취미':
        return 'emerald';
      case '문화':
        return 'secondary';
      default:
        return 'primary';
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _getStatusButton();
    final isFull = meetup.currentParticipants >= meetup.maxParticipants;

    // 글래스모피즘 스타일 적용 여부에 따라 다른 위젯 반환
    if (useGlassmorphism) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: GlassmorphismContainer(
          margin: EdgeInsets.zero,
          padding: const EdgeInsets.all(20),
          style: _getGlassmorphismStyle(meetup.category),
          onTap: () {
            // 모임 상세 화면 표시
            showDialog(
              context: context,
              builder: (context) => MeetupDetailScreen(
                meetup: meetup,
                meetupId: meetupId,
                onMeetupDeleted: onMeetupDeleted,
              ),
            );
          },
          child: _buildMeetupContent(status, isFull),
        ),
      );
    }

    // 기존 스타일 (호환성 보장)
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
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppTheme.backgroundGradient, // Subtle background gradient
            borderRadius: BorderRadius.circular(AppTheme.radiusL),
            boxShadow: [
              BoxShadow(
                color: _getCategoryColor(meetup.category).withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 8),
                spreadRadius: 0,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
                spreadRadius: 0,
              ),
            ],
            border: Border.all(
              color: _getCategoryColor(meetup.category).withOpacity(0.1),
              width: 1,
            ),
          ),
          child: _buildMeetupContent(status, isFull),
        ),
      ),
    );
  }

  /// 모임 컨텐츠 빌드 (글래스모피즘과 기존 스타일 공통)
  Widget _buildMeetupContent(String status, bool isFull) {
    return Row(
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
