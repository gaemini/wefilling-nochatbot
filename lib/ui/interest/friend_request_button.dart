import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/tokens.dart';
import '../../l10n/app_localizations.dart';
import '../../providers/relationship_provider.dart';
import '../snackbar/app_snackbar.dart';
import '../widgets/tag_chips.dart' show tagTextStyle;
import 'wf_colors.dart';

enum PeopleButtonSize { card, list }

enum PeopleRelation { none, pendingOut, friends, pendingIn }

/// 서버의 isFriend와 RelationshipProvider가 구독 중인 보낸·받은 요청으로 본 관계.
PeopleRelation peopleRelationOf(
  String uid, {
  required bool isFriend,
  required Set<String> outgoing,
  required Set<String> incoming,
}) {
  if (isFriend) return PeopleRelation.friends;
  if (outgoing.contains(uid)) return PeopleRelation.pendingOut;
  if (incoming.contains(uid)) return PeopleRelation.pendingIn;
  return PeopleRelation.none;
}

/// 친구 요청 버튼(카드 40 / 목록 36). 누르면 화면을 먼저 바꾸고(낙관적) 서버에 보낸다.
/// 실패하면 이전 상태로 되돌리고 안내. 같은 uid 요청이 진행 중이면 다시 눌러도 무시.
/// 전역 isLoading은 보지 않는다(silent 호출).
class FriendRequestButton extends StatefulWidget {
  const FriendRequestButton({
    super.key,
    required this.uid,
    required this.relation,
    required this.size,
    required this.onOpenProfile,
    this.onAdded,
  });

  final String uid;
  final PeopleRelation relation;
  final PeopleButtonSize size;
  final VoidCallback onOpenProfile;

  /// 친구 추가를 누른 직후(타일 축하).
  final VoidCallback? onAdded;

  /// 진행 중인 uid(카드·목록이 같이 본다).
  static final Set<String> _inFlight = <String>{};

  @visibleForTesting
  static void debugReset() => _inFlight.clear();

  @override
  State<FriendRequestButton> createState() => _FriendRequestButtonState();
}

class _FriendRequestButtonState extends State<FriendRequestButton>
    with SingleTickerProviderStateMixin {
  /// 낙관적으로 바꾼 상태(서버 상태가 따라오면 null).
  PeopleRelation? _override;
  bool _pressed = false;
  late final AnimationController _check;

  @override
  void initState() {
    super.initState();
    _check = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 430));
  }

  PeopleRelation get _relation => _override ?? widget.relation;

  @override
  void didUpdateWidget(FriendRequestButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.relation == _override) _override = null;
    if (oldWidget.uid != widget.uid) _override = null;
  }

  @override
  void dispose() {
    _check.dispose();
    super.dispose();
  }

  Future<void> _onTap() async {
    final relation = _relation;
    if (relation == PeopleRelation.friends) {
      widget.onOpenProfile();
      return;
    }
    if (!FriendRequestButton._inFlight.add(widget.uid)) return;
    final provider = context.read<RelationshipProvider>();
    final l10n = AppLocalizations.of(context)!;
    final (next, call) = switch (relation) {
      PeopleRelation.none => (
          PeopleRelation.pendingOut,
          () => provider.sendFriendRequest(widget.uid, silent: true)
        ),
      PeopleRelation.pendingOut => (
          PeopleRelation.none,
          () => provider.cancelFriendRequest(widget.uid, silent: true)
        ),
      _ => (
          PeopleRelation.friends,
          () => provider.acceptFriendRequest(widget.uid, silent: true)
        ),
    };
    HapticFeedback.lightImpact();
    setState(() => _override = next);
    if (next == PeopleRelation.pendingOut) {
      widget.onAdded?.call();
      if (MotionTokens.reduceMotion(context)) {
        _check.value = 1;
      } else {
        _check.forward(from: 0);
      }
    }
    bool ok;
    try {
      ok = await call();
    } catch (_) {
      ok = false;
    } finally {
      FriendRequestButton._inFlight.remove(widget.uid);
    }
    if (!mounted || ok) return;
    setState(() => _override = relation);
    AppSnackBar.show(
      context,
      message: provider.actionErrorMessage ??
          provider.errorMessage ??
          l10n.peopleActionFailed,
      type: AppSnackBarType.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final card = widget.size == PeopleButtonSize.card;
    final relation = _relation;
    final primary =
        relation == PeopleRelation.none || relation == PeopleRelation.pendingIn;
    final background = primary
        ? WfColors.brand
        : card
            ? Colors.white
            : WfColors.surface;
    final foreground = primary
        ? Colors.white
        : card
            ? WfColors.ink2
            : const Color(0xFF4B5563);
    final label = switch (relation) {
      PeopleRelation.none => card ? l10n.peopleAdd : l10n.peopleAddShort,
      PeopleRelation.pendingOut =>
        card ? l10n.peopleRequested : l10n.peopleRequestedShort,
      PeopleRelation.friends => l10n.peopleProfile,
      PeopleRelation.pendingIn => l10n.peopleAccept,
    };
    final iconSize = card ? 16.0 : 14.0;
    final Widget? icon = switch (relation) {
      PeopleRelation.none => Icon(Icons.person_add_alt_1_rounded,
          size: card ? 17 : 15, color: foreground),
      PeopleRelation.pendingOut => SizedBox.square(
          dimension: iconSize,
          child: CustomPaint(
              painter: _CheckPainter(_check, color: foreground)),
        ),
      _ => null,
    };
    final duration = MotionTokens.of(context, const Duration(milliseconds: 300));
    final content = Row(
      key: ValueKey(relation),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[icon, const SizedBox(width: 6)],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tagTextStyle(context, card ? 14.5 : 14, FontWeight.w800,
                  foreground)),
        ),
      ],
    );
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('friend-request-${widget.uid}'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: _onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: card ? 44 : 44),
          child: Center(
            widthFactor: 1,
            child: AnimatedScale(
              scale: _pressed ? .97 : 1,
              duration: MotionTokens.of(context, MotionTokens.pressShort),
              curve: MotionTokens.pressSnappy,
              child: AnimatedContainer(
                duration:
                    MotionTokens.of(context, const Duration(milliseconds: 250)),
                height: card ? 40 : 36,
                width: card ? double.infinity : null,
                padding: EdgeInsets.symmetric(horizontal: card ? 12 : 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration: duration,
                    transitionBuilder: (child, animation) => SlideTransition(
                      position: Tween(
                              begin: const Offset(0, .3), end: Offset.zero)
                          .animate(CurvedAnimation(
                              parent: animation, curve: Curves.easeOutCubic)),
                      child: FadeTransition(opacity: animation, child: child),
                    ),
                    child: content,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✓를 선으로 그린다(80ms 늦게 시작해 350ms).
class _CheckPainter extends CustomPainter {
  _CheckPainter(this.animation, {required this.color})
      : super(repaint: animation);

  final Animation<double> animation;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final raw = animation.isDismissed ? 1.0 : animation.value;
    final t = Curves.easeOutCubic
        .transform(const Interval(80 / 430, 1).transform(raw.clamp(0, 1)));
    final path = Path()
      ..moveTo(size.width * .18, size.height * .52)
      ..lineTo(size.width * .42, size.height * .74)
      ..lineTo(size.width * .84, size.height * .28);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold<double>(0, (sum, PathMetric m) => sum + m.length);
    var left = total * t;
    for (final metric in metrics) {
      final take = left.clamp(0, metric.length).toDouble();
      canvas.drawPath(metric.extractPath(0, take), paint);
      left -= take;
      if (left <= 0) break;
    }
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}
