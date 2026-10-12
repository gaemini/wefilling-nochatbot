import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/content_translation.dart';
import '../../models/post.dart';
import '../../services/content_translation_service.dart';
import '../../utils/post_translation_policy.dart';

/// Optional cache prefetch and screen-local display scopes. Each post card
/// requests its own translation; this wrapper never controls card readiness.
class PostTranslationFeed extends StatefulWidget {
  const PostTranslationFeed(
      {super.key,
      required this.posts,
      required this.child,
      this.enabled = true});

  final List<Post> posts;
  final Widget child;
  final bool enabled;

  static String scopeOf(BuildContext context, String postId) =>
      context
          .dependOnInheritedWidgetOfExactType<_PostTranslationFeedScope>()
          ?.state
          .scopeFor(postId) ??
      'post:$postId';

  static bool contains(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_PostTranslationFeedScope>() !=
      null;

  @override
  State<PostTranslationFeed> createState() => _PostTranslationFeedState();
}

class _PostTranslationFeedState extends State<PostTranslationFeed>
    with WidgetsBindingObserver {
  static int _nextScope = 0;
  late final String _scope = 'post-feed:${_nextScope++}';
  ContentTranslationService? _service;
  final Map<String, GlobalKey> _anchors = {};
  final Map<String, Map<String, String>> _prefetchedSources = {};
  int _languageRevision = 0;
  int _resultsRevision = 0;
  bool _anchorRestoreScheduled = false;
  Duration? _anchorRestoreUntil;
  bool _prefetchScheduled = false;
  bool _foreground = true;

  String scopeFor(String postId) => '$_scope:post:$postId';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPosts();
  }

  @override
  void didUpdateWidget(covariant PostTranslationFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPosts();
  }

  void _syncPosts() {
    if (!widget.enabled) return;
    if (_service == null && widget.posts.isNotEmpty) {
      _service = ContentTranslationService.instance;
      _languageRevision = _service!.languageRevision;
      _resultsRevision = _service!.resultsRevision;
      _service!.addListener(_serviceChanged);
    }
    final ids = widget.posts.map((post) => post.id).toSet();
    _prefetchedSources.removeWhere((id, _) => !ids.contains(id));
    _anchors.removeWhere((id, _) => !ids.contains(id));
    _schedulePrefetch();
  }

  void _serviceChanged() {
    if (!mounted) return;
    if (_languageRevision != _service!.languageRevision) {
      _languageRevision = _service!.languageRevision;
      _prefetchedSources.clear();
      _schedulePrefetch();
    }
    if (_resultsRevision != _service!.resultsRevision) {
      _resultsRevision = _service!.resultsRevision;
      _preserveReadingAnchor();
    }
    // No setState, viewport scan or list diff for a sibling's result.
  }

  // Capture before descendant result listeners lay out taller/shorter text.
  // Restore only if the user hasn't scrolled in the meantime. The first feed
  // position and content insert/refresh anchoring remain owned by the feed.
  void _preserveReadingAnchor() {
    if (!widget.enabled ||
        !_foreground ||
        !TickerMode.valuesOf(context).enabled) {
      return;
    }
    // Result notifications also arrive between frames, when no frame timestamp
    // is available. Start/extend the deadline inside the next frame callback.
    _anchorRestoreUntil = null;
    if (_anchorRestoreScheduled) return;
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return;
    }
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    GlobalKey? anchor;
    ScrollPosition? position;
    double? anchorTop;
    for (final key in _anchors.values) {
      final anchorContext = key.currentContext;
      final box = anchorContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy + box.size.height <= top || dy >= bottom) continue;
      if (anchorTop == null || dy < anchorTop) {
        anchor = key;
        anchorTop = dy;
        position = Scrollable.maybeOf(anchorContext!)?.position;
      }
    }
    if (anchor == null ||
        position == null ||
        !position.hasPixels ||
        position.pixels <= position.minScrollExtent ||
        position.isScrollingNotifier.value) {
      return;
    }
    final savedPosition = position;
    var savedOffset = position.pixels;
    final savedTop = anchorTop!;
    final savedAnchor = anchor;
    _anchorRestoreScheduled = true;
    void restore(Duration timestamp) {
      _anchorRestoreUntil ??= timestamp + const Duration(milliseconds: 450);
      if (!mounted ||
          !_foreground ||
          !savedPosition.hasPixels ||
          savedPosition.isScrollingNotifier.value ||
          (savedPosition.pixels - savedOffset).abs() > 0.5) {
        _anchorRestoreScheduled = false;
        return;
      }
      final anchorContext = savedAnchor.currentContext;
      final box = anchorContext?.findRenderObject();
      if (box is! RenderBox ||
          !box.attached ||
          !box.hasSize ||
          !identical(
              Scrollable.maybeOf(anchorContext!)?.position, savedPosition)) {
        _anchorRestoreScheduled = false;
        return;
      }
      final delta = box.localToGlobal(Offset.zero).dy - savedTop;
      if (delta.abs() > 0.5) {
        final target = (savedOffset + delta).clamp(
            savedPosition.minScrollExtent, savedPosition.maxScrollExtent);
        savedPosition.jumpTo(target);
        savedOffset = savedPosition.pixels;
      }
      // AnimatedSize/Switcher can change height after the first result frame.
      // This is bounded to the presentation animation, not a queue polling loop.
      if (timestamp < _anchorRestoreUntil!) {
        WidgetsBinding.instance.addPostFrameCallback(restore);
        WidgetsBinding.instance.ensureVisualUpdate();
      } else {
        _anchorRestoreScheduled = false;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback(restore);
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _schedulePrefetch() {
    if (_prefetchScheduled ||
        !mounted ||
        _service == null ||
        !widget.enabled ||
        !_foreground) {
      return;
    }
    _prefetchScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prefetchScheduled = false;
      if (!mounted || !widget.enabled || !_foreground) return;
      final uiLanguageCode = Localizations.localeOf(context).languageCode;
      for (final post in widget.posts) {
        final fields = postTranslationSourceFields(post);
        if (fields.isEmpty || mapEquals(_prefetchedSources[post.id], fields)) {
          continue;
        }
        _prefetchedSources[post.id] = fields;
        // The shared service already deduplicates and bounds parallel batches.
        // Prefetch never sets card loading/readiness or gates a visible request.
        unawaited(_service!
            .request(
          ContentTranslationRequest(
            contentType: 'post',
            contentId: post.id,
            sourceFields: fields,
          ),
          scope: scopeFor(post.id),
          uiLanguageCode: uiLanguageCode,
          priority: TranslationRequestPriority.background,
        )
            .then<void>((_) {}, onError: (Object error, StackTrace stack) {
          if (mounted && identical(_prefetchedSources[post.id], fields)) {
            _prefetchedSources.remove(post.id);
          }
        }));
      }
    });
    // Data can arrive on a kept-alive/offscreen tab without an animation.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) _schedulePrefetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service?.removeListener(_serviceChanged);
    _prefetchedSources.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !widget.enabled
      ? widget.child
      : _PostTranslationFeedScope(
          state: this,
          child: widget.child,
        );
}

class _PostTranslationFeedScope extends InheritedWidget {
  const _PostTranslationFeedScope({required this.state, required super.child});
  final _PostTranslationFeedState state;
  @override
  bool updateShouldNotify(_PostTranslationFeedScope oldWidget) =>
      !identical(state, oldWidget.state);
}

/// Geometry preserves the reading position; it never gates translation.
class PostTranslationAnchor extends StatelessWidget {
  const PostTranslationAnchor(
      {super.key, required this.postId, required this.child});
  final String postId;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final state = context
        .dependOnInheritedWidgetOfExactType<_PostTranslationFeedScope>()
        ?.state;
    if (state == null) return child;
    return KeyedSubtree(
        key: state._anchors.putIfAbsent(postId, GlobalKey.new), child: child);
  }
}
