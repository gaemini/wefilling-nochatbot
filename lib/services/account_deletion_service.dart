import 'dart:io' show Platform;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../config/app_config.dart';

class AccountDeletionService {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Google 계정으로 재인증
  Future<void> reauthenticateWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }

    try {
      // Google Sign-In 7.x API 사용
      final GoogleSignIn googleSignIn = GoogleSignIn.instance;
      
      // 플랫폼별 clientId 분기 (iOS/macOS만)
      final clientId = AppConfig.getGoogleClientId();
      await googleSignIn.initialize(clientId: clientId);
      
      // 기존 로그인 세션 초기화
      await googleSignIn.signOut();
      
      // authenticate 메소드로 재인증
      final GoogleSignInAccount googleUser = await googleSignIn.authenticate();

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      await user.reauthenticateWithCredential(credential);
    } catch (e) {
      throw Exception('Google 재인증 실패: $e');
    }
  }

  /// Apple 계정으로 재인증
  Future<void> reauthenticateWithApple() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('로그인된 사용자가 없습니다.');
    }

    try {
      // Apple Sign-In
      final appleProvider = AppleAuthProvider();
      appleProvider.addScope('email');
      appleProvider.addScope('name');

      await user.reauthenticateWithProvider(appleProvider);
    } catch (e) {
      throw Exception('Apple 재인증 실패: $e');
    }
  }

  Future<void> deleteAccountImmediately({required String reason}) async {
    final callable = _functions.httpsCallable('deleteAccountImmediately');
    await callable.call({
      'reason': reason,
    });
  }
}
