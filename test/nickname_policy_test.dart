import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/nickname_policy.dart';

void main() {
  test('new names use NFC, trim, Korean/English, and existing length limit', () {
    for (final raw in ['차재민', 'Jaemin', '  Jaemin  ', '한글', '한글English']) {
      expect(NicknamePolicy.validate(raw), isNull, reason: raw);
    }
    expect(NicknamePolicy.normalizePreview('한글'), '한글');
    expect(NicknamePolicy.canonicalKey(' Jaemin '), 'jaemin');
    expect(NicknamePolicy.canonicalKey('jaemin'), 'jaemin');
    expect(NicknamePolicy.validate('a'), NicknameValidationIssue.length);
    expect(NicknamePolicy.validate('abcdefghijklmnopqrstu'), NicknameValidationIssue.length);
    expect(NicknamePolicy.validate('anonymous'), NicknameValidationIssue.reserved);
    expect(NicknamePolicy.version, 3);
  });

  test('rejects instead of silently deleting or converting invalid input', () {
    for (final raw in ['Jaemin1', 'Jaemin_98', 'Cha Jaemin', 'user.name',
      'user-name', '사용자😊', '中文', 'ひらがな', 'ㄱㄴ', 'Ｔｅｓｔ',
      'Jae\u200bmin', 'Jae\u0085min', 'Jae\nmin', '12_34', '_____']) {
      expect(NicknamePolicy.validate(raw), NicknameValidationIssue.invalidCharacters, reason: raw);
      expect(NicknamePolicy.normalizePreview(raw), raw, reason: raw);
    }
  });
}
