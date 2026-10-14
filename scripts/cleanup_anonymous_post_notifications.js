#!/usr/bin/env node

/*
 * 익명 글에 대해 이미 만들어진 '새 포스트' 알림(post_created)을 지운다.
 * 이 알림에는 작성자 이름·사진이 들어 있어 익명 작성자가 친구라는 것이 드러난다.
 *
 * Usage:
 *   node scripts/cleanup_anonymous_post_notifications.js          # dry-run
 *   node scripts/cleanup_anonymous_post_notifications.js --apply  # delete
 *
 * GOOGLE_APPLICATION_CREDENTIALS 또는 Firebase CLI의 ADC가 필요합니다.
 * 안 읽은 알림 수 카운터는 기존 삭제 트리거가 맞춘다(skip 표시 없이 삭제).
 */
const admin = require('firebase-admin');

if (admin.apps.length === 0) admin.initializeApp();
const db = admin.firestore();
const apply = process.argv.includes('--apply');

async function main() {
  const anonymousPosts = await db.collection('posts')
    .where('isAnonymous', '==', true)
    .select()
    .get();
  console.log(`익명 글 ${anonymousPosts.size}개`);

  let found = 0;
  let deleted = 0;
  for (const post of anonymousPosts.docs) {
    const notifications = await db.collection('notifications')
      .where('postId', '==', post.id)
      .where('type', '==', 'post_created')
      .get();
    if (notifications.empty) continue;
    found += notifications.size;
    console.log(`- ${post.id}: 알림 ${notifications.size}개`);
    if (!apply) continue;
    for (let i = 0; i < notifications.docs.length; i += 400) {
      const batch = db.batch();
      notifications.docs.slice(i, i + 400).forEach((doc) => batch.delete(doc.ref));
      await batch.commit();
      deleted += Math.min(400, notifications.docs.length - i);
    }
  }
  console.log(apply
    ? `삭제 ${deleted}개`
    : `삭제 대상 ${found}개 (dry-run, --apply로 실제 삭제)`);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
