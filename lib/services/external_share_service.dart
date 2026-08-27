import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/external_share_request.dart';
import '../screens/create_post_screen.dart';
import '../utils/logger.dart';
import 'navigation_service.dart';

enum _ExternalShareRoutingState {
  queued,
  routing,
  opened,
  claimed,
  completed,
}

class ExternalShareService with WidgetsBindingObserver {
  ExternalShareService._();

  static final ExternalShareService instance = ExternalShareService._();
  static const MethodChannel _channel =
      MethodChannel('com.wefilling.app/external_share');

  StreamSubscription<User?>? _authSubscription;
  final Map<String, ExternalShareRequest> _pending =
      <String, ExternalShareRequest>{};
  final Map<String, _ExternalShareRoutingState> _routingStates =
      <String, _ExternalShareRoutingState>{};
  final Map<String, ExternalShareComposeOutcome> _deferredCompletions =
      <String, ExternalShareComposeOutcome>{};
  final ValueNotifier<int> postPageRequests = ValueNotifier<int>(0);

  Future<void>? _pullInFlight;
  bool _pullAgainRequested = false;
  bool _initialized = false;
  bool _routingReady = false;
  bool _presenting = false;
  bool _loginNoticeShown = false;
  bool _loginNoticeScheduled = false;
  String? _preferredRequestId;

  Future<void> initialize() async {
    if (_initialized || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      return;
    }
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareReceived') {
        final arguments = call.arguments;
        if (arguments is Map) {
          final requestId =
              arguments['externalShareRequestId']?.toString().trim();
          if (requestId != null && requestId.isNotEmpty) {
            _preferredRequestId = requestId;
          }
        }
        _log(
            'shareReceived wake received requestId=${_preferredRequestId ?? 'none'}');
        await _requestPendingShares(reason: 'native-wake');
      }
    });
    _log('method handler registered');

    // iOS keeps cold-start wake requests until this acknowledgement. Android
    // versions that do not implement the method continue through the pull path.
    try {
      await _channel.invokeMethod<void>('shareBridgeReady');
      _log('native bridge acknowledged ready');
    } on MissingPluginException {
      _log('shareBridgeReady unavailable on this platform version');
    } on PlatformException catch (error) {
      _log('shareBridgeReady ignored code=${error.code}');
    }

    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      _log('auth changed signedIn=${user != null}');
      unawaited(_requestPendingShares(reason: 'auth-state-ready'));
    });

    // Do not depend exclusively on a native wake event. This direct query is
    // the durable cold-start recovery path.
    await _requestPendingShares(reason: 'handler-registered');
  }

  void setRoutingReady(bool ready) {
    final changed = _routingReady != ready;
    _routingReady = ready;
    _log('routing ready=$ready changed=$changed');
    if (ready && changed) {
      _loginNoticeShown = false;
      unawaited(_requestPendingShares(reason: 'auth-and-router-ready'));
    } else if (ready) {
      unawaited(_presentNextIfPossible());
    } else {
      _showLoginNoticeIfNeeded();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_requestPendingShares(reason: 'app-resumed'));
    }
  }

  Future<void> _requestPendingShares({required String reason}) {
    final active = _pullInFlight;
    if (active != null) {
      _pullAgainRequested = true;
      _log('pending pull coalesced reason=$reason');
      return active;
    }

    late final Future<void> tracked;
    tracked = _drainPendingPulls(reason).whenComplete(() {
      if (identical(_pullInFlight, tracked)) _pullInFlight = null;
    });
    _pullInFlight = tracked;
    return tracked;
  }

  Future<void> _drainPendingPulls(String firstReason) async {
    var reason = firstReason;
    do {
      _pullAgainRequested = false;
      await _performPendingPull(reason: reason);
      reason = 'coalesced-follow-up';
    } while (_pullAgainRequested && _initialized);
  }

  Future<void> _performPendingPull({required String reason}) async {
    if (!_initialized) return;
    await _flushDeferredCompletions();

    try {
      final raw = await _channel.invokeMethod<dynamic>('getPendingShares');
      var receivedCount = 0;
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final request = ExternalShareRequest.fromMap(
            Map<String, dynamic>.from(item),
          );
          if (request.id.isEmpty ||
              (request.consumed && request.state != 'runnerClaimed')) {
            continue;
          }

          final state = _routingStates[request.id];
          if (state == _ExternalShareRoutingState.routing ||
              state == _ExternalShareRoutingState.opened ||
              state == _ExternalShareRoutingState.claimed ||
              state == _ExternalShareRoutingState.completed) {
            continue;
          }
          _pending.putIfAbsent(request.id, () => request);
          _routingStates[request.id] = _ExternalShareRoutingState.queued;
          receivedCount++;
        }
      }
      _log(
        'getPendingShares reason=$reason received=$receivedCount queued=${_pending.length}',
      );
    } on MissingPluginException {
      _log('getPendingShares plugin unavailable');
      return;
    } on PlatformException catch (error) {
      _log('getPendingShares failed code=${error.code}');
    } catch (error) {
      _log('getPendingShares failed type=${error.runtimeType}');
    }

    _showLoginNoticeIfNeeded();
    await _presentNextIfPossible();
  }

  void _showLoginNoticeIfNeeded() {
    if (_routingReady ||
        _pending.isEmpty ||
        _loginNoticeShown ||
        _loginNoticeScheduled) {
      return;
    }
    _loginNoticeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loginNoticeScheduled = false;
      final context = NavigationService.navigatorKey.currentContext;
      if (context == null) return;
      final isKo = Localizations.localeOf(context).languageCode == 'ko';
      final needsProfile = FirebaseAuth.instance.currentUser != null;
      _loginNoticeShown = true;
      unawaited(showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            needsProfile
                ? (isKo ? '프로필 설정이 필요해요' : 'Finish your profile')
                : (isKo ? '로그인이 필요해요' : 'Sign in required'),
          ),
          content: Text(
            needsProfile
                ? (isKo
                    ? '필수 프로필 설정을 완료하면 공유한 링크와 이미지로 바로 포스트를 작성할 수 있어요.'
                    : 'Finish the required profile setup to continue with the shared link and image.')
                : (isKo
                    ? '공유한 콘텐츠를 위필링 포스트로 만들려면 먼저 로그인해 주세요.\n로그인 후 공유한 링크와 이미지가 그대로 이어집니다.'
                    : 'Sign in to turn the shared content into a Wefilling post. Your shared link and image will be kept.'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(isKo ? '확인' : 'OK'),
            ),
          ],
        ),
      ));
      _log('login-required notice shown profileIncomplete=$needsProfile');
    });
  }

  Future<void> _presentNextIfPossible() async {
    if (!_routingReady || _presenting || _pending.isEmpty) return;
    final navigator = NavigationService.navigatorKey.currentState;
    if (navigator == null || !navigator.mounted) {
      _log('routing deferred navigator-not-ready');
      return;
    }

    final entries = _pending.values.where((request) {
      return _routingStates[request.id] == _ExternalShareRoutingState.queued;
    }).toList()
      ..sort((left, right) {
        final preferred = _preferredRequestId;
        if (preferred != null) {
          if (left.id == preferred && right.id != preferred) return -1;
          if (right.id == preferred && left.id != preferred) return 1;
        }
        return left.receivedAt.compareTo(right.receivedAt);
      });
    if (entries.isEmpty) return;

    final request = entries.first;
    _presenting = true;
    _routingStates[request.id] = _ExternalShareRoutingState.routing;
    _log('requestId=${request.id} routing=start');

    var claimed = false;
    var routeWasPushed = false;
    try {
      claimed = await _consumeNativeRequest(request.id);
      if (!claimed) {
        throw StateError('external-share-claim-failed');
      }
      _routingStates[request.id] = _ExternalShareRoutingState.claimed;

      final payloadReady = Completer<void>();
      final route = MaterialPageRoute<ExternalShareComposeOutcome>(
        settings: RouteSettings(name: '/create-post/shared/${request.id}'),
        builder: (_) => CreatePostScreen(
          onPostCreated: () {
            postPageRequests.value++;
          },
          initialSharedRequest: request,
          onSharedRequestReady: () {
            if (!payloadReady.isCompleted) payloadReady.complete();
          },
          onSharedPostCreated: (postId) =>
              _finishPostedShare(request.id, postId),
          onSharedDraftSave: (draft) => _saveSharedDraft(request.id, draft),
          stayInAppAfterSharedPost: Platform.isIOS,
        ),
      );

      final routeCompletion =
          navigator.push<ExternalShareComposeOutcome>(route);
      routeWasPushed = true;
      final payloadWasAccepted = await Future.any<bool>([
        payloadReady.future.then((_) => true),
        routeCompletion.then((_) => false),
      ]);

      if (payloadWasAccepted) {
        _routingStates[request.id] = _ExternalShareRoutingState.opened;
        _log('requestId=${request.id} payload=accepted');
      }

      final routeResult = await routeCompletion;
      final outcome = routeResult ?? ExternalShareComposeOutcome.saved;
      final alreadyCompleted =
          _routingStates[request.id] == _ExternalShareRoutingState.completed;
      final completed = alreadyCompleted ||
          await _completeNativeShareFlow(id: request.id, outcome: outcome);
      if (!completed) {
        _deferredCompletions[request.id] = outcome;
      }
      _routingStates[request.id] = completed
          ? _ExternalShareRoutingState.completed
          : _ExternalShareRoutingState.claimed;
      _pending.remove(request.id);
      if (_preferredRequestId == request.id) _preferredRequestId = null;
      _log(
        'requestId=${request.id} routing=closed outcome=${outcome.name} completed=$completed',
      );
    } catch (error) {
      _log(
        'requestId=${request.id} routing=failed pushed=$routeWasPushed claimed=$claimed type=${error.runtimeType}',
      );
      if (claimed) {
        await _completeNativeShareFlow(
          id: request.id,
          outcome: null,
          failed: true,
        );
      }
      _routingStates[request.id] = _ExternalShareRoutingState.queued;
    } finally {
      _presenting = false;
    }

    if (_pending.values.any(
      (request) =>
          _routingStates[request.id] == _ExternalShareRoutingState.queued,
    )) {
      unawaited(_presentNextIfPossible());
    }
  }

  Future<bool> _consumeNativeRequest(String id) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'consumeShare',
        <String, dynamic>{'id': id},
      );
      final success = result != false;
      _log('requestId=$id consumeShare=$success');
      return success;
    } on PlatformException catch (error) {
      _log('requestId=$id consumeShare=false code=${error.code}');
      return false;
    } catch (error) {
      _log('requestId=$id consumeShare=false type=${error.runtimeType}');
      return false;
    }
  }

  Future<bool> _saveSharedDraft(
    String id,
    ExternalShareDraft draft,
  ) async {
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'updateShareDraft',
        draft.toMap(id),
      );
      final success = result != false;
      _log('requestId=$id draft-save=$success');
      return success;
    } on PlatformException catch (error) {
      _log('requestId=$id draft-save=false code=${error.code}');
      return false;
    } catch (error) {
      _log('requestId=$id draft-save=false type=${error.runtimeType}');
      return false;
    }
  }

  Future<bool> _finishPostedShare(String id, String postId) async {
    final completed = await _completeNativeShareFlow(
      id: id,
      outcome: ExternalShareComposeOutcome.posted,
    );
    if (!completed) {
      _deferredCompletions[id] = ExternalShareComposeOutcome.posted;
    }
    _routingStates[id] = completed
        ? _ExternalShareRoutingState.completed
        : _ExternalShareRoutingState.claimed;
    _pending.remove(id);
    if (_preferredRequestId == id) _preferredRequestId = null;
    _log('requestId=$id postId=$postId posted-handoff-complete=$completed');
    // 게시 자체는 성공했으므로 native 정리가 일시 실패해도 상세 화면 이동은
    // 막지 않는다. 동일 postId와 deferred completion이 중복 생성을 방지한다.
    return true;
  }

  Future<bool> _completeNativeShareFlow({
    required String id,
    required ExternalShareComposeOutcome? outcome,
    bool failed = false,
  }) async {
    final nativeOutcome = failed
        ? 'failed'
        : switch (outcome) {
            ExternalShareComposeOutcome.saved => 'failed',
            ExternalShareComposeOutcome.posted => 'posted',
            ExternalShareComposeOutcome.discarded => 'discarded',
            null => null,
          };
    if (nativeOutcome == null) return false;
    try {
      final result = await _channel.invokeMethod<dynamic>(
        'completeShareFlow',
        <String, dynamic>{
          'id': id,
          'outcome': nativeOutcome,
        },
      );
      final success = result != false;
      _log('requestId=$id completeShareFlow=$success outcome=$nativeOutcome');
      return success;
    } on PlatformException catch (error) {
      _log('requestId=$id completeShareFlow=false code=${error.code}');
      return false;
    } catch (error) {
      _log('requestId=$id completeShareFlow=false type=${error.runtimeType}');
      return false;
    }
  }

  Future<void> _flushDeferredCompletions() async {
    if (_deferredCompletions.isEmpty) return;
    final snapshot = Map<String, ExternalShareComposeOutcome>.from(
      _deferredCompletions,
    );
    for (final entry in snapshot.entries) {
      final completed = await _completeNativeShareFlow(
        id: entry.key,
        outcome: entry.value,
      );
      if (completed) {
        _deferredCompletions.remove(entry.key);
        _routingStates[entry.key] = _ExternalShareRoutingState.completed;
      }
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    await _authSubscription?.cancel();
    _authSubscription = null;
    _channel.setMethodCallHandler(null);
    _pending.clear();
    _routingStates.clear();
    _deferredCompletions.clear();
    _pullInFlight = null;
    _preferredRequestId = null;
    _initialized = false;
  }

  void _log(String message) {
    if (kDebugMode && Logger.verboseLoggingEnabled) {
      debugPrint('[ExternalShare][Flutter] $message');
    }
  }
}
