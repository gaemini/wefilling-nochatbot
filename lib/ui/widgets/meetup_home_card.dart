import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../constants/app_constants.dart';
import '../../l10n/app_localizations.dart';
import '../../models/meetup.dart';
import '../../services/meetup_service.dart';
import '../../ui/snackbar/app_snackbar.dart';
import '../../utils/responsive_helper.dart';
import 'board_meetup_card.dart';

/// 밋업 탭의 카드 동작을 포스트 피드의 공통 밋업 카드 디자인에 연결한다.
/// 참여/나가기/후기/장소 URL 기능은 이 래퍼에서 그대로 유지한다.
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
    if (oldWidget.meetup.id == widget.meetup.id) return;
    _participantCountStream = _meetupService.participantCountStream(
      widget.meetup.id,
      fallback: widget.meetup.currentParticipants,
    );
  }

  bool _isUrl(String text) =>
      Uri.tryParse(text.trim())?.host.isNotEmpty == true ||
      RegExp(r'^[\w.-]+\.[a-zA-Z]{2,}').hasMatch(text.trim());

  Future<void> _openUrl(BuildContext context, String raw) async {
    try {
      final normalized = raw.startsWith('http://') || raw.startsWith('https://')
          ? raw
          : 'https://$raw';
      final uri = Uri.parse(normalized);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        message: '${AppLocalizations.of(context)!.error}: URL을 열 수 없습니다',
        type: AppSnackBarType.error,
      );
    } catch (error) {
      if (!context.mounted) return;
      AppSnackBar.show(
        context,
        message: '${AppLocalizations.of(context)!.error}: $error',
        type: AppSnackBarType.error,
      );
    }
  }

  Widget? _buildAction(BuildContext context, int participants) {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || widget.meetup.userId == currentUser.uid) {
      return null;
    }

    final isKo = Localizations.localeOf(context).languageCode == 'ko';
    if (widget.meetup.isExpired() || widget.meetup.isPublicWindowExpiredAt()) {
      return _statusText(isKo ? '만료' : 'Expired');
    }

    if (widget.isParticipationStatusLoading || widget.isParticipating == null) {
      return SizedBox.square(
        dimension: 34,
        child: widget.isParticipationStatusLoading
            ? const Padding(
                padding: EdgeInsets.all(8),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.pointColor,
                ),
              )
            : null,
      );
    }

    final participating = widget.isParticipating!;
    if (widget.meetup.isCompleted) {
      if (participating && widget.meetup.hasReview) {
        return _actionButton(
          context,
          label: AppLocalizations.of(context)!.checkReview,
          onPressed: widget.onViewReview,
        );
      }
      return _statusText(AppLocalizations.of(context)!.closedStatus);
    }

    if (participants >= widget.meetup.maxParticipants && !participating) {
      return _statusText(isKo ? '마감' : 'Full');
    }

    return _actionButton(
      context,
      label: participating
          ? AppLocalizations.of(context)!.leaveMeetup
          : AppLocalizations.of(context)!.joinMeetup,
      destructive: participating,
      loading: widget.isJoinLeaveInFlight,
      onPressed: widget.isJoinLeaveInFlight
          ? null
          : () async {
              if (participating) {
                await widget.onLeave?.call();
              } else {
                await widget.onJoin?.call();
              }
            },
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required VoidCallback? onPressed,
    bool destructive = false,
    bool loading = false,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(42, 36),
        padding: const EdgeInsets.symmetric(horizontal: 7),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        foregroundColor:
            destructive ? const Color(0xFFB42318) : const Color(0xFF111827),
        textStyle: TextStyle(
          fontFamily: 'Pretendard',
          fontSize: context.rf(12).clamp(11.5, 12.5).toDouble(),
          fontWeight: FontWeight.w800,
        ),
      ),
      child: loading
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _statusText(String label) => Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF667085),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final locationIsUrl = _isUrl(widget.meetup.location);
    return StreamBuilder<int>(
      stream: _participantCountStream,
      builder: (context, snapshot) {
        final participants = snapshot.data ?? widget.meetup.currentParticipants;
        return AnimatedOpacity(
          opacity: widget.isParticipationStatusLoading ? 0.72 : 1,
          duration: const Duration(milliseconds: 160),
          child: BoardMeetupCard(
            meetup: widget.meetup,
            currentParticipants: participants,
            onTap: widget.onTap,
            onLocationTap: locationIsUrl
                ? () => _openUrl(context, widget.meetup.location)
                : null,
            trailingAction: _buildAction(context, participants),
          ),
        );
      },
    );
  }
}
