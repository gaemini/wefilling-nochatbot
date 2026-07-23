'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {isMissingCategoryKey} = require('./migrate_post_category');

test('selects only documents where categoryKey is absent', () => {
  assert.equal(isMissingCategoryKey({title: 'legacy'}), true);
  assert.equal(isMissingCategoryKey({categoryKey: 'style'}), false);
  assert.equal(isMissingCategoryKey({categoryKey: 'other'}), false);
  assert.equal(isMissingCategoryKey({categoryKey: null}), false);
});

test('a migrated document is not selected again', () => {
  const data = {title: 'legacy'};
  assert.equal(isMissingCategoryKey(data), true);

  data.categoryKey = 'other';
  assert.equal(isMissingCategoryKey(data), false);
});
