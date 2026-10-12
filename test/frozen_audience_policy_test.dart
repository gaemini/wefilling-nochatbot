import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/security/frozen_audience_policy.dart';

void main() {
  const owner = 'owner';
  const memberAtCreation = 'member-at-creation';
  const joinedLater = 'joined-later';

  bool canRead(String viewer, List<String> frozen) {
    return FrozenAudiencePolicy.canRead(
      viewerId: viewer,
      ownerId: owner,
      visibilityMode: 'category',
      audienceUserIdsFrozen: frozen,
    );
  }

  group('frozen audience invariants', () {
    test('그룹에서 나중에 제거돼도 기존 콘텐츠 접근은 유지된다', () {
      const frozenAtCreation = <String>[owner, memberAtCreation];
      const currentGroupAfterRemoval = <String>[owner];

      expect(currentGroupAfterRemoval, isNot(contains(memberAtCreation)));
      expect(canRead(memberAtCreation, frozenAtCreation), isTrue);
    });

    test('그룹에 나중에 추가돼도 기존 콘텐츠 접근은 생기지 않는다', () {
      const frozenAtCreation = <String>[owner, memberAtCreation];
      const currentGroupAfterAddition = <String>[
        owner,
        memberAtCreation,
        joinedLater,
      ];

      expect(currentGroupAfterAddition, contains(joinedLater));
      expect(canRead(joinedLater, frozenAtCreation), isFalse);
    });

    test('같은 그룹에서 만든 콘텐츠도 각 audience snapshot이 독립적이다', () {
      const olderContent = <String>[owner, memberAtCreation];
      const newerContent = <String>[owner, joinedLater];

      expect(canRead(memberAtCreation, olderContent), isTrue);
      expect(canRead(memberAtCreation, newerContent), isFalse);
      expect(canRead(joinedLater, olderContent), isFalse);
      expect(canRead(joinedLater, newerContent), isTrue);
    });

    test('owner/public/unknown mode는 fail-closed 규칙을 따른다', () {
      expect(canRead(owner, const <String>[]), isTrue);
      expect(
        FrozenAudiencePolicy.canRead(
          viewerId: joinedLater,
          ownerId: owner,
          visibilityMode: 'public',
          audienceUserIdsFrozen: const <String>[owner],
        ),
        isTrue,
      );
      expect(
        FrozenAudiencePolicy.canRead(
          viewerId: joinedLater,
          ownerId: owner,
          visibilityMode: 'unknown',
          audienceUserIdsFrozen: const <String>[owner, joinedLater],
        ),
        isFalse,
      );
      expect(
        FrozenAudiencePolicy.canRead(
          viewerId: null,
          ownerId: owner,
          visibilityMode: 'public',
          audienceUserIdsFrozen: const <String>[owner],
        ),
        isFalse,
      );
    });
  });
}
