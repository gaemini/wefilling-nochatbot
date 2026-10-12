import type * as admin from 'firebase-admin';

// Presentation only: no Firestore, counters, token selection or retry policy.
// Opt in only after the device/state matrix in docs/chat_push_presentation.md.
export const chatPushPresentationEnabled = (): boolean =>
  process.env.CHAT_PUSH_PRESENTATION_V2 === 'true';

export function pushText(value: unknown, maxBytes = 280): string {
  const text = typeof value === 'string' ? value.trim() : '';
  let result = '';
  // Node 20 supports grapheme segmentation (including ZWJ emoji). Retain a
  // surrogate-safe fallback for older test runtimes without Intl.Segmenter.
  const Segmenter = (Intl as unknown as {Segmenter?: new (
    locale?: string, options?: {granularity: string}
  ) => {segment(text: string): Iterable<{segment: string}>}}).Segmenter;
  const parts = Segmenter
    ? Array.from(new Segmenter(undefined, {granularity: 'grapheme'}).segment(text), part => part.segment)
    : Array.from(text);
  for (const point of parts) {
    if (Buffer.byteLength(result + point, 'utf8') > maxBytes) break;
    result += point;
  }
  return result;
}

export function chatPushCopy(args: {
  kind: 'snack' | 'dm'; title: string; sender: string;
  message: Record<string, unknown>; language?: unknown; unreadCount?: number | null;
}): {title: string; body: string; preview: string; subtitle?: string; language: string} {
  const language = String(args.language ?? 'ko').toLowerCase();
  const ko = language.startsWith('ko');
  const zh = language.startsWith('zh');
  const message = args.message;
  const raw = pushText(message.text);
  const type = typeof message.type === 'string' ? message.type : '';
  let preview = raw;
  if (type === 'image' || message.imageUrl) preview = '📷 ' + (raw || (ko ? '사진' : zh ? '照片' : 'Photo'));
  else if (type === 'file') preview = '📎 ' + (
    pushText(message.originalFileName, 160) ||
    pushText(message.fileName, 160) ||
    (ko ? '파일' : zh ? '文件' : 'File')
  );
  else if (type === 'poll') preview = '📊 ' + (raw || (ko ? '투표' : zh ? '投票' : 'Poll'));
  else if (!preview) preview = ko ? '메시지' : zh ? '消息' : 'Message';
  if (message.replyToMessageId) preview = '↪ ' + preview;
  const count = args.unreadCount;
  const subtitle = typeof count === 'number' && Number.isInteger(count) && count > 1
    ? ko ? `안 읽음 ${count}개` : zh ? `${count}条未读` : `${count} unread`
    : undefined;
  const sender = pushText(args.sender, 120);
  return {title: pushText(args.kind === 'dm' ? sender : args.title, 180),
    body: args.kind === 'snack' && sender ? `${sender}: ${preview}` : preview,
    preview, subtitle, language: ko ? 'ko' : zh ? 'zh' : 'en'};
}

/** Prepare everything before the ONE existing FCM send. If enrichment fails
 * or gets too large, return the exact legacy envelope; never retry delivery. */
export function decorateChatPush(
  legacy: admin.messaging.MulticastMessage,
  args: Parameters<typeof chatPushCopy>[0] & {
    threadKey: string; messageId: string; sentAtMillis: number;
  },
): admin.messaging.MulticastMessage {
  if (!chatPushPresentationEnabled()) return legacy;
  try {
    const display = chatPushCopy(args);
    if (!display.title || !Number.isSafeInteger(args.sentAtMillis) || args.sentAtMillis <= 0) return legacy;
    const candidate: admin.messaging.MulticastMessage = {
      ...legacy,
      notification: {...legacy.notification, title: display.title, body: display.body},
      data: {...legacy.data,
        chatPresentationVersion: '2', displayMessagePreview: display.preview,
        messageType: pushText(args.message.type, 30) || 'text',
        // Existing fields win, retaining their meaning for older clients.
        messageId: legacy.data?.messageId ?? args.messageId,
        notificationEventId: legacy.data?.notificationEventId ?? args.messageId,
        sentAtMillis: legacy.data?.sentAtMillis ?? String(args.sentAtMillis),
        language: legacy.data?.language ?? display.language,
        ...(args.unreadCount != null && Number.isInteger(args.unreadCount) && args.unreadCount >= 0
          ? {roomUnreadCount: legacy.data?.roomUnreadCount ?? String(args.unreadCount)} : {}),
        ...(display.subtitle ? {displayUnreadLabel: display.subtitle} : {}),
      },
      apns: {...legacy.apns, payload: {...legacy.apns?.payload, aps: {
        ...legacy.apns?.payload?.aps, threadId: args.threadKey,
        alert: {title: display.title, body: display.body,
          ...(display.subtitle ? {subtitle: display.subtitle} : {})},
      }}},
    };
    // Conservative budget including both platform overrides. Do not let
    // optional duplicated text cause FCM's 4096-byte limit to drop a push.
    if (Buffer.byteLength(JSON.stringify({...candidate, tokens: undefined}), 'utf8') > 3500) return legacy;
    return candidate;
  } catch (_) {
    // Content/metadata preparation is never allowed to fail the send path.
    return legacy;
  }
}
