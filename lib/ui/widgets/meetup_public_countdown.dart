import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/meetup.dart';
import '../../utils/responsive_helper.dart';

/// 미확정 밋업의 공개 잔여 시간을 화면 새로고침 없이 갱신한다.
class MeetupPublicCountdown extends StatefulWidget {
  const MeetupPublicCountdown({
    super.key,
    required this.meetup,
    this.compact = false,
  });

  final Meetup meetup;
  final bool compact;

  static String format(Duration remaining) {
    final totalMinutes = remaining.inSeconds <= 0
        ? 0
        : (remaining.inSeconds / Duration.secondsPerMinute).ceil();
    if (totalMinutes <= 0) return '0min left';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0 && minutes > 0) return '${hours}H ${minutes}min left';
    if (hours > 0) return '${hours}H left';
    return '${minutes}min left';
  }

  @override
  State<MeetupPublicCountdown> createState() => _MeetupPublicCountdownState();
}

class _MeetupPublicCountdownState extends State<MeetupPublicCountdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant MeetupPublicCountdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meetup.publicExpiresAt != widget.meetup.publicExpiresAt ||
        oldWidget.meetup.isConfirmed != widget.meetup.isConfirmed) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    if (!widget.meetup.hasPublicTimeLimit) return;
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (widget.meetup.isPublicWindowExpiredAt()) {
        _timer?.cancel();
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = widget.meetup.publicTimeRemaining();
    if (remaining == null || remaining.inSeconds <= 0) {
      return const SizedBox.shrink();
    }
    final label = MeetupPublicCountdown.format(remaining);

    if (widget.compact) {
      return Semantics(
        label: label,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.timer_outlined,
                size: 9,
                color: Color(0xFF667085),
              ),
              const SizedBox(width: 2),
              Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(8.5).clamp(8.0, 9.0).toDouble(),
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -0.1,
                  color: const Color(0xFF667085),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      label: label,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: context.rs(12).clamp(10, 14).toDouble(),
          vertical: context.rs(9).clamp(8, 10).toDouble(),
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFEAECF0)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.timer_outlined,
              size: context.ri(16).clamp(15, 17).toDouble(),
              color: const Color(0xFF475467),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontFamilyFallback: const ['NotoSansKR'],
                  fontSize: context.rf(12.5).clamp(12, 13).toDouble(),
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF475467),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
