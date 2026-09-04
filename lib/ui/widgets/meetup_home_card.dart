import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/meetup.dart';
import '../../services/meetup_service.dart';
import '../../ui/snackbar/app_snackbar.dart';
import '../../utils/category_label_utils.dart';
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

  Widget _buildCategoryHashtag(BuildContext context) {
    final label = localizedCategoryLabel(context, widget.meetup.category);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: context.rs(86).clamp(72.0, 96.0).toDouble(),
      ),
      child: Text(
        '#$label',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'Inter',
          fontFamilyFallback: const ['NotoSansKR'],
          fontSize: context.rf(11.5).clamp(11.0, 12.0).toDouble(),
          fontWeight: FontWeight.w700,
          height: 1.15,
          color: const Color(0xFF2563EB),
        ),
      ),
    );
  }

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
            trailingAction: _buildCategoryHashtag(context),
          ),
        );
      },
    );
  }
}
