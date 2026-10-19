// posts/{id}.latestComment: 피드 카드가 댓글을 따로 읽지 않고 '최근 댓글 한 줄'을 그리도록
// 댓글 트리거가 비정규화해 둔다. 최상위·삭제되지 않은 댓글만 쓴다(대댓글은 갱신하지 않음).
import * as admin from 'firebase-admin';
import {FieldValue, Timestamp} from 'firebase-admin/firestore';

export const LATEST_COMMENT_TEXT_MAX = 120;
/** 최신 댓글이 지워졌을 때 다음 댓글을 고르려고 읽는 최대 개수. */
export const LATEST_COMMENT_SCAN_LIMIT = 200;

type CommentData = admin.firestore.DocumentData;

function millisOf(value: unknown): number {
  const candidate = value as {toMillis?: () => number} | null | undefined;
  return typeof candidate?.toMillis === 'function' ? candidate.toMillis() : 0;
}

/** 최상위이고 삭제되지 않은 댓글인가. */
export function isVisibleTopLevelComment(data: CommentData | undefined): boolean {
  if (!data) return false;
  const parent = typeof data.parentCommentId === 'string' ? data.parentCommentId.trim() : '';
  return parent.length === 0 && data.isDeleted !== true;
}

/** 댓글 문서 → latestComment 값. 익명이면 이름·사진을 저장하지 않는다. */
export function latestCommentFields(commentId: string, data: CommentData): Record<string, unknown> {
  const anonymous = data.isAnonymous === true;
  const text = Array.from(String(data.content ?? '').replace(/\s+/g, ' ').trim())
    .slice(0, LATEST_COMMENT_TEXT_MAX).join('');
  const images = Array.isArray(data.imagePaths) ? data.imagePaths.length : 0;
  const hasMedia = images > 0 || String(data.gifStoragePath ?? '').trim().length > 0;
  return {
    commentId,
    authorId: String(data.userId ?? ''),
    ...(anonymous ? {} : {
      authorName: String(data.authorNickname ?? '').trim(),
      authorPhotoUrl: String(data.authorPhotoUrl ?? '').trim(),
    }),
    isAnonymous: anonymous,
    text,
    hasMedia,
    createdAt: data.createdAt ?? FieldValue.serverTimestamp(),
  };
}

/** 새 댓글이 지금의 latestComment보다 늦을 때만 바꾼다(트리거 순서가 뒤바뀌어도 안전). */
export function isNewerThanLatest(current: unknown, candidate: CommentData): boolean {
  if (!current || typeof current !== 'object') return true;
  const currentMillis = millisOf((current as Record<string, unknown>).createdAt);
  const candidateMillis = millisOf(candidate.createdAt);
  return candidateMillis === 0 || candidateMillis >= currentMillis;
}

/** 지운 댓글을 뺀 나머지 중 가장 최근의 보이는 최상위 댓글. 없으면 null. */
export function pickLatestComment(
  docs: ReadonlyArray<{id: string; data: CommentData}>,
  excludeId: string,
): {id: string; data: CommentData} | null {
  let best: {id: string; data: CommentData} | null = null;
  for (const doc of docs) {
    if (doc.id === excludeId || !isVisibleTopLevelComment(doc.data)) continue;
    if (!best || millisOf(doc.data.createdAt) > millisOf(best.data.createdAt)) best = doc;
  }
  return best;
}

/**
 * [deletedCommentId]가 그 글의 latestComment면 다음 댓글로 다시 계산한다(없으면 필드 삭제).
 * 다른 댓글이 latestComment면 아무것도 읽거나 쓰지 않는다.
 */
export async function recomputeLatestCommentIfNeeded(
  postId: string,
  deletedCommentId: string,
): Promise<void> {
  const db = admin.firestore();
  const postRef = db.collection('posts').doc(postId);
  await db.runTransaction(async (tx) => {
    const post = await tx.get(postRef);
    const current = post.exists ? post.get('latestComment') : undefined;
    if (!current || current.commentId !== deletedCommentId) return;
    const snap = await tx.get(db.collection('comments')
      .where('postId', '==', postId)
      .limit(LATEST_COMMENT_SCAN_LIMIT));
    const next = pickLatestComment(
      snap.docs.map((doc) => ({id: doc.id, data: doc.data()})),
      deletedCommentId,
    );
    tx.update(postRef, {
      latestComment: next ? latestCommentFields(next.id, next.data) : FieldValue.delete(),
    });
  });
}

/**
 * 이전 스크립트: [sinceMillis] 이후 포스트 중 latestComment가 없거나 다른 글의 값을 다시 계산한다.
 * 포스트마다 댓글을 최대 LATEST_COMMENT_SCAN_LIMIT개 읽는다. apply가 false면 세기만 한다.
 */
export async function backfillLatestComments(
  sinceMillis: number,
  apply: boolean,
): Promise<{posts: number; updated: number; cleared: number}> {
  const db = admin.firestore();
  const posts = await db.collection('posts')
    .where('createdAt', '>=', Timestamp.fromMillis(sinceMillis))
    .get();
  let updated = 0;
  let cleared = 0;
  for (const post of posts.docs) {
    const comments = await db.collection('comments')
      .where('postId', '==', post.id)
      .limit(LATEST_COMMENT_SCAN_LIMIT)
      .get();
    const next = pickLatestComment(comments.docs.map((doc) => ({id: doc.id, data: doc.data()})), '');
    const current = post.get('latestComment');
    if (next && current?.commentId !== next.id) {
      updated++;
      if (apply) await post.ref.update({latestComment: latestCommentFields(next.id, next.data)});
    } else if (!next && current) {
      cleared++;
      if (apply) await post.ref.update({latestComment: FieldValue.delete()});
    }
  }
  return {posts: posts.size, updated, cleared};
}
