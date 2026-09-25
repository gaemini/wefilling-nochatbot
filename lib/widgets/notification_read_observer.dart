import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../services/fcm_service.dart';
import '../services/notification_service.dart';

/// Attach only to successfully loaded content, never to its loading shell.
/// Lazy list construction alone is not evidence that a comment was seen.
class NotificationReadObserver extends StatefulWidget {
  const NotificationReadObserver(
      {super.key,
      this.types = const {},
      this.targets = const {},
      this.onVisible,
      required this.child});
  final Set<String> types;
  final Map<String, String> targets;
  final Widget child;
  final Future<void> Function()? onVisible;

  @override
  State<NotificationReadObserver> createState() =>
      _NotificationReadObserverState();
}

class _NotificationReadObserverState extends State<NotificationReadObserver> {
  final _visibilityKey = UniqueKey();
  String? _owner;
  int? _session;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    if (Firebase.apps.isEmpty) return; // Injected previews have no backend.
    _owner = FirebaseAuth.instance.currentUser?.uid;
    _session = FCMService().notificationSession;
  }

  @override
  Widget build(BuildContext context) => _owner == null
      ? widget.child
      : VisibilityDetector(
          key: _visibilityKey,
          onVisibilityChanged: (visibility) {
            if (_requested ||
                visibility.visibleFraction <= 0 ||
                !mounted ||
                ModalRoute.of(context)?.isCurrent != true ||
                _owner == null ||
                !FCMService().isNotificationSession(_owner!, _session!)) return;
            _requested = true;
            if (widget.onVisible != null) {
              unawaited(widget.onVisible!());
              return;
            }
            unawaited(NotificationService().markRelatedNotificationsAsRead(
              types: widget.types,
              targets: widget.targets,
              expectedOwner: _owner,
              expectedSession: _session,
            ));
          },
          child: widget.child,
        );
}
