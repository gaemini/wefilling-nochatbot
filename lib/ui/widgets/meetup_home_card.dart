import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/meetup.dart';
import '../../services/meetup_service.dart';
import '../../ui/snackbar/app_snackbar.dart';
import '../../utils/ui_utils.dart';

/// 모임 페이지(Home)에서 쓰는 카드와 **동일한 UI**를 공용 위젯으로 제공합니다.
///
/// - `isParticipating == null`이면 버튼 자리를 placeholder로 유지합니다(홈과 동일).
/// - 참여/나가기/후기 확인 동작은 화면에서 콜백으로 주입합니다.
class MeetupHomeCard extends StatefulWidget {
  final Meetup meetup;
  final bool? isParticipating;
  final bool isParticipationStatusLoading;
  final bool isJoinLeaveInFlight;

  final VoidCallback onTap;
  final Future<void> Function()? onJoin;
  final Future<void> Function()? onLeave;
  final VoidCallback? onViewReview;

  const MeetupHomeCard({
    super.key,
    required this.meetup,
    required this.onTap,
    this.isParticipating,
    this.isParticipationStatusLoading = false,
    this.isJoinLeaveInFlight = false,
    this.onJoin,
    this.onLeave,
    this.onViewReview,
  });

  @override
  State<MeetupHomeCard> createState() => _MeetupHomeCardState();
}

class _MeetupHomeCardState extends State<MeetupHomeCard> {
  final MeetupService _meetupService = MeetupService();
  late Stream<int> _participantCountStream;

  @override
  void initState() {
    super.initState();
    _participantCountStream = _meetupService.participantCountStream(
      widget.meetup.id,
      fallback: widget.meetup.currentParticipants,
    );
  }

  @override
  void didUpdateWidget(covariant MeetupHomeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meetup.id != widget.meetup.id) {
      _participantCountStream = _meetupService.participantCountStream(
        widget.meetup.id,
        fallback: widget.meetup.currentParticipants,
      );
    }
  }

  bool _isUrl(String text) {
    final urlPattern = RegExp(
      r'^(https?:\/\/)?(www\.)?[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b([-a-zA-Z0-9()@:%_\+.~#?&//=]*)',
      caseSensitive: false,
    );
    return urlPattern.hasMatch(text);
  }

  Future<void> _openUrl(BuildContext context, String urlString) async {
    try {
      var fixed = urlString;
      if (!fixed.startsWith('http://') && !fixed.startsWith('https://')) {
        fixed = 'https://$fixed';
      }

      final uri = Uri.parse(fixed);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (!context.mounted) return;
        AppSnackBar.show(
          context,
          message: '${AppLocalizations.of(context)!.error}: URL을 열 수 없습니다',
          type: AppSnackBarType.error,
        );
      }
    } catch (e) {
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        message: '${AppLocalizations.of(context)!.error}: $e',
        type: AppSnackBarType.error,
      );
    }
  }

  Widget _buildVisibilityBadge(BuildContext context) {
    if (widget.meetup.visibility == 'category') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3E0),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.group_outlined,
              size: 15,
              color: Color(0xFFFF8A65),
            ),
            const SizedBox(width: 6),
            Text(
              AppLocalizations.of(context)!.friendsOnlyBadge,
              style: const TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFFF8A65),
              ),
            ),
          ],
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildJoinButton(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const SizedBox.shrink();

    // 내가 만든 모임이면 버튼 표시 안함
    if (widget.meetup.userId == currentUser.uid) return const SizedBox.shrink();

    // 상태가 아직 없으면(로딩/미조회) 홈과 동일하게 자리만 유지
    if (widget.isParticipating == null) {
      return const SizedBox(width: 64, height: 32);
    }

    final participating = widget.isParticipating!;
    final inFlight = widget.isJoinLeaveInFlight;

    // 모임이 완료된 경우 처리 (홈과 동일)
    if (widget.meetup.isCompleted) {
      if (participating) {
        if (widget.meetup.hasReview == true) {
          return GestureDetector(
            onTap: widget.onViewReview,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.green[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.rate_review, size: 12, color: Colors.green[700]),
                  const SizedBox(width: 4),
                  Text(
                    AppLocalizations.of(context)!.checkReview,
                    style: TextStyle(
                      fontFamily: 'Pretendard',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[300]!),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.check_circle, size: 12, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                AppLocalizations.of(context)!.closedStatus,
                style: TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        );
      }

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 12, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(
              AppLocalizations.of(context)!.closedStatus,
              style: TextStyle(
                fontFamily: 'Pretendard',
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // 마감된 모임이지만 참여하지 않았으면 버튼 숨김 (홈과 동일)
    if (widget.meetup.currentParticipants >= widget.meetup.maxParticipants &&
        !participating) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: inFlight
          ? null
          : () async {
              if (participating) {
                await widget.onLeave?.call();
              } else {
                await widget.onJoin?.call();
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: participating ? const Color(0xFFEF4444) : AppColors.pointColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: inFlight
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                participating
                    ? AppLocalizations.of(context)!.leaveMeetup
                    : AppLocalizations.of(context)!.joinMeetup,
                style: const TextStyle(
                  fontFamily: 'Pretendard',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Stack(
        children: [
          Container(
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
                // 상단: 제목과 공개 범위 배지
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.meetup.title,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 16,
                            // ✅ BoardMeetupCard(게시글 Today 카드)와 제목 폰트 통일
                            // - size: 16
                            // - weight: w800
                            // - height: 1.25
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827),
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildVisibilityBadge(context),
                    ],
                  ),
                ),

                // 중간: 장소와 참여자 수
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: _isUrl(widget.meetup.location)
                                ? GestureDetector(
                                    onTap: () =>
                                        _openUrl(context, widget.meetup.location),
                                    child: Text(
                                      widget.meetup.location,
                                      style: const TextStyle(
                                        fontFamily: 'Pretendard',
                                        fontSize: 14,
                                        color: AppColors.pointColor,
                                        decoration: TextDecoration.underline,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                : Text(
                                    widget.meetup.location,
                                    style: const TextStyle(
                                      fontFamily: 'Pretendard',
                                      fontSize: 14,
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
                          StreamBuilder<int>(
                            stream: _participantCountStream,
                            builder: (context, snapshot) {
                              final participantCount = snapshot.data ??
                                  widget.meetup.currentParticipants;
                              return Text(
                                AppLocalizations.of(context)!.participantCount(
                                  '$participantCount',
                                  '${widget.meetup.maxParticipants}',
                                ),
                                style: const TextStyle(
                                  fontFamily: 'Pretendard',
                                  fontSize: 14,
                                  color: Color(0xFF6B7280),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 하단: 호스트 정보와 참여 버튼
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFFE5E7EB),
                        backgroundImage: widget.meetup.hostPhotoURL.isNotEmpty
                            ? NetworkImage(widget.meetup.hostPhotoURL)
                            : null,
                        child: widget.meetup.hostPhotoURL.isEmpty
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
                          widget.meetup.hostNickname ??
                              AppLocalizations.of(context)!.anonymous,
                          style: const TextStyle(
                            fontFamily: 'Pretendard',
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF374151),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _buildJoinButton(context),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 로딩 오버레이 (홈과 동일)
          if (widget.isParticipationStatusLoading)
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: UIUtils.safeOpacity(value),
                    child: Container(
                      decoration: BoxDecoration(
                        color: UIUtils.safeColorWithOpacity(
                          Colors.white,
                          0.85 * value,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Transform.scale(
                          scale: value,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: UIUtils.safeColorWithOpacity(
                                    Colors.black,
                                    0.1 * value,
                                  ),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.pointColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

