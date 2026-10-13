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

  static const String webHost = 'wefilling.app';

  /// 공유용 https 링크. 앱이 없으면 웹 안내 페이지가 열린다.
  static String build(String uid) => 'https://$webHost/u/$uid';

  /// `https://wefilling.app/u/{uid}` 또는 `wefilling://u/{uid}` 에서 uid를 꺼낸다.
  static String? parseUid(Uri uri) {
    String? raw;
    if (uri.scheme == 'https' || uri.scheme == 'http') {
      if (uri.host != webHost && uri.host != 'www.$webHost') return null;
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
  StreamSubscription<User?>? _authSubscription;
  String? _pendingUid;
  bool _started = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    // 로그인 전에 받은 링크는 로그인 완료 후 연다.
    _authSubscription = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null && _pendingUid != null) {
        // 첫 화면이 그려진 뒤에 push 한다.
        WidgetsBinding.instance.addPostFrameCallback((_) => openPending());
      }
    });
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
    _pendingUid = uid;
    openPending();
  }

  /// 로그인 완료 후에도 호출해 보관된 링크를 연다.
  void openPending() {
    final uid = _pendingUid;
    if (uid == null) return;
    final me = FirebaseAuth.instance.currentUser;
    final navigator = NavigationService.navigatorKey.currentState;
    if (me == null || navigator == null) return;
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

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _authSubscription?.cancel();
    _authSubscription = null;
    _started = false;
  }
}
