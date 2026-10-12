import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/services/cache/app_image_cache_manager.dart';
import 'package:wefilling/services/post_media_prefetch_service.dart';
import 'package:wefilling/ui/widgets/user_avatar.dart';
import 'package:wefilling/utils/avatar_image.dart';
import 'package:wefilling/utils/profile_photo_policy.dart';

const String _allowedUrl =
    'https://firebasestorage.googleapis.com/v0/b/flutterproject3-af322.firebasestorage.app/o/profile_images%2Fu1%2Fa.jpg?alt=media&token=t';

Post _post(
  String id, {
  String uid = '',
  String photo = '',
  bool anonymous = false,
}) =>
    Post(
      id: id,
      title: '',
      content: id,
      author: 'author',
      createdAt: DateTime(2026, 10, 1),
      userId: uid.isEmpty ? 'user-$id' : uid,
      authorPhotoURL: photo,
      isAnonymous: anonymous,
    );

void main() {
  group('디코딩 크기 구간', () {
    test('논리 크기와 화면 배율을 몇 개 구간으로 묶는다', () {
      expect(avatarDecodeWidth(28, 3), 96); // 84px
      expect(avatarDecodeWidth(36, 3), 128); // 108px
      expect(avatarDecodeWidth(40, 3), 128); // 120px
      expect(avatarDecodeWidth(40, 2), 96); // 80px
      expect(avatarDecodeWidth(16, 2), 64); // 32px
      expect(avatarDecodeWidth(120, 3), 384); // 상한
    });
  });

  group('캐시 키', () {
    test('버전이 있으면 (uid, version), 없으면 URL', () {
      expect(
        AppImageCacheManager.avatarCacheKeyFor(
            uid: 'u1', photoVersion: 7, photoUrl: _allowedUrl),
        'u1_7',
      );
      expect(
        AppImageCacheManager.avatarCacheKeyFor(
            uid: 'u1', photoVersion: 0, photoUrl: _allowedUrl),
        _allowedUrl,
      );
    });
  });

  group('selectAuthorAvatarWarmTargets', () {
    test('익명·탈퇴·사진 없음·중복 작성자를 제외하고 순서를 유지한다', () {
      final targets = selectAuthorAvatarWarmTargets(<Post>[
        _post('a', uid: 'u1', photo: ' https://x/1.jpg '),
        _post('b', uid: 'u1', photo: 'https://x/dup.jpg'),
        _post('c', uid: 'u2', photo: 'https://x/2.jpg', anonymous: true),
        _post('d', uid: 'deleted', photo: 'https://x/3.jpg'),
        _post('e', uid: 'u3'),
        _post('f', uid: 'u4', photo: 'https://x/4.jpg'),
      ]);
      expect(targets.map((t) => t.uid), <String>['u1', 'u4']);
      expect(targets.first.photoUrl, 'https://x/1.jpg');
      expect(targets.every((t) => t.photoVersion == 0), isTrue);
    });

    test('최대 인원을 지킨다', () {
      final posts = List<Post>.generate(
        30,
        (i) => _post('p$i', uid: 'u$i', photo: 'https://x/$i.jpg'),
      );
      expect(selectAuthorAvatarWarmTargets(posts, maxAuthors: 5).length, 5);
      expect(selectAuthorAvatarWarmTargets(posts, maxAuthors: 0), isEmpty);
    });
  });

  group('UserAvatar', () {
    Future<void> pump(WidgetTester tester, Widget child) =>
        tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));

    testWidgets('익명이거나 허용되지 않은 주소면 placeholder만 그린다', (tester) async {
      await pump(
        tester,
        const UserAvatar(
          uid: 'u1',
          photoUrl: _allowedUrl,
          photoVersion: 3,
          isAnonymous: true,
          size: 36,
        ),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.person), findsOneWidget);

      await pump(
        tester,
        const UserAvatar(
          uid: 'u1',
          photoUrl: 'https://evil.example.com/a.jpg',
          photoVersion: 0,
          isAnonymous: false,
          size: 36,
        ),
      );
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('허용된 주소는 아바타 전용 provider와 같은 이미지를 쓴다', (tester) async {
      expect(ProfilePhotoPolicy.isAllowedProfilePhotoUrl(_allowedUrl), isTrue);
      late double ratio;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ratio = MediaQuery.devicePixelRatioOf(context);
          return const Scaffold(
            body: Center(
              child: UserAvatar(
                uid: 'u1',
                photoUrl: _allowedUrl,
                photoVersion: 3,
                isAnonymous: false,
                size: 28,
              ),
            ),
          );
        }),
      ));
      final image = tester.widget<Image>(find.byType(Image));
      // 미리 데운 provider와 같으면 ImageCache가 같은 항목으로 본다.
      expect(
        image.image,
        avatarImageProvider(
          uid: 'u1',
          photoVersion: 3,
          photoUrl: _allowedUrl,
          logicalSize: 28,
          devicePixelRatio: ratio,
        ),
      );
    });

    testWidgets('사진 버전이 바뀌면 새 이미지 위젯으로 교체된다', (tester) async {
      Widget avatar(int version) => UserAvatar(
            uid: 'u1',
            photoUrl: _allowedUrl,
            photoVersion: version,
            isAnonymous: false,
            size: 36,
          );
      await pump(tester, avatar(1));
      final first = tester.widget<Image>(find.byType(Image)).key;
      await pump(tester, avatar(2));
      final second = tester.widget<Image>(find.byType(Image)).key;
      expect(second, isNot(first));
    });
  });
}
