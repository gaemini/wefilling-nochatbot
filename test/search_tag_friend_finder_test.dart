import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/interest_tag.dart';
import 'package:wefilling/repositories/users_repository.dart';
import 'package:wefilling/services/interest_tag_service.dart';

import 'support/translation_test_backend.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final backend = TranslationTestBackend();
  setUpAll(backend.initialize);
  tearDownAll(backend.close);

  setUp(() => InterestTagService.instance
    ..debugReset()
    ..debugPut(const InterestTag(id: 'kpop', displayName: 'K-POP')));
  tearDown(() => InterestTagService.instance.debugReset());

  test('검색 화면 태그로 친구 찾기는 listTagHolders(모든 태그, 최근 순)를 쓴다', () async {
    final calls = <Map<String, Object?>>[];
    InterestTagService.instance.debugCall = (name, data) async {
      expect(name, 'listTagHolders');
      calls.add(data);
      return {
        'users': [
          {
            'uid': 'u1',
            'nickname': '하늘',
            'photoURL': '',
            'nationality': 'KR',
            'university': 'Hanyang',
            'tags': ['kpop', 'running'],
          },
        ],
        'cursor': '1792123193000_u1',
      };
    };
    await backend.setAccount('me');
    final page = await UsersRepository().searchUsersByInterest('kpop');
    expect(calls.single['tagId'], 'kpop');
    expect(page.users.single.uid, 'u1');
    expect(page.users.single.interestTagIds, ['kpop', 'running']);
    expect(page.nextCursor, '1792123193000_u1');
    expect(page.hasMore, isTrue);

    await UsersRepository().searchUsersByInterest('kpop', cursor: page.nextCursor);
    expect(calls.last['cursor'], '1792123193000_u1');
  });
}
