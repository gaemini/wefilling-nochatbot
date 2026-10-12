// lib/ui/widgets/post_card_friend_button.dart
// 피드 포스트 카드 머리줄 오른쪽의 친구 추가 버튼.
// 관계 상태는 부모가 넘기고(provider 스트림), 이 위젯은 표시와 낙관적 갱신,
// 중복 탭 방지, 실패 시 되돌림만 맡는다. 서버 호출은 콜백으로 받는다.

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/ui_locale.dart';
import '../../models/relationship_status.dart';
import '../dialogs/relationship_confirm_dialog.dart';
import '../snackbar/app_snackbar.dart';

const Color _kPointStrong = Color(0xFF2C6BC0);
const Color _kFillSubtle = Color(0xFFEEEEEE);
const Color _kInkSecondary = Color(0xFF5F5F5F);

class PostCardFriendButton extends StatefulWidget {
  const PostCardFriendButton({
    super.key,
    required this.status,
    required this.onSend,
    required this.onCancel,
    required this.onAccept,
    this.confirmCancel = confirmCancelFriendRequest,
  });

  /// null이면 아직 모름(또는 숨김 조건) → 그리지 않는다.
  final RelationshipStatus? status;

  /// 각각 성공 여부를 돌려준다.
  final Future<bool> Function() onSend;
  final Future<bool> Function() onCancel;
  final Future<bool> Function() onAccept;

  /// 요청 취소 전 확인. 기본은 프로필 화면과 같은 확인 다이얼로그.
  final Future<bool> Function(BuildContext context) confirmCancel;

  static const double visualHeight = 30;
  static const double minTouch = 44;

  /// 버튼을 그리는 상태인지.
  static bool isVisibleFor(RelationshipStatus? status) =>
      status == RelationshipStatus.none ||
      status == RelationshipStatus.pendingOut ||
      status == RelationshipStatus.pendingIn;

  @override
  State<PostCardFriendButton> createState() => _PostCardFriendButtonState();
}

class _PostCardFriendButtonState extends State<PostCardFriendButton> {
  /// 탭 직후 서버 결과·스트림 반영 전까지 보여 줄 상태.
  RelationshipStatus? _optimistic;
  bool _inFlight = false;
  bool _pressed = false;

  RelationshipStatus? get _shown => _optimistic ?? widget.status;

  @override
  void didUpdateWidget(covariant PostCardFriendButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 스트림이 낙관적 상태를 따라잡았거나, 다른 곳에서 관계가 바뀌면
    // (예: 상대가 수락) 실제 상태를 따른다.
    if (!_inFlight &&
        _optimistic != null &&
        (widget.status == _optimistic || widget.status != oldWidget.status)) {
      _optimistic = null;
    }
  }

  Future<void> _handleTap() async {
    if (_inFlight) return;
    final from = _shown;
    if (!PostCardFriendButton.isVisibleFor(from)) return;
    final l10n = AppLocalizations.of(context)!;

    late final RelationshipStatus to;
    late final Future<bool> Function() action;
    late final String failure;
    String? success;
    switch (from!) {
      case RelationshipStatus.none:
        to = RelationshipStatus.pendingOut;
        action = widget.onSend;
        failure = l10n.friendRequestFailed;
      case RelationshipStatus.pendingOut:
        if (!await widget.confirmCancel(context) || !mounted) return;
        if (_inFlight || _shown != RelationshipStatus.pendingOut) return;
        to = RelationshipStatus.none;
        action = widget.onCancel;
        failure = l10n.friendRequestCancelFailed;
      case RelationshipStatus.pendingIn:
        to = RelationshipStatus.friends;
        action = widget.onAccept;
        failure = l10n.friendRequestAcceptFailed;
        success = l10n.friendRequestAccepted;
      default:
        return;
    }

    setState(() {
      _inFlight = true;
      _optimistic = to;
    });
    var ok = false;
    try {
      ok = await action();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _inFlight = false;
      // 실패하면 이전 상태로 되돌린다. 성공이면 스트림이 따라잡을 때까지 유지.
      if (!ok) {
        _optimistic = null;
      } else if (widget.status == to) {
        _optimistic = null;
      }
    });
    if (!ok) {
      AppSnackBar.show(context, message: failure, type: AppSnackBarType.error);
    } else if (success != null) {
      AppSnackBar.show(context,
          message: success, type: AppSnackBarType.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _shown;
    if (!PostCardFriendButton.isVisibleFor(status)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context)!;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final colorDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 120);
    final labelDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

    final filled = status != RelationshipStatus.pendingOut;
    final background = filled ? _kPointStrong : _kFillSubtle;
    final foreground = filled ? Colors.white : _kInkSecondary;
    final (IconData icon, String label) = switch (status!) {
      RelationshipStatus.none => (
          Icons.person_add_alt_1_rounded,
          l10n.addFriend
        ),
      RelationshipStatus.pendingOut => (
          Icons.check_rounded,
          l10n.requestPending
        ),
      _ => (Icons.check_rounded, l10n.accept),
    };

    final content = AnimatedSwitcher(
      duration: labelDuration,
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: .9, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: Row(
        key: ValueKey<RelationshipStatus>(status),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: uiFontFamily(context, 'Inter'),
                fontFamilyFallback: const ['NotoSansKR'],
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: foreground,
                height: isChineseUi(context) ? 1.3 : 1.2,
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      key: const ValueKey('post-card-friend-button'),
      button: true,
      enabled: !_inFlight,
      label: label,
      excludeSemantics: true,
      onTap: _inFlight ? null : _handleTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: _inFlight ? null : _handleTap,
        // 보이는 높이 30, 터치는 투명 여백을 더해 44 이상.
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: PostCardFriendButton.minTouch,
            minHeight: PostCardFriendButton.minTouch,
          ),
          child: Center(
            widthFactor: 1,
            child: AnimatedScale(
              scale: _pressed ? .96 : 1,
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              child: AnimatedContainer(
                duration: colorDuration,
                height: PostCardFriendButton.visualHeight,
                padding: const EdgeInsets.only(left: 10, right: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: content,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
