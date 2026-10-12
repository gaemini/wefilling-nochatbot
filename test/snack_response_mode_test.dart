import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/models/snapshot.dart';
import 'package:wefilling/snapshot/snack_response_policy.dart';

void main() {
  test('responseMode는 저장 값이 없으면 기존 동작(답장 받기)으로 해석한다', () {
    expect(SnapshotResponseMode.fromValue(null), SnapshotResponseMode.replies);
    expect(SnapshotResponseMode.fromValue('view_only'),
        SnapshotResponseMode.viewOnly);
    expect(SnapshotResponseMode.fromValue('reactions'),
        SnapshotResponseMode.reactions);
    expect(SnapshotResponseMode.fromValue('garbage'),
        SnapshotResponseMode.replies);
  });

  test('보기만/반응/답장은 허용 행동이 단계적으로 늘어난다', () {
    const viewOnly = SnapshotResponseMode.viewOnly;
    const reactions = SnapshotResponseMode.reactions;
    const replies = SnapshotResponseMode.replies;
    expect(viewOnly.allowsReaction, isTrue);
    expect(viewOnly.allowsTextReply, isFalse);
    expect(viewOnly.allowsSnackReply, isFalse);
    expect(reactions.allowsTextReply, isTrue);
    expect(reactions.allowsSnackReply, isFalse);
    expect(replies.allowsTextReply, isTrue);
    expect(replies.allowsSnackReply, isTrue);
  });

  test('SnapshotItem.fromMap은 responseMode와 캡션 필드를 읽고 기본값을 둔다', () {
    final legacy = SnapshotItem.fromMap('a', <String, dynamic>{
      'authorId': 'u1',
      'overlays': [
        {'id': 'o', 'text': '첫 줄 텍스트', 'x': .5, 'y': .5, 'lightText': true}
      ],
    });
    expect(legacy.responseMode, SnapshotResponseMode.replies);
    expect(legacy.hasTranslatedCaption, isFalse);
    expect(legacy.displayCaption, '첫 줄 텍스트');
    expect(legacy.isSnackReply, isFalse);

    final item = SnapshotItem.fromMap('b', <String, dynamic>{
      'authorId': 'u1',
      'responseMode': 'view_only',
      'caption': '원문',
      'translatedCaption': '번역',
      'sourceLanguage': 'en',
      'replyToSnapshotId': 'a',
    });
    expect(item.responseMode, SnapshotResponseMode.viewOnly);
    expect(item.displayCaption, '원문');
    expect(item.hasTranslatedCaption, isTrue);
    expect(item.isSnackReply, isTrue);
  });

  test('밋업 제안은 네 조건을 모두 만족할 때만 보인다', () {
    expect(
      canOfferMeetupDraft(
        responseMode: SnapshotResponseMode.replies,
        replyCount: 1,
        hasTimeOrPlaceContext: true,
        canCreateMeetup: true,
      ),
      isTrue,
    );
    expect(
      canOfferMeetupDraft(
        responseMode: SnapshotResponseMode.reactions,
        replyCount: 1,
        hasTimeOrPlaceContext: true,
        canCreateMeetup: true,
      ),
      isFalse,
    );
    expect(
      canOfferMeetupDraft(
        responseMode: SnapshotResponseMode.replies,
        replyCount: 0,
        hasTimeOrPlaceContext: true,
        canCreateMeetup: true,
      ),
      isFalse,
    );
    expect(
      canOfferMeetupDraft(
        responseMode: SnapshotResponseMode.replies,
        replyCount: 2,
        hasTimeOrPlaceContext: false,
        canCreateMeetup: true,
      ),
      isFalse,
    );
    expect(showSnackReplyEntry(SnapshotResponseMode.replies), isTrue);
    expect(showSnackReplyEntry(SnapshotResponseMode.reactions), isFalse);
  });
}
