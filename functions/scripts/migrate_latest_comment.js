'use strict';

/*
 * 최근 30일 포스트의 latestComment(카드의 최근 댓글 한 줄)를 한 번 채운다.
 * dry run: node scripts/migrate_latest_comment.js
 * 적용:    node scripts/migrate_latest_comment.js --apply
 * (npm run build 뒤, GOOGLE_CLOUD_PROJECT/GCLOUD_PROJECT 지정)
 */
const admin = require('firebase-admin');
const {backfillLatestComments} = require('../lib/latest_comment');

const apply = process.argv.includes('--apply');
const days = Number((process.argv.find((a) => a.startsWith('--days=')) || '--days=30').slice(7));

async function main() {
  if (!admin.apps.length) admin.initializeApp();
  const since = Date.now() - days * 24 * 60 * 60 * 1000;
  const result = await backfillLatestComments(since, apply);
  console.log(JSON.stringify({mode: apply ? 'apply' : 'dry-run', days, ...result}, null, 2));
}

main().then(() => process.exit(0), (error) => {
  console.error(error);
  process.exit(1);
});
