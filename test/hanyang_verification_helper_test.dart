import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/hanyang_verification_helper.dart';

void main() {
  group('isHanyangEmailVerified', () {
    test('explicit school verification is authoritative', () {
      expect(
        isHanyangEmailVerified({
          'hanyangEmailVerified': true,
          'hanyangEmail': 'student@hanyang.ac.kr',
        }),
        isTrue,
      );
      expect(
        isHanyangEmailVerified({
          'hanyangEmailVerified': false,
          'emailVerified': true,
          'hanyangEmail': 'student@hanyang.ac.kr',
        }),
        isFalse,
      );
    });

    test('general and social signup do not imply school verification', () {
      for (final method in ['email_code', 'social_en_bypass']) {
        expect(
          isHanyangEmailVerified({
            'emailVerified': true,
            'hanyangEmail': 'student@hanyang.ac.kr',
            'hanyangEmailVerified': false,
            'verificationMethod': method,
          }),
          isFalse,
        );
      }
    });

    test('method alone is not a second verification source', () {
      expect(
        isHanyangEmailVerified({
          'emailVerified': true,
          'hanyangEmail': 'student@hanyang.ac.kr',
          'verificationMethod': 'hanyang_email_code',
        }),
        isFalse,
      );
    });
  });
}
