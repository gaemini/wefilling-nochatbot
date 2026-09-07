'use strict';

// Load the actual compiled pipeline with only Firestore/provider I/O replaced.
// No production exports, credentials, Firestore writes, or Gemini calls.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {createRequire} = require('node:module');
const filename = path.resolve(__dirname, '../lib/content_translation.js');
const requireFromPipeline = createRequire(filename);
const reads = [];
const records = new Map();
const readFailures = new Set();
const firebaseAdmin = requireFromPipeline('firebase-admin');
const fakeFirestore = () => ({
  doc(documentPath) {
    return {
      async get() {
        reads.push(documentPath);
        if (readFailures.has(documentPath)) throw new Error('offline');
        const data = records.get(documentPath);
        return {
          id: documentPath.split('/').pop(),
          exists: data !== undefined,
          data: () => data,
        };
      },
    };
  },
});
fakeFirestore.Timestamp = firebaseAdmin.firestore.Timestamp;
const sandbox = {
  exports: {},
  require: (id) => id === 'firebase-admin' ?
    {firestore: fakeFirestore} : requireFromPipeline(id),
  console: {warn() {}, info() {}, log() {}},
  process,
  Buffer,
  Error,
  SyntaxError,
  setTimeout,
  clearTimeout,
};
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(filename, 'utf8') + `
exports.test = {
  resolveContent, buildTranslationContext, callGemini,
  setProvider(provider) { callGeminiModel = provider; },
};`, sandbox, {filename});
const helpers = sandbox.exports.test;
const cache = () => ({
  snackRooms: new Map(), dmConversations: new Map(), documents: new Map(),
});
const tick = () => new Promise((resolve) => setImmediate(resolve));
const item = (id, content) => ({
  contentType: 'comment', contentId: id, parentId: 'post-1',
  fields: {content}, context: {}, contextHash: '', contextSeed: {},
  typoHints: [], matchedGlossary: [], preserveIfUncertain: [], sourceHash: id,
});
const result = (source, content, overrides = {}) => ({
  id: `comment:post-1:${source.contentId}`,
  translations: {content}, sourceLanguage: 'ko', sourceIntent: 'statement',
  coverageComplete: true, uncertainTerms: [], modelUsed: 'gemini-3.5-flash-lite',
  ...overrides,
});

async function run() {
  records.set('posts/post-1', {visibility: 'public', content: 'A public post'});
  const requests = Array.from({length: 5}, (_, index) => {
    const contentId = `comment-${index}`;
    records.set(`comments/${contentId}`, {
      postId: 'post-1', content: '댓글 본문', parentCommentId: 'parent-1',
    });
    return {contentType: 'comment', parentId: 'post-1', contentId};
  });
  records.set('comments/parent-1', {postId: 'post-1', content: '부모 댓글'});
  const invocation = cache();
  const resolved = await Promise.all(requests.map((request) =>
    helpers.resolveContent('reader', request, invocation),
  ));
  assert.equal(reads.length, 7, '5 sources + 1 post + 1 meetup, not 15 reads');
  await Promise.all(resolved.map((source) =>
    helpers.buildTranslationContext(source, invocation),
  ));
  assert.equal(reads.length, 8, 'five replies share one thread-parent read');
  assert.ok(resolved.every((source) => source.context.threadParentComment));

  // A fresh invocation re-reads the parent and enforces changed permissions.
  records.set('posts/post-1', {visibility: 'friends', allowedUserIds: []});
  await assert.rejects(helpers.resolveContent('reader', requests[0], cache()),
    (error) => error.code === 'permission-denied');
  records.set('posts/post-1', {visibility: 'public'});
  records.delete('comments/parent-1');
  const orphanContext = await helpers.resolveContent('reader', requests[0], cache());
  await helpers.buildTranslationContext(orphanContext, cache());
  assert.equal(orphanContext.fields.content, '댓글 본문');

  readFailures.add('comments/parent-1');
  const contextError = await helpers.resolveContent('reader', requests[0], cache());
  await helpers.buildTranslationContext(contextError, cache());
  assert.equal(contextError.context.threadParentComment, undefined);
  assert.equal(contextError.fields.content, '댓글 본문');
  readFailures.clear();

  records.set('comments/deleted', {postId: 'post-1', isDeleted: true});
  const accessResults = await Promise.allSettled([
    helpers.resolveContent('reader', {contentType: 'comment', contentId: 'deleted'}, cache()),
    helpers.resolveContent('reader', requests[0], cache()),
  ]);
  assert.equal(accessResults[0].status, 'rejected');
  assert.equal(accessResults[0].reason.code, 'failed-precondition');
  assert.equal(accessResults[1].status, 'fulfilled');

  const sources = [item('good', '음악이 좋아요'), item('time', '오후 3시입니다'),
    item('strict', '반갑습니다')];
  let completeTemporal;
  let completeStrict;
  const calls = [];
  helpers.setProvider(async (batch, _target, _model, strict, temporal) => {
    calls.push({ids: batch.map((source) => source.contentId), strict, temporal});
    if (!strict) return new Map([
      ['comment:post-1:good', result(sources[0], 'I like music')],
      ['comment:post-1:time', result(sources[1], 'It is 3 AM')],
    ]);
    if (temporal) return new Promise((resolve) => { completeTemporal = resolve; });
    return new Promise((resolve) => { completeStrict = resolve; });
  });
  const translating = helpers.callGemini(sources, 'en');
  await tick();
  assert.equal(typeof completeStrict, 'function', 'strict retry starts immediately');
  assert.equal(typeof completeTemporal, 'function', 'temporal repair starts alongside');
  assert.equal(calls.length, 3, 'same request count: initial + two repairs');
  completeStrict(new Map([
    ['comment:post-1:strict', result(sources[2], 'Nice to meet you')],
  ]));
  completeTemporal(new Map([
    ['comment:post-1:time', result(sources[1], 'It is 3 PM')],
  ]));
  const output = await translating;
  assert.equal(output.translations.size, 3);
  assert.equal(output.translations.get('comment:post-1:time').translations.content,
    'It is 3 PM');
  assert.ok(output.diagnostics.repairSucceeded.has('comment:post-1:time'));
  assert.ok(calls.slice(1).every((call) => !call.ids.includes('good')));

  const many = Array.from({length: 5}, (_, index) => item(`time-${index}`, '오후 3시입니다'));
  let active = 0;
  let peak = 0;
  helpers.setProvider(async (batch, _target, _model, strict) => {
    if (strict) {
      active++;
      peak = Math.max(peak, active);
      await tick();
      active--;
    }
    return new Map(batch.map((source) => [
      `comment:post-1:${source.contentId}`,
      result(source, strict ? 'It is 3 PM' : 'It is 3 AM'),
    ]));
  });
  assert.equal((await helpers.callGemini(many, 'en')).translations.size, 5);
  assert.equal(peak, 5, 'existing five-item repair concurrency is preserved');

  // One provider failure retains validated siblings and completes the call.
  helpers.setProvider(async (batch, _target, _model, strict) => {
    if (strict) throw new Error('Gemini HTTP 429');
    return new Map([['comment:post-1:good', result(sources[0], 'I like music')]]);
  });
  const partial = await helpers.callGemini([sources[0], sources[2]], 'en');
  assert.equal(partial.translations.size, 1);
  assert.ok(partial.providerUnavailable);

  // Never trade temporal accuracy for latency, even after all repairs fail.
  let invalidCalls = 0;
  helpers.setProvider(async (batch) => {
    invalidCalls++;
    return new Map(batch.map((source) => [
      `comment:post-1:${source.contentId}`, result(source, 'It is 3 AM'),
    ]));
  });
  const rejected = await helpers.callGemini([sources[1]], 'en');
  assert.equal(rejected.translations.size, 0);
  assert.equal(invalidCalls, 3, 'initial, isolated temporal repair, existing fallback');
  assert.ok(rejected.diagnostics.failureCodes.has('comment:post-1:time'));
  console.log('Translation latency regression tests passed: shared reads 20 -> 8; '
    + 'independent repairs overlap; max concurrency 5; quality/permissions preserved.');
}

run().catch((error) => { console.error(error); process.exitCode = 1; });
