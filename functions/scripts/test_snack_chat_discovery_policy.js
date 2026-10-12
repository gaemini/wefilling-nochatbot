'use strict';
const assert = require('node:assert/strict');
const {normalizeSnackSearch, validSnackMentions, isSummaryAnnouncement,
  selectedSummaryCategories, pollSummarySnapshot, hasGroundedRequesterRelation} = require('../lib/snack_chat_discovery_policy');
const {unreadSummaryTestHelpers: summary} = require('../lib/snack_chat');

assert.equal(normalizeSnackSearch('  HELLO\n  微邻  가  '), 'hello 微邻 가');
assert.deepEqual(selectedSummaryCategories(['tasks', 'invalid', 'schedule', 'tasks']), ['schedule', 'tasks']);
const text = '😀 @민수 please reply';
const mention = {userId: 'uid', displayName: '민수', start: 3, end: 6};
assert.deepEqual(validSnackMentions(text, [mention], ['uid']), [mention]);
assert.deepEqual(validSnackMentions(text, [{...mention, userId: 'outsider'}], ['uid']), []);
assert.deepEqual(validSnackMentions(text, [{...mention, start: 2}], ['uid']), []);
assert.deepEqual(validSnackMentions(text, [mention, mention], ['uid']), []);
assert.equal(isSummaryAnnouncement({type: 'system', metadata: {systemType: 'announcement'}}), true);
assert.equal(isSummaryAnnouncement({type: 'system', metadata: {systemType: 'joined'}}), false);
const poll = {type: 'poll', poll: {question: 'Where?', isAnonymous: true,
  options: [{id: 'a', text: 'Library'}, {id: 'b', text: 'Park'}], voteCounts: {a: 2, b: 1},
  votes: {privateUid: ['a']}, totalVoters: 3, closesAt: {toMillis: () => Date.now() + 100000}}};
// Stable deadline required for stable cache snapshot.
const deadline = Date.now() + 100000;
poll.poll.closesAt = {toMillis: () => deadline};
const first = pollSummarySnapshot(poll);
assert.equal(first, pollSummarySnapshot(poll));
assert.ok(!first.includes('privateUid'));
assert.equal(JSON.parse(first).status, 'open');
poll.poll.voteCounts.a = 3;
assert.notEqual(first, pollSummarySnapshot(poll));
poll.poll.closesAt = {toMillis: () => Date.now() - 1};
assert.equal(JSON.parse(pollSummarySnapshot(poll)).status, 'closed');
assert.equal(hasGroundedRequesterRelation({senderId: 'other', content: '민수 and I like coffee'}, 'uid', '민수'), false);
assert.equal(hasGroundedRequesterRelation({senderId: 'other', content: '@민수 안녕', legacyNameMention: true}, 'uid', '민수'), false);
assert.equal(hasGroundedRequesterRelation({senderId: 'other', content: '민수 제출 부탁해'}, 'uid', '민수'), true);
assert.equal(hasGroundedRequesterRelation({senderId: 'other', content: '민수 제출 부탁해'}, 'uid', '민수', false), false);
assert.equal(hasGroundedRequesterRelation({senderId: 'uid', content: '제가 맡을게요'}, 'uid', '민수'), true);
assert.equal(hasGroundedRequesterRelation({senderId: 'uid', content: '안녕하세요'}, 'uid', '민수'), false);
assert.equal(hasGroundedRequesterRelation({senderId: 'other', content: '', directlyMentionsRequester: true}, 'uid', '민수'), true);
const source = {messageId: 'old', sequence: 0, senderId: 'other', sender: 'Alice',
  sentAt: '', type: 'text', content: 'The reference PDF covers orientation preparations.',
  replyToMessageId: '', replyTargetSenderId: '', directlyMentionsRequester: false, repliesToRequester: false};
const candidate = {schemaVersion: 3, overview: '', otherConversationSummary: '', sections: [{type: 'sharedInformation', items: [{
  title: 'Orientation resource', description: 'Preparation guidance is available in the reference document.', status: 'information', importance: 'general',
  sourceMessageIds: ['old'], representativeMessageId: 'old', sourceSequences: []}]}]};
const legacy = summary.evaluateCandidate(candidate, [source], 'en', 'uid', true);
assert.equal(legacy.sections[0].items[0].representativeMessageId, 'old');
assert.deepEqual(legacy.sections[0].items[0].sourceSequences, []);
const empty = summary.evaluateCandidate({...candidate, sections: []}, [source], 'en', 'uid', true);
assert.equal(empty.validation.valid, true, JSON.stringify(empty.validation));
const unscoped = summary.evaluateCandidate({...candidate, sections: []}, [source], 'en', 'uid');
assert.equal(unscoped.validation.valid, false);
console.log('PASS: NFC/multilingual search, explicit UTF-16 mentions, grounded relevance, announcements, anonymous poll changes, legacy evidence, scoped empty results');
