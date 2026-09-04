'use strict';

const assert = require('node:assert/strict');
const {
  unreadSummaryTestHelpers,
} = require('../lib/snack_chat');
const {
  GeminiHttpError,
  GeminiStructuredResponseError,
} = require('../lib/content_translation');

const source = (overrides) => ({
  messageId: 'message-1',
  sequence: 1,
  senderId: 'sender-1',
  sender: 'Watson',
  sentAt: '2026-09-04T04:08:00.000Z',
  type: 'text',
  content: 'A deliberately unique source sentence that must not be copied.',
  replyToMessageId: '',
  replyTargetSenderId: '',
  directlyMentionsRequester: false,
  repliesToRequester: false,
  ...overrides,
});

const sources = [
  source({content: 'Could you confirm the plan?', directlyMentionsRequester: true}),
  source({
    messageId: 'message-2',
    sequence: 2,
    content: 'The meeting is tomorrow at 10:30.',
  }),
  source({
    messageId: 'message-3',
    sequence: 3,
    type: 'file',
    content: '[File attachment: agenda.pdf]',
  }),
];

const fallback = unreadSummaryTestHelpers.fallback(sources, 'en');
assert.match(fallback.overview, /confirm the plan/);
assert.ok(fallback.sections.length >= 2);
const items = fallback.sections.flatMap((section) => section.items);
assert.ok(items.every((item) => item.sourceMessageIds.length > 0));
assert.ok(items.every((item) => item.sourceMessageIds.every((id) =>
  sources.some((message) => message.messageId === id))));
assert.ok(items.some((item) => item.content.includes('confirm the plan')));
assert.ok(items.every((item) => !/check the (?:chat|original)/i.test(item.content)));

// Gemini compiles the response schema before generation. Nested maxItems
// constraints make this schema exceed its structured-output complexity limit
// and cause HTTP 400, while runtime validation already bounds every array.
assert.doesNotMatch(
  JSON.stringify(unreadSummaryTestHelpers.responseSchema([])),
  /"maxItems"/,
);

const classifiedFallback = unreadSummaryTestHelpers.fallback([
  source({
    content: 'Please organize and send the files today.',
    directlyMentionsRequester: true,
  }),
  source({
    messageId: 'message-2',
    sequence: 2,
    content: 'Can you attend the meeting tonight?',
    directlyMentionsRequester: true,
  }),
], 'en');
const actionSection = classifiedFallback.sections.find((section) =>
  section.type === 'mustKnow');
const replySection = classifiedFallback.sections.find((section) =>
  section.type === 'responseRequired');
assert.ok(actionSection);
assert.ok(replySection);
assert.deepEqual(actionSection.items[0].sourceSequences, [1]);
assert.deepEqual(replySection.items[0].sourceSequences, [2]);

const actionQuestionFallback = unreadSummaryTestHelpers.fallback([
  source({content: 'Could you clean the club room?'}),
], 'en');
assert.equal(actionQuestionFallback.sections[0]?.type, 'mustKnow');
assert.equal(
  actionQuestionFallback.sections.some((section) =>
    section.type === 'responseRequired'),
  false,
);

// Today is a device-local calendar range, not a rolling 24-hour window.
const todayRequestAt = Date.parse('2026-09-04T16:00:00.000Z');
const todayRange = unreadSummaryTestHelpers.todayRange({
  localDate: '2026-09-05',
  timezoneOffsetMinutes: 540,
  timezoneName: 'KST',
  todayStartUtc: '2026-09-04T15:00:00.000Z',
  tomorrowStartUtc: '2026-09-05T15:00:00.000Z',
}, todayRequestAt);
assert.equal(todayRange.localDate, '2026-09-05');
assert.equal(todayRange.startMillis, Date.parse('2026-09-04T15:00:00.000Z'));
assert.equal(unreadSummaryTestHelpers.timestampIsInTodayRange(
  Date.parse('2026-09-04T14:59:59.999Z'),
  todayRange,
  todayRequestAt,
), false);
assert.equal(unreadSummaryTestHelpers.timestampIsInTodayRange(
  Date.parse('2026-09-04T15:00:00.000Z'),
  todayRange,
  todayRequestAt,
), true);
assert.equal(unreadSummaryTestHelpers.timestampIsInTodayRange(
  Date.parse('2026-09-04T16:00:00.001Z'),
  todayRange,
  todayRequestAt,
), false);
assert.throws(() => unreadSummaryTestHelpers.todayRange({
  localDate: '2026-09-04',
  timezoneOffsetMinutes: 540,
  timezoneName: 'KST',
  todayStartUtc: '2026-09-03T15:00:00.000Z',
  tomorrowStartUtc: '2026-09-04T15:00:00.000Z',
}, todayRequestAt));

assert.equal(unreadSummaryTestHelpers.worthGenerating([
  source({content: 'The meeting is today at 5 PM.'}),
], 'today'), true);
assert.equal(unreadSummaryTestHelpers.worthGenerating([
  source({content: 'ok'}),
], 'today'), false);
assert.equal(unreadSummaryTestHelpers.worthGenerating(sources.slice(0, 2)), false);
assert.equal(unreadSummaryTestHelpers.worthGenerating([
  source({content: '🙂'}),
  source({messageId: 'message-2', sequence: 2, content: 'ㅋㅋ'}),
  source({messageId: 'message-3', sequence: 3, content: 'ok'}),
]), false);

const generationSources = unreadSummaryTestHelpers.generationSources([
  source({content: 'hello'}),
  source({
    messageId: 'message-2',
    sequence: 2,
    content: 'Could we meet at 7 PM?',
  }),
  source({messageId: 'message-3', sequence: 3, content: 'ok'}),
  source({messageId: 'message-4', sequence: 4, content: 'thanks'}),
  source({messageId: 'message-5', sequence: 5, content: 'no'}),
]);
assert.deepEqual(
  generationSources.map((message) => message.messageId),
  ['message-2', 'message-3', 'message-5'],
);
assert.equal(
  unreadSummaryTestHelpers.generationSources([
    source({content: 'thanks', replyToMessageId: 'question-1'}),
  ]).length,
  1,
);

// A requester's own outgoing instruction is context for a daily recap, not a
// new action or reply that the requester owes themselves.
const requesterOwnSource = source({
  senderId: 'requester-1',
  content: 'Please organize and send the files today.',
});
const ownActionFailures = unreadSummaryTestHelpers.briefingFailures(
  'Files were discussed today.',
  [{
    type: 'mustKnow',
    title: '',
    items: [{
      label: 'Files',
      content: 'Organize and send the files today.',
      status: 'information',
      importance: 'critical',
      sourceMessageIds: ['message-1'],
      representativeMessageId: 'message-1',
      sourceSequences: [1],
    }],
  }],
  [requesterOwnSource],
  '',
  'requester-1',
);
assert.ok(ownActionFailures.includes('nonActionInActionSection'));
assert.equal(
  unreadSummaryTestHelpers.fallback(
    [requesterOwnSource],
    'en',
    'requester-1',
  ).sections.some((section) => section.type === 'mustKnow'),
  false,
);

const misclassifiedReplyFailures =
  unreadSummaryTestHelpers.briefingFailures(
    'Today includes file preparation.',
    [{
      type: 'responseRequired',
      title: '',
      items: [{
        label: 'Files',
        content: 'Organize and send the files today.',
        status: 'responseRequired',
        importance: 'critical',
        sourceMessageIds: ['message-1'],
        representativeMessageId: 'message-1',
        sourceSequences: [1],
      }],
    }],
    [source({content: 'Please organize and send the files today.'})],
  );
assert.ok(misclassifiedReplyFailures.includes('actionMisclassifiedAsReply'));

const repeatedOverviewFailures = unreadSummaryTestHelpers.briefingFailures(
  'The meeting is today at 2 PM.',
  [{
    type: 'scheduleAndPlace',
    title: '',
    items: [{
      label: 'Meeting',
      content: 'The meeting is today at 2 PM.',
      status: 'confirmed',
      importance: 'important',
      sourceMessageIds: ['message-1'],
      representativeMessageId: 'message-1',
      sourceSequences: [1],
    }],
  }],
  [source({content: 'The meeting is today at 2 PM.'})],
);
assert.ok(repeatedOverviewFailures.includes('overviewDuplicatesItem'));

const unsupportedConfirmationFailures =
  unreadSummaryTestHelpers.briefingFailures(
    'A meeting time was suggested.',
    [{
      type: 'scheduleAndPlace',
      title: '',
      items: [{
        label: 'Meeting',
        content: 'The suggested time is 7 PM.',
        status: 'confirmed',
        importance: 'important',
        sourceMessageIds: ['message-1'],
        representativeMessageId: 'message-1',
        sourceSequences: [1],
      }],
    }],
    [source({content: 'Could we meet at 7 PM?'})],
  );
assert.ok(
  unsupportedConfirmationFailures.includes('unsupportedConfirmedStatus'),
);

const koreanFallback = unreadSummaryTestHelpers.fallback([
  source({
    content: '오늘까지 파일을 PDF로 넘겨주세요.',
    directlyMentionsRequester: true,
  }),
  source({
    messageId: 'message-2',
    sequence: 2,
    content: '오늘 저녁에는 야근입니다.',
  }),
  source({
    messageId: 'message-3',
    sequence: 3,
    content: '저도 오늘 야근할 수 있어요.',
  }),
], 'ko');
const koreanText = koreanFallback.sections
  .flatMap((section) => section.items)
  .map((item) => item.content)
  .join(' ');
assert.match(koreanText, /오늘까지 파일을 PDF로 넘겨주세요/);
assert.doesNotMatch(koreanText, /원문|확인 가능한 값|관련 내용/);

const genericFailures = unreadSummaryTestHelpers.genericContentFailures(
  '새 메시지 4개에 1명이 참여했어요.',
  [{
    type: 'responseRequired',
    title: '',
    items: [{
      label: '확인 필요',
      content: '질문이나 요청이 포함된 메시지가 있어 원문 확인이 필요해요.',
      status: 'responseRequired',
      importance: 'critical',
      sourceMessageIds: ['message-1'],
      representativeMessageId: 'message-1',
      sourceSequences: [1],
    }],
  }],
);
assert.ok(genericFailures.includes('metaSummary'));
assert.ok(genericFailures.includes('genericContent'));
assert.ok(genericFailures.includes('missingActualFact'));

const emptySectionFailures = unreadSummaryTestHelpers.genericContentFailures(
  '파일을 오늘까지 보내 달라는 요청이 있었어요.',
  [{
    type: 'mustKnow',
    title: '',
    items: [{
      label: '해야 할 일',
      content: '해야 할 일이 있어요.',
      status: 'information',
      importance: 'important',
      sourceMessageIds: ['message-1'],
      representativeMessageId: 'message-1',
      sourceSequences: [1],
    }],
  }],
);
assert.ok(emptySectionFailures.includes('genericContent'));
assert.ok(emptySectionFailures.includes('missingActualFact'));

const actualFactFailures = unreadSummaryTestHelpers.genericContentFailures(
  '오늘 야근 일정과 파일 전달 마감에 대한 이야기가 있었어요.',
  [{
    type: 'mustKnow',
    title: '',
    items: [{
      label: '파일 전달',
      content: '파일을 오늘까지 전달해 달라는 요청이 있었어요.',
      status: 'information',
      importance: 'important',
      sourceMessageIds: ['message-1'],
      representativeMessageId: 'message-1',
      sourceSequences: [1],
    }],
  }],
);
assert.deepEqual(actualFactFailures, []);

assert.equal(
  unreadSummaryTestHelpers.usesTargetLanguage(
    '오늘 파일을 오후 6시까지 전달하기로 했어요.',
    'ko',
  ),
  true,
);
assert.equal(
  unreadSummaryTestHelpers.usesTargetLanguage(
    'The file must be delivered by 6 PM today.',
    'ko',
  ),
  false,
);
assert.equal(
  unreadSummaryTestHelpers.usesTargetLanguage(
    'The file must be delivered by 6 PM today.',
    'en',
  ),
  true,
);

const grounding = unreadSummaryTestHelpers.validationResult([
  'invalidEvidence',
]);
assert.equal(grounding.valid, false);
assert.equal(grounding.severity, 'fatal');
assert.deepEqual(grounding.categories, ['GROUNDING_ERROR']);

const empty = unreadSummaryTestHelpers.validationResult(['missingOverview']);
assert.equal(empty.valid, false);
assert.equal(empty.repairable, true);
assert.deepEqual(empty.categories, ['EMPTY_RESULT']);

const valid = unreadSummaryTestHelpers.validationResult([]);
assert.equal(valid.valid, true);
assert.equal(valid.severity, 'none');

const schema400 = unreadSummaryTestHelpers.providerFailure(
  new GeminiHttpError({
    httpStatus: 400,
    providerCode: 400,
    providerStatus: 'INVALID_ARGUMENT',
    providerMessage: 'Request schema is too complex.',
    requestStage: 'structured_output_request',
    model: 'canary-model',
  }),
);
assert.equal(schema400.code, 'provider_400');
assert.equal(schema400.category, 'request_schema');
assert.equal(schema400.retryable, false);
assert.equal(schema400.providerStatus, 'INVALID_ARGUMENT');
assert.equal(schema400.model, 'canary-model');

const quota429 = unreadSummaryTestHelpers.providerFailure(
  new GeminiHttpError({
    httpStatus: 429,
    providerCode: 429,
    providerStatus: 'RESOURCE_EXHAUSTED',
    requestStage: 'structured_output_request',
    model: 'canary-model',
  }),
);
assert.equal(quota429.category, 'rate_limit');
assert.equal(quota429.retryable, true);

const parseFailure = unreadSummaryTestHelpers.providerFailure(
  new GeminiStructuredResponseError(
    'Gemini returned invalid JSON.',
    'structured_output_parse',
    'canary-model',
  ),
);
assert.equal(parseFailure.category, 'parse_failure');
assert.equal(parseFailure.retryable, false);

const crossLanguageSources = [
  source({content: '오늘 오후 5시에 회의가 있습니다.'}),
  source({messageId: 'message-2', sequence: 2, content: '파일을 보내주세요.'}),
  source({messageId: 'message-3', sequence: 3, content: '참석 가능하세요?'}),
];
assert.equal(
  unreadSummaryTestHelpers.needsFallbackTranslation(
    crossLanguageSources,
    'en',
  ),
  true,
);
const translatedJapaneseFallback = unreadSummaryTestHelpers.fallback([
  source({content: '今日午後5時に会議があります。'}),
  source({messageId: 'message-2', sequence: 2, content: '資料を送ってください。'}),
  source({messageId: 'message-3', sequence: 3, content: '参加できますか？'}),
], 'ja', '', true);
assert.ok(translatedJapaneseFallback.overview);

console.log('Snack Chat unread summary helper tests passed.');
