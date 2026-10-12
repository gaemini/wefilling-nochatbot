#!/usr/bin/env node

const assert = require('assert');
const organization = require('../lib/organization_accounts');

function expectInvalidHandle(value) {
  assert.throws(
    () => organization.normalizeOrganizationHandle(value),
    (error) => error && error.code === 'invalid-argument',
  );
}

assert.strictEqual(
  organization.normalizeOrganizationHandle('  @Campus_Club  '),
  'campus_club',
);
assert.strictEqual(
  organization.normalizeOrganizationHandle('a1'),
  'a1',
);

for (const invalid of [
  'a',
  '1campus',
  'campus-club',
  'campus club',
  '단체',
  'admin',
  'wefilling',
  'a/b',
  'a'.repeat(31),
]) {
  expectInvalidHandle(invalid);
}

process.stdout.write('organization account policy tests passed\n');
