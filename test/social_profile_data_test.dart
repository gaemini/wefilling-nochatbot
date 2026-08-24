import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/social_profile_data.dart';

void main() {
  group('SocialProfileData conversation starter', () {
    test('기존 공강 질문을 상대방에게 묻는 존댓말로 표시한다', () {
      final profile = SocialProfileData.fromMap(<String, dynamic>{
        'conversationStarter': '공강 시간에는 주로 무엇을 하나요?',
      });

      expect(profile.conversationStarter, '공강 시간에는 주로 무엇을 하시나요?');
    });

    test('사용자가 직접 작성한 질문은 변경하지 않는다', () {
      final profile = SocialProfileData.fromMap(<String, dynamic>{
        'conversationStarter': '요즘 어떤 음악을 듣고 계시나요?',
      });

      expect(profile.conversationStarter, '요즘 어떤 음악을 듣고 계시나요?');
    });
  });
}
