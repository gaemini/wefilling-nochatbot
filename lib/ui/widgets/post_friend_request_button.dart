import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
      _sent = false;
      _sending = false;
      _refreshForAccount();
    }
  }

  void _refreshForAccount() {
    final viewerId = FirebaseAuth.instance.currentUser?.uid;
    if (_viewerId == viewerId && _canRequest != null) return;
    _viewerId = viewerId;
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
            return RelationshipActionButton(
              label: AppLocalizations.of(context)!.friendRequest,
              onPressed: _sending ? null : _sendRequest,
            );
          },
        );
      },
    );
  }
}
