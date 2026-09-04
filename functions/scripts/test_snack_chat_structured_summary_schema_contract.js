'use strict';

const assert = require('node:assert/strict');
const {unreadSummaryTestHelpers: helpers} = require('../lib/snack_chat');

const source = (overrides) => ({
  senderId: 'sender-1',
  sender: 'Watson',
  sentAt: '2026-09-05T01:00:00.000Z',
  type: 'text',
  replyToMessageId: '',
  replyTargetSenderId: '',
  directlyMentionsRequester: false,
  repliesToRequester: false,
  ...overrides,
});

const sources = [
  source({
    messageId: 'schedule-1',
    sequence: 1,
    content: '오늘 오후 5시에 학생회관에서 킥오프 회의를 합니다.',
  }),
  source({
    messageId: 'action-2',
    sequence: 2,
    content: '발표 자료를 오늘까지 보내주세요.',
    directlyMentionsRequester: true,
  }),
  source({
    messageId: 'question-3',
    sequence: 3,
    content: '금요일 모임에 참석할 수 있나요?',
    directlyMentionsRequester: true,
  }),
];

const schema = helpers.responseSchema(sources);
const metadata = helpers.schemaMetadata();

// This fingerprint is the accepted production baseline. A deliberate schema
// change must update the schema version, this fingerprint, and the opt-in
// Gemini canary together rather than reaching users first.
assert.equal(metadata.schemaVersion, 3);
assert.equal(metadata.summaryVersion, 9);
assert.equal(metadata.promptVersion, 7);
assert.equal(metadata.fingerprint, '157c917ad2ef84e4');
assert.equal(schema.type, 'object');
assert.deepEqual(schema.required, [
  'schemaVersion',
  'overview',
  'sections',
  'otherConversationSummary',
]);

// Guard the request's overall compilation complexity, not only one keyword.
assert.ok(metadata.maximumDepth <= 10);
assert.ok(metadata.maximumArrayDepth <= 3);
assert.ok(metadata.propertyCount <= 13);
assert.ok(metadata.enumValueCount <= 18);
assert.equal(metadata.combinatorCount, 0);
assert.ok(metadata.nestedArrayConstraintCount <= 3);
assert.doesNotMatch(JSON.stringify(schema), /"maxItems"/);

const canonicalCandidate = {
  schemaVersion: 3,
  overview:
    'The discussion covers a kickoff plan, presentation preparation, and attendance.',
  sections: [
    {
      type: 'mustKnow',
      items: [{
        title: 'Presentation',
        description: 'Send the presentation materials by today.',
        status: 'information',
        importance: 'critical',
        sourceMessageIds: ['action-2'],
        representativeMessageId: 'action-2',
        sourceSequences: [2],
      }],
    },
    {
      type: 'responseRequired',
      items: [{
        title: 'Friday meetup',
        description: 'Let the group know whether you can attend on Friday.',
        status: 'responseRequired',
        importance: 'critical',
        sourceMessageIds: ['question-3'],
        representativeMessageId: 'question-3',
        sourceSequences: [3],
      }],
    },
    {
      type: 'scheduleAndPlace',
      items: [{
        title: 'Kickoff meeting',
        description: 'The kickoff is at 5 PM today in the Student Center.',
        status: 'confirmed',
        importance: 'important',
        sourceMessageIds: ['schedule-1'],
        representativeMessageId: 'schedule-1',
        sourceSequences: [1],
      }],
    },
  ],
  otherConversationSummary: '',
};
const evaluation = helpers.evaluateCandidate(
  canonicalCandidate,
  sources,
  'en',
  'requester-1',
);
assert.equal(evaluation.validation.valid, true);
assert.deepEqual(evaluation.validation.failureCodes, []);

// The API schema stays deliberately simple; product limits remain enforced by
// the server validator after normalization.
const tooManyItemsCandidate = structuredClone(canonicalCandidate);
tooManyItemsCandidate.sections[0].items = Array.from(
  {length: 4},
  (_, index) => ({
    ...canonicalCandidate.sections[0].items[0],
    title: `Presentation ${index + 1}`,
    description: `Send presentation material ${index + 1} by today.`,
  }),
);
const boundedEvaluation = helpers.evaluateCandidate(
  tooManyItemsCandidate,
  sources,
  'en',
  'requester-1',
);
assert.equal(boundedEvaluation.validation.valid, false);
assert.ok(
  boundedEvaluation.validation.failureCodes.includes('tooManySectionItems'),
);

console.log(
  'Structured summary production schema contract passed ' +
  `(v${metadata.schemaVersion}, ${metadata.fingerprint}).`,
);
