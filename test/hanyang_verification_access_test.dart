import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/meetup.dart';
import 'package:wefilling/models/post.dart';
import 'package:wefilling/utils/hanyang_verification_helper.dart';

void main() {
  group('Hanyang verification state', () {
    test('completed signup can remain Hanyang-unverified', () {
      expect(
        isHanyangEmailVerified({
          'emailVerified': true,
          'hanyangEmailVerified': false,
          'signupLanguage': 'ko',
        }),
        isFalse,
      );
    });

    test('explicit Hanyang verification is recognized', () {
      expect(
        isHanyangEmailVerified({
          'emailVerified': true,
          'hanyangEmailVerified': true,
          'hanyangEmail': 'student@hanyang.ac.kr',
        }),
        isTrue,
      );
    });

    test('Hanyang address without the verification method stays locked', () {
      expect(
        isHanyangEmailVerified({
          'emailVerified': true,
          'hanyangEmail': 'student@hanyang.ac.kr',
        }),
        isFalse,
      );
    });

    test('legacy metadata does not override the canonical boolean', () {
      expect(
        isHanyangEmailVerified({
          'emailVerified': true,
          'hanyangEmail': 'student@hanyang.ac.kr',
          'schoolVerificationMethod': 'hanyang_email_code',
          'hanyangEmailVerifiedAt': DateTime(2026, 8, 25),
        }),
        isFalse,
      );
    });
  });

  test('post keeps Hanyang-only content marker through cache mapping', () {
    final post = Post(
      id: 'post',
      title: '',
      content: 'restricted',
      author: 'author',
      createdAt: DateTime(2026, 8, 25),
      userId: 'uid',
      requiresHanyangVerification: true,
    );

    expect(
      Post.fromMap(post.toMap(), post.id).requiresHanyangVerification,
      isTrue,
    );
  });

  test('meetup keeps Hanyang-only marker through JSON mapping', () {
    final meetup = Meetup(
      id: 'meetup',
      title: 'title',
      description: 'description',
      location: 'location',
      time: '12:00',
      maxParticipants: 10,
      currentParticipants: 1,
      host: 'host',
      imageUrl: '',
      date: DateTime(2026, 8, 25),
      requiresHanyangVerification: true,
    );

    expect(
      Meetup.fromJson(meetup.toJson()).requiresHanyangVerification,
      isTrue,
    );
  });
}
