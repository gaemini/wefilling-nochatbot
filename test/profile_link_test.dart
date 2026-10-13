import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/profile_link.dart';
import 'package:wefilling/ui/widgets/profile_share_sheet.dart';

void main() {
  group('ProfileLink', () {
    test('https 링크에서 uid를 꺼낸다', () {
      expect(
        ProfileLink.parseUid(Uri.parse('https://flutterproject3-af322.web.app/u/abc123XYZ')),
        'abc123XYZ',
      );
      expect(ProfileLink.build('abc123XYZ'), 'https://flutterproject3-af322.web.app/u/abc123XYZ');
    });

    test('앱 스킴 링크도 지원한다', () {
      expect(ProfileLink.parseUid(Uri.parse('wefilling://u/abc123XYZ')), 'abc123XYZ');
      // 예전 도메인 링크도 연다.
      expect(ProfileLink.parseUid(Uri.parse('https://wefilling.app/u/abc123XYZ')), 'abc123XYZ');
    });

    test('다른 도메인·경로·위험한 uid는 거부한다', () {
      expect(ProfileLink.parseUid(Uri.parse('https://evil.com/u/abc123XYZ')), isNull);
      expect(ProfileLink.parseUid(Uri.parse('https://flutterproject3-af322.web.app/p/abc123XYZ')), isNull);
      expect(ProfileLink.parseUid(Uri.parse('https://wefilling.app/u/..%2Fadmin')), isNull);
      expect(ProfileLink.parseUid(Uri.parse('https://wefilling.app/u/a')), isNull);
      expect(ProfileLink.parseUid(Uri.parse('wefilling://organization-invite?token=x')), isNull);
    });
  });

  testWidgets('공유 시트에 QR·링크·두 버튼이 보인다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ProfileShareSheet(uid: 'abc123XYZ', nickname: '민수'),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('profile_share_qr')), findsOneWidget);
    expect(find.text('https://flutterproject3-af322.web.app/u/abc123XYZ'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile_share_copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile_share_system')), findsOneWidget);
  });
}
