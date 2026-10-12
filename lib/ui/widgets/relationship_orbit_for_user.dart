// lib/ui/widgets/relationship_orbit_for_user.dart
// 사용자 id만 주면 서버 문서로 관계 상태를 판단해 RelationshipOrbit를 그리고,
// `+` 노드 탭을 기존 친구 요청 흐름(RelationshipProvider.sendFriendRequest)에 연결한다.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/relationship_strings.dart';
import '../../models/relationship_orbit_state.dart';
import '../../providers/relationship_provider.dart';
import '../../services/relationship_service.dart';
import '../../services/relationship_state_watcher.dart';
import 'relationship_orbit.dart';

class RelationshipOrbitForUser extends StatefulWidget {
  const RelationshipOrbitForUser({
    super.key,
    required this.userId,
    required this.size,
    required this.child,
    this.allowRequest = true,
    this.onStateResolved,
  });

  final String userId;
  final double size;
  final Widget child;

  /// false면 비친구여도 `+` 노드를 숨긴다(예: 탈퇴 계정, 익명).
  final bool allowRequest;

  /// 상태가 결정될 때마다 알린다. 도크의 분기(친구→DM, 비친구→요청)에 쓴다.
  final ValueChanged<OrbitRelationshipState>? onStateResolved;

  @override
  State<RelationshipOrbitForUser> createState() =>
      _RelationshipOrbitForUserState();
}

class _RelationshipOrbitForUserState extends State<RelationshipOrbitForUser> {
  static final Map<String, (DateTime, Future<bool>)> _recentChecks = {};
  final RelationshipService _relationshipService = RelationshipService();
  Future<bool>? _canRequest;
  Stream<OrbitRelationshipState>? _state;
  String? _viewerId;
  bool _sending = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshForAccount();
  }

  @override
  void didUpdateWidget(covariant RelationshipOrbitForUser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.allowRequest != widget.allowRequest) {
      _viewerId = null;
      _canRequest = null;
      _state = null;
      _sending = false;
      _refreshForAccount();
    }
  }

  void _refreshForAccount() {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (_viewerId == viewerId && _state != null) return;
    _viewerId = viewerId;
    _sending = false;
    final other = widget.userId;
    final valid = viewerId != null &&
        other.isNotEmpty &&
        other != viewerId &&
        other != 'deleted';
    _state = valid ? RelationshipStateWatcher.instance.watch(other) : null;
    _canRequest = valid && widget.allowRequest
        ? _checkCanRequest(viewerId, other)
        : Future<bool>.value(false);
  }

  Future<bool> _checkCanRequest(String viewerId, String other) {
    final key = '$viewerId:$other';
    final cached = _recentChecks[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 30)) {
      return cached.$2;
    }
    if (_recentChecks.length >= 200) _recentChecks.clear();
    final check = _relationshipService.canSendFriendRequest(other);
    _recentChecks[key] = (DateTime.now(), check);
    return check;
  }

  Future<void> _sendRequest() async {
    if (_sending) return;
    final viewerId = _viewerId;
    final other = widget.userId;
    if (viewerId == null || FirebaseAuth.instance.currentUser?.uid != viewerId) {
      return;
    }
    RelationshipProvider? provider;
    try {
      provider = context.read<RelationshipProvider>();
    } on ProviderNotFoundException {
      provider = null;
    }
    setState(() => _sending = true);
    final bool success;
    String? error;
    if (provider != null) {
      success = await provider.sendFriendRequest(other);
      error = provider.actionErrorMessage;
    } else {
      success = await _relationshipService.sendFriendRequest(other);
    }
    if (!mounted || widget.userId != other) return;
    _recentChecks.remove('$viewerId:$other');
    if (success) {
      RelationshipStateWatcher.instance.markRequestSent(other);
      // 요청을 보냈으면 서버 반영 전에도 + 노드를 다시 띄우지 않는다.
      _canRequest = Future<bool>.value(false);
    } else if (provider != null) {
      unawaited(provider.updateRelationshipStatus(other));
      _canRequest = _checkCanRequest(viewerId, other);
    }
    setState(() => _sending = false);
    final strings = RelationshipStrings.of(context);
    final message = success
        ? strings.friendRequestSentLocalized
        : strings.friendRequestError(error);
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final stream = _state;
    if (stream == null) {
      // 본인/미로그인/탈퇴 계정: 관계 표시 없이 아바타만 그린다.
      return SizedBox.square(
        dimension: widget.size,
        child: ClipOval(child: widget.child),
      );
    }
    return StreamBuilder<OrbitRelationshipState>(
      stream: stream,
      initialData: RelationshipStateWatcher.instance.latest(widget.userId),
      builder: (context, snapshot) {
        final state = snapshot.data;
        if (state != null) widget.onStateResolved?.call(state);
        return FutureBuilder<bool>(
          future: _canRequest,
          builder: (context, canRequest) => RelationshipOrbit(
            // 상태를 모르는 동안에는 노드를 보이지 않는다.
            state: state ?? OrbitRelationshipState.friend,
            semanticsLabel: state == null ? '' : null,
            size: widget.size,
            showNode: canRequest.data == true &&
                state == OrbitRelationshipState.notConnected,
            actionInFlight: _sending,
            onRelationshipAction: () => unawaited(_sendRequest()),
            child: widget.child,
          ),
        );
      },
    );
  }
}
