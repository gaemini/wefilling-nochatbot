// Pure policies shared by discovery and summary. No message/counter writes.
export function normalizeSnackSearch(value: unknown): string {
  return typeof value === 'string' ? value.normalize('NFC').toLowerCase().replace(/\s+/gu, ' ').trim() : '';
}

export function isSummaryAnnouncement(data: Record<string, any>): boolean {
  return data.type === 'system' && data.metadata?.systemType === 'announcement';
}

export const summaryCategories = ['highlights', 'schedule', 'tasks', 'decisions', 'questions', 'information', 'people', 'casual'];
export function selectedSummaryCategories(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return summaryCategories.filter(category => raw.includes(category));
}

export type SnackMention = {userId: string; displayName: string; start: number; end: number};
export function validSnackMentions(text: string, raw: unknown, participants: string[]): SnackMention[] {
  if (!Array.isArray(raw) || raw.length > 10) return [];
  const result: SnackMention[] = [];
  for (const value of raw) {
    if (!value || typeof value !== 'object') return [];
    const {userId, displayName, start, end} = value;
    if (typeof userId !== 'string' || !participants.includes(userId) ||
        typeof displayName !== 'string' || !displayName || displayName.length > 80 ||
        !Number.isInteger(start) || !Number.isInteger(end) || start < 0 || end <= start || end > text.length ||
        text.slice(start, end) !== '@' + displayName || result.some(item => start < item.end && end > item.start)) return [];
    result.push({userId, displayName, start, end});
  }
  return result;
}

// Frozen aggregate only, never ballots/user choices (including anonymous polls).
export function pollSummarySnapshot(data: Record<string, any>): string {
  if (data.type !== 'poll') return '';
  const poll = data.poll ?? {};
  const millis = (v: any) => typeof v?.toMillis === 'function' ? v.toMillis() : 0;
  const closesAt = millis(poll.closesAt);
  const closed = poll.isClosed === true || poll.status === 'closed' || millis(poll.closedAt) > 0 || (closesAt > 0 && closesAt <= Date.now());
  const counts = poll.voteCounts && typeof poll.voteCounts === 'object' ? poll.voteCounts : {};
  const options = Array.isArray(poll.options) ? poll.options.slice(0, 10).map((option: any) => ({
    text: typeof option.text === 'string' ? option.text.slice(0, 300) : '',
    votes: Number.isInteger(counts[option.id]) && counts[option.id] >= 0 ? counts[option.id] : null,
  })) : [];
  return JSON.stringify({status: closed ? 'closed' : 'open', closesAt: closesAt || null,
    totalVoters: Number.isInteger(poll.totalVoters) ? poll.totalVoters : null, options,
    // Stable across unchanged requests, so cache changes only with source state.
    stateUpdatedAt: millis(poll.updatedAt) || millis(data.updatedAt) || millis(poll.closedAt) || null,
    interpretation: 'Leading option is not a final agreement. Never infer individual votes.'});
}

export function hasGroundedRequesterRelation(source: Record<string, any>, uid: string, name: string, uniqueName = true): boolean {
  if (source.directlyMentionsRequester || source.repliesToRequester) return true;
  if (source.senderId === uid && /(?:할게|맡을게|참여할|갈게|제가\s*(?:할|맡)|내가\s*(?:할|맡)|\bI(?:'ll| will| can take| am responsible)|count me in|我来|我会|我参加|我负责)/iu.test(source.content)) return true;
  if (!uniqueName || !name) return false;
  const escaped = name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return new RegExp(escaped + '.{0,24}(?:부탁|해줘|해줄|담당|please|can you|could you|负责|请)', 'iu').test(source.content);
}
