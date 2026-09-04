#!/usr/bin/env node

const assert = require('assert');
const {
  explicitSignupLanguage,
  resolvePendingSignupLanguage,
  resolvePendingSignupLanguageRequest,
} = require('../lib/registration_progress');

assert.strictEqual(explicitSignupLanguage(undefined), null);
assert.strictEqual(explicitSignupLanguage(''), null);
assert.strictEqual(explicitSignupLanguage('ko-KR'), 'ko');
assert.strictEqual(explicitSignupLanguage('en-US'), 'en');

// A signup screen can correct the default stored by an earlier social-login
// probe, regardless of whether that credential came from Google or Apple.
assert.strictEqual(resolvePendingSignupLanguage('ko', 'en'), 'ko');
assert.strictEqual(resolvePendingSignupLanguage('en', 'ko'), 'en');

// Startup/login recovery omits a language and must preserve the pending
// signup's locale instead of silently resetting it.
assert.strictEqual(resolvePendingSignupLanguage(null, 'ko'), 'ko');
assert.strictEqual(resolvePendingSignupLanguage(null, 'en'), 'en');
assert.strictEqual(resolvePendingSignupLanguage(null, null), 'en');

// Rolling deploy compatibility: an old app's startup default must not replace
// an existing pending locale, while a new app marks a real screen choice.
assert.strictEqual(resolvePendingSignupLanguageRequest({
  rawRequested: 'en',
  existing: 'ko',
  userDocumentExists: true,
  explicitlySelected: false,
}), 'ko');
assert.strictEqual(resolvePendingSignupLanguageRequest({
  rawRequested: 'ko',
  existing: 'en',
  userDocumentExists: true,
  explicitlySelected: true,
}), 'ko');
// Older email-signup builds can still set the locale when creating the first
// progress document because there is no stored value to preserve.
assert.strictEqual(resolvePendingSignupLanguageRequest({
  rawRequested: 'ko',
  existing: null,
  userDocumentExists: false,
  explicitlySelected: false,
}), 'ko');

process.stdout.write('auth registration helper assertions passed\n');
