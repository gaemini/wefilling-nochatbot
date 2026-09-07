import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/nickname_policy.dart';

void main() {
  group('NicknamePolicy', () {
    test('accepts supported identity combinations', () {
      for (final value in <String>[
        '차재민',
        'Jaemin',
        '한국인_Student1',
        'Jaemin_98',
      ]) {
        expect(NicknamePolicy.validate(value), isNull, reason: value);
      }
    });

    test('normalizes whitespace and common NFKC compatibility input', () {
      expect(NicknamePolicy.normalizePreview('  Cha   Jaemin  '), 'Cha_Jaemin');
      expect(NicknamePolicy.normalizePreview('차 재민'), '차_재민');
      expect(NicknamePolicy.normalizePreview('Ｔｅｓｔ　Ｕｓｅｒ'), 'Test_User');
      expect(NicknamePolicy.normalizePreview('Jae\u200bmin'), 'Jaemin');
    });

    test('uses a locale-independent case-insensitive canonical key', () {
      expect(NicknamePolicy.canonicalKey('Cha Jaemin'), 'cha_jaemin');
      expect(NicknamePolicy.canonicalKey('CHA_JAEMIN'), 'cha_jaemin');
    });

    test('rejects unsupported and non-identifying values', () {
      expect(
        NicknamePolicy.validate('user.name'),
        NicknameValidationIssue.invalidCharacters,
      );
      expect(
        NicknamePolicy.validate('user-name'),
        NicknameValidationIssue.invalidCharacters,
      );
      expect(
        NicknamePolicy.validate('사용자😊'),
        NicknameValidationIssue.invalidCharacters,
      );
      expect(
        NicknamePolicy.validate('12_34'),
        NicknameValidationIssue.letterRequired,
      );
      expect(
        NicknamePolicy.validate('_____'),
        NicknameValidationIssue.letterRequired,
      );
    });

    test('enforces length and reserved identities', () {
      expect(NicknamePolicy.validate('a'), NicknameValidationIssue.length);
      expect(
        NicknamePolicy.validate('abcdefghijklmnopqrstu'),
        NicknameValidationIssue.length,
      );
      expect(
        NicknamePolicy.validate('anonymous'),
        NicknameValidationIssue.reserved,
      );
      expect(
        NicknamePolicy.validate('삭제된 계정'),
        NicknameValidationIssue.reserved,
      );
    });
  });
}
