import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/interest_tag.dart';

void main() {
  test('공식 태그는 UI 언어 이름, 사용자 태그는 만든 이름', () {
    final running = InterestTag.fromMap('running', {
      'displayName': 'Running',
      'labels': {'ko': '러닝', 'en': 'Running', 'zh': '跑步'},
      'official': true,
      'holderCount': 12,
    });
    expect(running.labelFor('ko'), '러닝');
    expect(running.labelFor('zh'), '跑步');
    expect(running.labelFor('ja'), 'Running');
    expect(running.holderCount, 12);

    final kpop = InterestTag.fromMap('kpop', {'displayName': 'K-POP', 'labels': {}});
    expect(kpop.labelFor('ko'), 'K-POP');
    expect(kpop.official, isFalse);
    expect(kpop.postCount, 0);
  });
}
