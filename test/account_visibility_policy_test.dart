import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/utils/account_status_helper.dart';

void main() {
  Map<String, dynamic> complete({String nickname = 'friend_01'}) =>
      <String, dynamic>{
        'nickname': nickname,
        'email': 'f@example.com',
        'registrationStatus': 'complete',
      };

  group('isVisibleUserAccountData (friend list / participants)', () {
    test('keeps friends that the search policy would hide', () {
      // Chinese nickname, nickname with a space, search turned off, private
      // profile: all are still friends and must stay in the friend list.
      expect(
        isVisibleUserAccountData(complete(nickname: '小明'), uid: 'u1'),
        isTrue,
      );
      expect(
        isVisibleUserAccountData(complete(nickname: 'Jae min'), uid: 'u2'),
        isTrue,
      );
      expect(
        isVisibleUserAccountData(
            {...complete(), 'allowUserSearch': false}, uid: 'u3'),
        isTrue,
      );
      expect(
        isVisibleUserAccountData(
            {...complete(), 'isProfilePrivate': true}, uid: 'u4'),
        isTrue,
      );
      // The search policy indeed hides them, which was the bug.
      expect(
        isSearchableUserAccountData(complete(nickname: '小明'), uid: 'u1'),
        isFalse,
      );
    });

    test('still drops deleted, suspended, deleting and incomplete accounts', () {
      expect(
        isVisibleUserAccountData({...complete(), 'isDeleted': true}, uid: 'u'),
        isFalse,
      );
      expect(
        isVisibleUserAccountData(
            {...complete(), 'status': 'suspended'}, uid: 'u'),
        isFalse,
      );
      expect(
        isVisibleUserAccountData({...complete(), 'deleting': true}, uid: 'u'),
        isFalse,
      );
      expect(
        isVisibleUserAccountData(
            {...complete(), 'registrationStatus': 'pending'}, uid: 'u'),
        isFalse,
      );
      expect(
        isVisibleUserAccountData(
            {'nickname': 'DELETED_ACCOUNT', 'registrationStatus': 'complete'},
            uid: 'u'),
        isFalse,
      );
      expect(isVisibleUserAccountData(complete(), uid: 'deleted'), isFalse);
      expect(isVisibleUserAccountData(null, uid: 'u'), isFalse);
    });

    test('legacy profiles without registrationStatus need a verified email', () {
      expect(
        isVisibleUserAccountData(
            {'nickname': 'legacy', 'email': 'l@x.com', 'emailVerified': true},
            uid: 'u'),
        isTrue,
      );
      expect(
        isVisibleUserAccountData(
            {'nickname': 'legacy', 'email': 'l@x.com', 'emailVerified': false},
            uid: 'u'),
        isFalse,
      );
    });
  });
}
