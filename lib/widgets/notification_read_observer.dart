import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
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

class _NotificationReadObserverState extends State<NotificationReadObserver>
    with WidgetsBindingObserver {
  final _visibilityKey = UniqueKey();
  String? _owner;
  int? _session;
  bool _inFlight = false;
  bool _completed = false;
  bool _visible = false;
  int _failures = 0;
  int _requestGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Firebase.apps.isEmpty) return; // Injected previews have no backend.
    _owner = FirebaseAuth.instance.currentUser?.uid;
    _session = FCMService().notificationSession;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant NotificationReadObserver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!setEquals(oldWidget.types, widget.types) ||
        !mapEquals(oldWidget.targets, widget.targets) ||
        oldWidget.onVisible != widget.onVisible) {
      _requestGeneration++;
      _completed = false;
      _failures = 0;
      if (!_inFlight) _requestRead();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _visible) _requestRead();
  }

  void _requestRead() {
    if (!_visible || _inFlight || _completed || _failures >= 3 || !mounted ||
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
        ModalRoute.of(context)?.isCurrent != true ||
        _owner == null || _session == null ||
        !FCMService().isNotificationSession(_owner!, _session!)) return;
    _inFlight = true;
    final generation = _requestGeneration;
    unawaited(() async {
      try {
        if (widget.onVisible != null) {
          await widget.onVisible!();
        } else {
          final count = await NotificationService().markRelatedNotificationsAsRead(
            types: widget.types,
            targets: widget.targets,
            expectedOwner: _owner,
            expectedSession: _session,
          );
          if (count < 0) throw StateError('Notification read request failed');
        }
        if (generation == _requestGeneration) _completed = true;
      } catch (_) {
        if (generation == _requestGeneration) _failures++;
      } finally {
        _inFlight = false;
        if (generation != _requestGeneration) _requestRead();
      }
    }());
  }

  @override
  Widget build(BuildContext context) => _owner == null
      ? widget.child
      : VisibilityDetector(
          key: _visibilityKey,
          onVisibilityChanged: (visibility) {
            _visible = visibility.visibleFraction > 0;
            _requestRead();
          },
          child: widget.child,
        );
}
