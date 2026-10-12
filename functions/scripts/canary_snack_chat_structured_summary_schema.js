'use strict';

const assert = require('node:assert/strict');
const {unreadSummaryTestHelpers: helpers} = require('../lib/snack_chat');
const {structuredGeminiRuntimeInfo} = require('../lib/content_translation');

const apiKey = String(process.env.GEMINI_API_KEY || '').trim();
if (!apiKey) {
  throw new Error(
    'Set GEMINI_API_KEY only for this opt-in canary invocation. ' +
    'This script is intentionally not part of CI.',
  );
}

const source = (overrides) => ({
  senderId: 'canary-sender',
  sender: 'Canary teammate',
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
    content: '@Jaemin 발표 자료를 오늘까지 보내주세요.',
    directlyMentionsRequester: true,
  }),
  source({
    messageId: 'question-3',
    sequence: 3,
    content: '@Jaemin 금요일 모임에 참석할 수 있나요?',
    directlyMentionsRequester: true,
  }),
];

const schema = helpers.responseSchema(sources);
const metadata = helpers.schemaMetadata();
const runtime = structuredGeminiRuntimeInfo(false);
const prompt = [
  'This is a non-user canary for a production structured-output contract.',
  'Summarize the Korean source records in concise natural English.',
  'State actual grounded actions, questions, schedules, and places.',
  'Do not copy source sentences and do not add facts.',
  'Use only allowed schema values and cite exact messageId/sequence pairs.',
  'Use mustKnow for the file action, responseRequired for the attendance question, and scheduleAndPlace for the meeting.',
  'Keep overview brief and do not repeat the exact item details in it.',
  `SOURCE_RECORDS=${JSON.stringify(sources)}`,
].join('\n');

function safeProviderError(raw, httpStatus) {
  try {
    const parsed = JSON.parse(raw);
    return {
      httpStatus,
      providerCode: Number(parsed?.error?.code) || null,
      providerStatus: String(parsed?.error?.status || '')
        .replace(/[^A-Z0-9_]/gi, '')
        .slice(0, 80),
      providerMessage: String(parsed?.error?.message || '')
        .replace(/AIza[0-9A-Za-z_-]{20,}/g, '[REDACTED]')
        .replace(/[\r\n]+/g, ' ')
        .slice(0, 240),
    };
  } catch (_) {
    return {httpStatus, providerCode: null, providerStatus: '', providerMessage: ''};
  }
}

async function main() {
  const response = await fetch(
    `https://generativelanguage.googleapis.com/${runtime.apiVersion}/models/${runtime.model}:generateContent`,
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify({
        contents: [{role: 'user', parts: [{text: prompt}]}],
        generationConfig: {
          maxOutputTokens: 1800,
          thinkingConfig: {thinkingLevel: 'minimal'},
          responseMimeType: 'application/json',
          responseJsonSchema: schema,
        },
      }),
      signal: AbortSignal.timeout(20_000),
    },
  );
  const raw = await response.text();
  if (!response.ok) {
    throw new Error(
      `Gemini canary rejected the production schema: ${JSON.stringify(
        safeProviderError(raw, response.status),
      )}`,
    );
  }
  const envelope = JSON.parse(raw);
  const candidate = envelope?.candidates?.[0];
  assert.equal(candidate?.finishReason, 'STOP');
  const text = String(candidate?.content?.parts?.[0]?.text || '').trim();
  assert.ok(text);
  const structured = JSON.parse(text);
  for (const field of schema.required) {
    assert.ok(Object.hasOwn(structured, field), `Missing required field: ${field}`);
  }
  const evaluation = helpers.evaluateCandidate(
    structured,
    sources,
    'en',
    'canary-requester',
  );
  assert.equal(
    evaluation.validation.valid,
    true,
    `Canary validator failures: ${evaluation.validation.failureCodes.join(',')}`,
  );
  console.log(JSON.stringify({
    ok: true,
    model: runtime.model,
    finishReason: candidate.finishReason,
    schemaVersion: metadata.schemaVersion,
    schemaFingerprint: metadata.fingerprint,
  }));
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : 'Canary failed.');
  process.exitCode = 1;
});
