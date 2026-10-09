import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../firestore/firestore_paths.dart';
import '../../l10n/app_localizations.dart';
import '../../models/relationship_status.dart';
import '../../providers/relationship_provider.dart';
import '../../services/relationship_service.dart';
import '../../widgets/relationship_action_button.dart';

/// 포스트 작성자에게 실제로 친구 요청을 보낼 수 있을 때만 표시한다.
class PostFriendRequestButton extends StatefulWidget {
  const PostFriendRequestButton({super.key, required this.authorId});

  final String authorId;

  @override
  State<PostFriendRequestButton> createState() => _PostFriendRequestButtonState();
}

class _PostFriendRequestButtonState extends State<PostFriendRequestButton> {
  static final Map<String, (DateTime, Future<bool>)> _recentChecks = {};
  final RelationshipService _relationshipService = RelationshipService();
  Future<bool>? _canRequest;
  Stream<bool>? _isFriend;
  String? _viewerId;
  bool _sending = false;
  bool _sent = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshForAccount();
  }

  @override
  void didUpdateWidget(covariant PostFriendRequestButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authorId != widget.authorId) {
      _canRequest = null;
      _isFriend = null;
      _sent = false;
      _sending = false;
      _refreshForAccount();
    }
  }

  void _refreshForAccount() {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (_viewerId == viewerId && _canRequest != null) return;
    _viewerId = viewerId;
    _isFriend = null;
    _sent = false;
    _sending = false;
    _canRequest = viewerId == null ||
            widget.authorId.isEmpty ||
            widget.authorId == viewerId ||
            widget.authorId == 'deleted'
        ? null
        : _checkCanRequest(viewerId, widget.authorId);
  }

  Future<bool> _checkCanRequest(String viewerId, String authorId) {
    final key = '$viewerId:$authorId';
    final cached = _recentChecks[key];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(seconds: 30)) {
      return cached.$2;
    }
    if (_recentChecks.length >= 100) _recentChecks.clear();
    final check = _relationshipService.canSendFriendRequest(authorId);
    _recentChecks[key] = (DateTime.now(), check);
    return check;
  }

  /// 상대가 수락하거나 다른 화면에서 친구가 되면 버튼을 바로 숨기도록
  /// 두 사용자의 친구 관계 문서를 구독한다. 같은 작성자의 카드가 여러 개여도
  /// Firestore SDK가 동일 문서 구독을 하나로 합친다.
  Stream<bool> _watchFriendship(String viewerId, String authorId) {
    return FirebaseFirestore.instance
        .collection(FirestoreCollections.friendships)
        .doc(FirestoreDocIds.friendshipPairId(viewerId, authorId))
        .snapshots()
        .map((snapshot) => snapshot.exists)
        .handleError((_) {});
  }

  Future<void> _sendRequest() async {
    if (_sending || _sent) return;
    final viewerId = _viewerId;
    final authorId = widget.authorId;
    if (viewerId == null || FirebaseAuth.instance.currentUser?.uid != viewerId) {
      return;
    }
    setState(() => _sending = true);
    final provider = context.read<RelationshipProvider>();
    final success = await provider.sendFriendRequest(authorId);
    if (!mounted || _viewerId != viewerId || widget.authorId != authorId ||
        FirebaseAuth.instance.currentUser?.uid != viewerId) {
      return;
    }
    setState(() {
      _sending = false;
      _sent = success;
    });
    _recentChecks.remove('$viewerId:$authorId');
    // 이미 친구이거나 요청이 오간 상태라 실패한 경우에도 실제 관계를 다시
    // 확인해 버튼이 남지 않게 한다.
    if (!success) unawaited(provider.updateRelationshipStatus(authorId));
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success
          ? l10n.friendRequestSent
          : provider.actionErrorMessage ?? l10n.friendRequestFailed),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (FirebaseAuth.instance.currentUser?.uid != _viewerId) {
      return const SizedBox.shrink();
    }
    final request = _canRequest;
    if (request == null || _sent) return const SizedBox.shrink();
    return Selector<RelationshipProvider, RelationshipStatus>(
      selector: (_, provider) => provider.getRelationshipStatus(widget.authorId),
      builder: (context, status, _) {
        if (status != RelationshipStatus.none) return const SizedBox.shrink();
        return FutureBuilder<bool>(
          future: request,
          builder: (context, snapshot) {
            if (snapshot.data != true) return const SizedBox.shrink();
            final viewerId = _viewerId;
            if (viewerId == null) return const SizedBox.shrink();
            return StreamBuilder<bool>(
              stream: _isFriend ??= _watchFriendship(viewerId, widget.authorId),
              builder: (context, friendship) {
                if (friendship.data == true) return const SizedBox.shrink();
                return RelationshipActionButton(
                  label: AppLocalizations.of(context)!.friendRequest,
                  onPressed: _sending ? null : _sendRequest,
                );
              },
            );
          },
        );
      },
    );
  }
}
