// lib/services/profile_link.dart
// 프로필 공유 링크 생성/해석과 앱 링크(딥링크) 수신.

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/friend_profile_screen.dart';
import 'navigation_service.dart';

class ProfileLink {
  const ProfileLink._();

  /// 공유 링크가 가리키는 도메인(Firebase Hosting 기본 도메인).
  static const String webHost = 'flutterproject3-af322.web.app';

  /// 링크로 인정하는 도메인. 예전에 만든 링크도 열린다.
  static const Set<String> _acceptedHosts = {
    webHost,
    'flutterproject3-af322.firebaseapp.com',
    'wefilling.app',
    'www.wefilling.app',
  };

  /// 공유용 https 링크. 앱이 없으면 웹 안내 페이지가 열린다.
  static String build(String uid) => 'https://$webHost/u/$uid';

  /// `https://wefilling.app/u/{uid}` 또는 `wefilling://u/{uid}` 에서 uid를 꺼낸다.
  static String? parseUid(Uri uri) {
    String? raw;
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      if (!_acceptedHosts.contains(uri.host)) return null;
      final segments = uri.pathSegments;
      if (segments.length >= 2 && segments[0] == 'u') raw = segments[1];
    } else if (uri.scheme == 'wefilling' && uri.host == 'u') {
      if (uri.pathSegments.isNotEmpty) raw = uri.pathSegments.first;
    }
    final uid = raw?.trim() ?? '';
    // Firebase uid 형식만 허용한다(경로 조작 방지).
    if (!RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(uid)) return null;
    return uid;
  }
}

/// 앱 링크 수신기. 로그인 전에 받은 링크는 보관했다가 로그인 후 연다.
class ProfileLinkService {
  ProfileLinkService._();
  static final ProfileLinkService instance = ProfileLinkService._();

  StreamSubscription<Uri>? _subscription;
  String? _pendingUid;
  String? _lastLink;
  DateTime? _lastLinkAt;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    // 로그인·가입 완료 전에 받은 링크는 메인 화면이 준비되면 연다.
    NavigationService.routingReadyListenable.addListener(_onRoutingReady);
    try {
      final links = AppLinks();
      final initial = await links.getInitialLink();
      if (initial != null) _handle(initial);
      _subscription = links.uriLinkStream.listen(_handle, onError: (_) {});
    } catch (_) {
      // 플랫폼이 링크를 지원하지 않으면 조용히 건너뛴다.
    }
  }

  void _handle(Uri uri) {
    final uid = ProfileLink.parseUid(uri);
    if (uid == null) return;
    // 콜드 스타트 링크는 getInitialLink와 uriLinkStream으로 두 번 올 수 있다.
    final now = DateTime.now();
    final key = uri.toString();
    if (_lastLink == key &&
        _lastLinkAt != null &&
        now.difference(_lastLinkAt!) < const Duration(seconds: 3)) {
      return;
    }
    _lastLink = key;
    _lastLinkAt = now;
    _pendingUid = uid;
    openPending();
  }

  /// 로그인 완료 후에도 호출해 보관된 링크를 연다.
  void openPending() {
    final uid = _pendingUid;
    if (uid == null) return;
    final me = FirebaseAuth.instance.currentUser;
    final navigator = NavigationService.navigatorKey.currentState;
    // 로그인·가입 완료 전에는 보관만 한다(로그인 화면 위에 프로필을 올리지 않는다).
    if (me == null ||
        navigator == null ||
        !NavigationService.routingReadyListenable.value) {
      return;
    }
    _pendingUid = null;
    if (me.uid == uid) return;
    navigator.push<void>(
      MaterialPageRoute(
        builder: (_) => FriendProfileScreen(
          userId: uid,
          allowNonFriendsPreview: true,
        ),
      ),
    );
  }

  void _onRoutingReady() {
    if (_pendingUid == null || !NavigationService.routingReadyListenable.value) {
      return;
    }
    // 홈 화면이 먼저 그려진 뒤에 프로필을 올린다.
    WidgetsBinding.instance.addPostFrameCallback((_) => openPending());
  }

  void dispose() {
    NavigationService.routingReadyListenable.removeListener(_onRoutingReady);
    _subscription?.cancel();
    _subscription = null;
    _started = false;
  }
}
