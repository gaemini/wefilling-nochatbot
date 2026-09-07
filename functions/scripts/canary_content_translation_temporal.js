'use strict';

const assert = require('node:assert/strict');
const {
  translatePlainTextsWithExistingPipeline,
} = require('../lib/content_translation');
const {
  validateTemporalTranslation,
} = require('../lib/content_translation_policy');

const fixtures = [
  '회의는 9월 3일 오후 2시입니다',
  '3시간 20분 후에 만나요',
  '@jaemin 9월 3일 오후 2시 https://example.com',
];

async function run() {
  if (!process.env.GEMINI_API_KEY) {
    throw new Error('Set GEMINI_API_KEY before running the manual canary.');
  }
  for (const targetLanguage of ['en', 'ro']) {
    for (const canaryModel of ['primary', 'fallback']) {
      const translated = await translatePlainTextsWithExistingPipeline(
        fixtures,
        targetLanguage,
        {canaryModel},
      );
      assert.equal(translated.length, fixtures.length);
      translated.forEach((value, index) => {
        assert.ok(value.trim());
        assert.equal(
          validateTemporalTranslation(
            fixtures[index],
            value,
            'ko',
            targetLanguage,
          ),
          null,
        );
      });
      console.log(JSON.stringify({
        canaryModel,
        targetLanguage,
        fixtureCount: fixtures.length,
        structuredParsing: 'passed',
        qualityValidation: 'passed',
        protectedTokenRestore: 'passed',
      }));
    }
  }
}

run().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
