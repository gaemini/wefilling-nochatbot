import 'package:flutter_test/flutter_test.dart';
import 'package:wefilling/services/snack_chat_service.dart';

void main() {
  test('today summary window follows the same device-local calendar day', () {
    final requestedAt = DateTime(2026, 9, 5, 1, 7);
    final window = buildSnackChatTodaySummaryWindow(requestedAt);

    expect(window.localDate, '2026-09-05');
    expect(window.start, DateTime(2026, 9, 5));
    expect(window.nextStart, DateTime(2026, 9, 6));
    expect(window.start.isBefore(requestedAt), isTrue);
    expect(window.nextStart.isAfter(requestedAt), isTrue);
  });

  test('today response keeps its range identity and total message count', () {
    final result = SnackChatUnreadSummaryResult.fromMap(<String, dynamic>{
      'summarySchemaVersion': 3,
      'summaryVersion': 7,
      'promptVersion': 7,
      'rangeType': 'today',
      'localDate': '2026-09-05',
      'firstSequence': 350,
      'latestSequence': 412,
      'totalTodayMessageCount': 24,
      'overview': '오늘 회의와 준비 작업이 정리됐어요.',
      'sections': <Object?>[
        <String, dynamic>{
          'type': 'mustKnow',
          'items': <Object?>[
            <String, dynamic>{
              'title': '파일 정리',
              'description': '파일을 오늘까지 보내야 해요.',
              'status': 'information',
              'sourceSequences': <int>[350],
            },
          ],
        },
      ],
    });

    expect(result.rangeType, SnackChatSummaryRangeType.today);
    expect(result.localDate, '2026-09-05');
    expect(result.firstSequence, 350);
    expect(result.latestSequence, 412);
    expect(result.messageCount, 24);
    expect(result.isLegacy, isFalse);
  });

  test('safe fallback response remains displayable and identifiable', () {
    final result = SnackChatUnreadSummaryResult.fromMap(<String, dynamic>{
      'success': true,
      'summarySchemaVersion': 3,
      'summaryVersion': 7,
      'promptVersion': 7,
      'summarySource': 'fallback',
      'cacheSource': 'fallback',
      'overview': '',
      'messageCount': 3,
      'sections': <Object?>[
        <String, dynamic>{
          'type': 'responseRequired',
          'items': <Object?>[
            <String, dynamic>{
              'title': '확인이 필요한 메시지',
              'description': '질문이나 요청이 포함된 메시지가 있어요.',
              'status': 'responseRequired',
              'importance': 'critical',
              'sourceMessageIds': <String>['message-1'],
              'representativeMessageId': 'message-1',
              'sourceSequences': <int>[1],
            },
          ],
        },
      ],
    });

    expect(result.isFallback, isTrue);
    expect(result.isLegacy, isFalse);
    expect(result.items, hasLength(1));
    expect(result.summaryVersion, 7);
  });

  test('structured summary response keeps sections, states, and evidence', () {
    final result = SnackChatUnreadSummaryResult.fromMap(<String, dynamic>{
      'summarySchemaVersion': 3,
      'summaryVersion': 4,
      'promptVersion': 4,
      'targetLanguage': 'ko',
      'firstUnreadSequence': 120,
      'latestSequence': 165,
      'totalUnreadMessageCount': 24,
      'sourceHash': 'range-hash',
      'cacheSource': 'gemini',
      'sourceStartedAt': '2026-09-04T08:47:00.000Z',
      'sourceEndedAt': '2026-09-04T11:15:00.000Z',
      'overview': '금요일 모임 일정을 정하고 있으며, 아직 내 투표가 필요해요.',
      'otherConversationSummary': '일정 안내 뒤 짧은 인사와 반응이 오갔어요.',
      'sections': <Object?>[
        <String, dynamic>{
          'type': 'responseRequired',
          'items': <Object?>[
            <String, dynamic>{
              'title': '날짜 투표',
              'description': '@차재민님에게 날짜 투표 참여 요청이 왔어요.',
              'status': 'responseRequired',
              'importance': 'critical',
              'sourceMessageIds': <String>['message-130'],
              'representativeMessageId': 'message-130',
              'sourceSequences': <int>[130],
            },
          ],
        },
        <String, dynamic>{
          'type': 'sharedInformation',
          'items': <Object?>[
            <String, dynamic>{
              'title': '일정 안내',
              'description': '모임 준비 일정이 공유됐어요.',
              'status': 'information',
              'importance': 'general',
              'sourceMessageIds': <String>['message-131', 'message-132'],
              'representativeMessageId': 'message-132',
              'sourceSequences': <int>[131, 132],
            },
          ],
        },
      ],
    });

    expect(result.sections, hasLength(2));
    expect(
      result.sections.first.type,
      SnackChatSummarySectionType.responseRequired,
    );
    expect(
      result.sections.first.items.single.status,
      SnackChatSummaryStatus.responseRequired,
    );
    expect(
      result.sections.first.items.single.sourceMessageIds,
      <String>['message-130'],
    );
    expect(result.items, hasLength(2));
    expect(result.overview, contains('투표'));
    expect(result.otherConversationSummary, contains('인사'));
    expect(result.isLegacy, isFalse);
    expect(result.messageCount, 24);
    expect(result.firstUnreadSequence, 120);
    expect(result.latestSequence, 165);
    expect(result.sourceStartedAt, DateTime.utc(2026, 9, 4, 8, 47));
  });

  test('unknown enum values and invalid evidence degrade safely', () {
    final result = SnackChatUnreadSummaryResult.fromMap(<String, dynamic>{
      'success': true,
      'summarySchemaVersion': 3,
      'overview': '근거가 있는 내용을 간단히 정리했어요.',
      'sections': <Object?>[
        <String, dynamic>{
          'type': 'inventedSection',
          'title': '안전한 기본 섹션',
          'items': <Object?>[
            <String, dynamic>{
              'description': '근거가 있는 항목',
              'title': '안내',
              'status': 'inventedStatus',
              'sourceSequences': <int>[7],
            },
            <String, dynamic>{
              'description': '근거가 없는 항목',
              'title': '제외 대상',
              'sourceSequences': <int>[],
            },
          ],
        },
      ],
    });

    expect(result.sections, hasLength(1));
    expect(result.sections.single.type,
        SnackChatSummarySectionType.sharedInformation);
    expect(result.items, hasLength(1));
    expect(result.items.single.status, SnackChatSummaryStatus.information);
  });

  test('legacy flat items remain readable for rolling deployments', () {
    final result = SnackChatUnreadSummaryResult.fromMap(<String, dynamic>{
      'messageCount': 6,
      'rangeHash': 'legacy-hash',
      'items': <Object?>[
        <String, dynamic>{
          'text': '금요일 오후 7시가 제안됐어요.',
          'sourceSequences': <int>[10, 11],
        },
      ],
    });

    expect(result.items.single.content, contains('오후 7시'));
    expect(result.sections.single.type, SnackChatSummarySectionType.mustKnow);
    expect(result.messageCount, 6);
    expect(result.isLegacy, isTrue);
  });

  test('new general-only summary does not duplicate overview as a section', () {
    final result = SnackChatUnreadSummaryResult.fromMap(<String, dynamic>{
      'summarySchemaVersion': 3,
      'summaryVersion': 4,
      'promptVersion': 4,
      'overview': '오랜만에 안부를 나누며 가볍게 근황을 이야기했어요.',
      'otherConversationSummary': '주말 계획에 관한 짧은 대화도 오갔어요.',
      'items': <Object?>[
        <String, dynamic>{
          'text': '오랜만에 안부를 나누며 가볍게 근황을 이야기했어요.',
          'sourceSequences': <int>[21, 22, 23],
        },
      ],
      'sections': <Object?>[],
    });

    expect(result.isLegacy, isFalse);
    expect(result.items, hasLength(1));
    expect(result.sections, isEmpty);
  });
}
