#!/usr/bin/env node

/*
 * Reconciles meetup_reviews with users/{uid}/posts/{reviewId}.
 * Existing visibility, likes, and comment counts are preserved.
 *
 * Dry run (default): npm run migrate:review-projections
 * Apply: npm run migrate:review-projections -- --apply
 */
const admin = require('firebase-admin');

admin.initializeApp();
const db = admin.firestore();
const apply = process.argv.includes('--apply');
const projectionVersion = 1;

function uid(value) {
  return String(value || '').trim();
}

function canRetainProfile(data) {
  if (!data) return false;
  const status = String(data.status || data.accountStatus || '')
    .trim().toLowerCase();
  const registrationStatus = String(data.registrationStatus || '')
    .trim().toLowerCase();
  return data.isDeleted !== true &&
    data.deleted !== true &&
    data.deleting !== true &&
    data.deletedAt == null &&
    status !== 'deleted' &&
    registrationStatus !== 'deleted' &&
    registrationStatus !== 'deleting';
}

function owners(review) {
  const values = [
    uid(review.authorId),
    ...(Array.isArray(review.approvedParticipants)
      ? review.approvedParticipants.map(uid)
      : []),
  ];
  return [...new Set(values.filter(Boolean))];
}

function projectionData(reviewId, review, ownerId, profile, existing) {
  const listedImages = Array.isArray(review.imageUrls)
    ? review.imageUrls.map(uid).filter(Boolean)
    : [];
  const legacyImage = uid(review.imageUrl);
  const imageUrls = listedImages.length > 0
    ? listedImages
    : (legacyImage ? [legacyImage] : []);
  const profileName = uid(profile.nickname || profile.displayName) || '익명';
  const result = {
    type: 'meetup_review',
    authorId: ownerId,
    authorName: profileName,
    authorProfileImage: uid(profile.photoURL),
    profileOwnerId: ownerId,
    meetupId: uid(review.meetupId),
    meetupTitle: uid(review.meetupTitle),
    imageUrls,
    imageUrl: legacyImage || imageUrls[0] || '',
    content: String(review.content || ''),
    category: String(review.category || '모임'),
    participationRole: ownerId === uid(review.authorId)
      ? 'host'
      : 'participant',
    reviewId,
    sourceReviewId: reviewId,
    createdAt: review.createdAt || admin.firestore.FieldValue.serverTimestamp(),
    visibility: 'public',
    reviewProjectionVersion: projectionVersion,
    projectionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };
  if (review.updatedAt) result.updatedAt = review.updatedAt;
  if (typeof existing.isHidden !== 'boolean') result.isHidden = false;
  if (!Array.isArray(existing.likedBy)) result.likedBy = [];
  if (typeof existing.likeCount !== 'number') result.likeCount = 0;
  if (typeof existing.commentCount !== 'number') result.commentCount = 0;
  return result;
}

function isCurrent(post, reviewId, ownerId) {
  return post.type === 'meetup_review' &&
    post.authorId === ownerId &&
    post.profileOwnerId === ownerId &&
    post.reviewId === reviewId &&
    post.sourceReviewId === reviewId &&
    post.reviewProjectionVersion === projectionVersion;
}

async function main() {
  const [reviewSnapshot, userSnapshot] = await Promise.all([
    db.collection('meetup_reviews').get(),
    db.collection('users').get(),
  ]);
  const users = new Map(userSnapshot.docs.map((doc) => [doc.id, doc.data()]));
  const expected = [];
  let ineligibleOwners = 0;
  for (const reviewDoc of reviewSnapshot.docs) {
    for (const ownerId of owners(reviewDoc.data())) {
      const profile = users.get(ownerId);
      if (!canRetainProfile(profile)) {
        ineligibleOwners++;
        continue;
      }
      expected.push({
        reviewDoc,
        ownerId,
        profile,
        ref: db.collection('users').doc(ownerId)
          .collection('posts').doc(reviewDoc.id),
      });
    }
  }

  const postDocs = expected.length > 0
    ? await db.getAll(...expected.map((entry) => entry.ref))
    : [];
  const repairs = [];
  let missing = 0;
  postDocs.forEach((postDoc, index) => {
    const entry = expected[index];
    const existing = postDoc.exists ? postDoc.data() || {} : {};
    if (!postDoc.exists) missing++;
    if (postDoc.exists && isCurrent(existing, entry.reviewDoc.id, entry.ownerId)) {
      return;
    }
    repairs.push({entry, existing});
  });

  if (apply) {
    for (let offset = 0; offset < repairs.length; offset += 400) {
      const batch = db.batch();
      repairs.slice(offset, offset + 400).forEach(({entry, existing}) => {
        batch.set(
          entry.ref,
          projectionData(
            entry.reviewDoc.id,
            entry.reviewDoc.data(),
            entry.ownerId,
            entry.profile,
            existing,
          ),
          {merge: true},
        );
      });
      await batch.commit();
    }
  }

  process.stdout.write(`${JSON.stringify({
    mode: apply ? 'apply' : 'dry-run',
    scannedReviews: reviewSnapshot.size,
    expectedProfileDocuments: expected.length,
    missingProfileDocuments: missing,
    outdatedProfileDocuments: repairs.length - missing,
    repairedProfileDocuments: apply ? repairs.length : 0,
    skippedIneligibleOwners: ineligibleOwners,
  }, null, 2)}\n`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
