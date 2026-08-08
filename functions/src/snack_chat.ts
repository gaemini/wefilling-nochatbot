import * as admin from 'firebase-admin';
import * as crypto from 'crypto';
import * as dns from 'dns';
import * as functions from 'firebase-functions';
import {FieldValue, Timestamp} from 'firebase-admin/firestore';
import * as http from 'http';
import * as https from 'https';
import * as net from 'net';
import {TextDecoder} from 'util';

const SNACK_CHATS = 'snack_chats';
const USERS = 'users';
const BLOCKS = 'blocks';
const FRIENDSHIPS = 'friendships';
const MEETUPS = 'meetups';
const REPORTS = 'reports';
const FUNCTION_EVENTS = '_snack_chat_function_events';
const LINK_PREVIEW_CACHE = '_snack_chat_link_preview_cache';

const ALLOWED_REACTIONS = new Set(['👍', '❤️', '😂', '😮', '😢', '🙏']);
const ALLOWED_REPORT_REASONS = new Set([
  '스팸/광고',
  '부적절한 콘텐츠',
  '괴롭힘/욕설',
  '허위 정보',
  '저작권 침해',
  '기타',
  'Spam/Ads',
  'Inappropriate content',
  'Harassment/Abuse',
  'False information',
  'Copyright infringement',
  'Other',
]);
const MAX_URL_LENGTH = 2048;
const MAX_LINK_URL_CANDIDATES = 12;
const LINK_URL_SELECTION_TIMEOUT_MS = 6000;
const MAX_HTML_BYTES = 1024 * 1024;
const DNS_TIMEOUT_MS = 2500;
const HTTP_TIMEOUT_MS = 5500;
const HTTP_TOTAL_TIMEOUT_MS = 9000;
const MAX_REDIRECTS = 4;
const LINK_CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const EVENT_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const CURRENT_LIST_POLICY_VERSION = 2;
const MAX_ROOM_PARTICIPANTS = 50;
const MAX_PUSH_TOKENS_PER_USER = 20;
const MAX_MEMBERSHIP_EVENT_WINDOW = 64;
const MAX_MEMBERSHIP_EVENT_READ = 129;
const SNACK_CHAT_FILE_MAX_BYTES = 20 * 1024 * 1024;
const SNACK_CHAT_FILE_JOB_TTL_MS = 2 * 24 * 60 * 60 * 1000;
const SNACK_CHAT_FILE_COMMITTED_JOB_TTL_MS = 60 * 60 * 1000;
const SNACK_CHAT_FILE_RETENTION_MS = 24 * 60 * 60 * 1000;
const SNACK_CHAT_FILE_MIME_BY_EXTENSION: Record<string, string> = {
  pdf: 'application/pdf',
  hwp: 'application/x-hwp',
  hwpx: 'application/vnd.hancom.hwpx',
  doc: 'application/msword',
  docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  ppt: 'application/vnd.ms-powerpoint',
  pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  xls: 'application/vnd.ms-excel',
  xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  txt: 'text/plain',
  csv: 'text/csv',
};

type Data = FirebaseFirestore.DocumentData;
type Period = {
  joinedAfterSequence: number;
  leftAfterSequence: number | null;
};
type MembershipEvent = {
  id: string;
  kind: 'join' | 'leave';
  boundary: number;
  occurredAtMs: number;
};
type LinkPreview = {
  url: string;
  domain: string;
  title: string;
  description: string;
  imageUrl?: string;
};

class LinkFetchError extends Error {}
class UnsafeUrlError extends Error {}

function db(): FirebaseFirestore.Firestore {
  return admin.firestore();
}

function stringValue(value: unknown): string {
  return (value ?? '').toString().trim();
}

function boundedString(value: unknown, max: number): string {
  return Array.from(stringValue(value)).slice(0, max).join('');
}

function objectValue(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
  return value as Record<string, unknown>;
}

function uniqueStrings(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return Array.from(new Set(value.map(stringValue).filter(Boolean)));
}

function nonNegativeInteger(value: unknown): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, Math.trunc(parsed));
}

function timestampMillis(value: unknown): number {
  if (value instanceof Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function nextRoomMessageTimestamp(
  room: FirebaseFirestore.DocumentSnapshot,
): Timestamp {
  const now = Timestamp.now();
  const previous = room.get('lastMessageTime');
  if (previous instanceof Timestamp) {
    const isAfterNow = previous.seconds > now.seconds ||
      (previous.seconds === now.seconds &&
        previous.nanoseconds > now.nanoseconds);
    return isAfterNow ? previous : now;
  }
  const previousMillis = timestampMillis(previous);
  return previousMillis > now.toMillis()
    ? Timestamp.fromMillis(previousMillis)
    : now;
}

function activeUserData(data: Data): boolean {
  return data.isDeleted !== true &&
    data.deleted !== true &&
    data.disabled !== true &&
    data.isSuspended !== true &&
    data.status !== 'deleted' &&
    data.status !== 'suspended';
}

function requireUid(context: functions.https.CallableContext): string {
  const uid = context.auth?.uid?.trim() ?? '';
  if (!uid) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Sign-in is required.',
    );
  }
  return uid;
}

async function requireActiveUser(uid: string): Promise<Data> {
  const user = await db().collection(USERS).doc(uid).get();
  const data = user.data() ?? {};
  if (!user.exists || !activeUserData(data)) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'An active account is required.',
    );
  }
  return data;
}

function firestoreId(value: unknown, field: string): string {
  const id = stringValue(value);
  if (!/^[A-Za-z0-9_-]{1,256}$/.test(id)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Invalid ' + field + '.',
    );
  }
  return id;
}

function firestoreIdList(
  value: unknown,
  field: string,
  maxItems: number,
): string[] {
  if (!Array.isArray(value) || value.length > maxItems) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Invalid ' + field + '.',
    );
  }
  const result: string[] = [];
  const seen = new Set<string>();
  for (const entry of value) {
    const id = firestoreId(entry, field);
    if (seen.has(id)) continue;
    seen.add(id);
    result.push(id);
  }
  return result;
}

function boundedStringList(
  value: unknown,
  field: string,
  maxItems: number,
  maxLength: number,
): string[] {
  if (!Array.isArray(value) || value.length > maxItems) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Invalid ' + field + '.',
    );
  }
  const result: string[] = [];
  const seen = new Set<string>();
  for (const entry of value) {
    if (typeof entry !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Invalid ' + field + '.',
      );
    }
    const normalized = entry.trim();
    if (!normalized || Array.from(normalized).length > maxLength) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Invalid ' + field + '.',
      );
    }
    if (seen.has(normalized)) continue;
    seen.add(normalized);
    result.push(normalized);
  }
  return result;
}

function friendshipId(userA: string, userB: string): string {
  return [userA, userB].sort().join('__');
}

function assertActiveUserSnapshot(
  snapshot: FirebaseFirestore.DocumentSnapshot,
): void {
  if (!snapshot.exists || !activeUserData(snapshot.data() ?? {})) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Every participant must have an active account.',
    );
  }
}

function assertFriendshipSnapshot(
  snapshot: FirebaseFirestore.DocumentSnapshot,
  ownerId: string,
  invitedId: string,
): void {
  if (!snapshot.exists) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only friends can be invited to a Snack Chat.',
    );
  }
  const members = uniqueStrings(snapshot.get('uids'));
  if (!members.includes(ownerId) ||
      !members.includes(invitedId)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only friends can be invited to a Snack Chat.',
    );
  }
}

function meetupAudienceAllows(data: Data, userId: string): boolean {
  const ownerId = stringValue(data.ownerId);
  const legacyOwnerId = stringValue(data.userId);
  const frozenAudience = uniqueStrings(data.audienceUserIdsFrozen);
  const frozenMode = stringValue(data.visibilityMode);
  const hasFrozenAudience = nonNegativeInteger(data.visibilitySchemaVersion) >= 2 &&
    ownerId.length > 0 &&
    ['public', 'friends', 'category'].includes(frozenMode) &&
    Array.isArray(data.audienceUserIdsFrozen) &&
    Array.isArray(data.sourceGroupIds) &&
    timestampMillis(data.visibilityLockedAt) > 0 &&
    frozenAudience.includes(ownerId);
  const frozenAllowed = hasFrozenAudience &&
    (userId === ownerId ||
      frozenMode === 'public' ||
      frozenAudience.includes(userId));
  // Once a frozen audience exists it is authoritative. Falling through to
  // legacy fields here could turn a stale legacy `visibility: public` value
  // into a bypass for a newer category/friends-only audience.
  if (hasFrozenAudience) return frozenAllowed;
  return userId === legacyOwnerId ||
    stringValue(data.visibility) === 'public' ||
    uniqueStrings(data.allowedUserIds).includes(userId);
}

// Keep this identical to the canonical Meetup join policy: endsAt is
// authoritative when present, legacy date falls back to the end of that day,
// and an unknown/malformed schedule fails closed.
function meetupHasEnded(data: Data, nowMillis = Date.now()): boolean {
  if (data.endsAt instanceof Timestamp) {
    return data.endsAt.toMillis() < nowMillis;
  }
  if (data.date instanceof Timestamp) {
    return data.date.toMillis() + 24 * 60 * 60 * 1000 < nowMillis;
  }
  return true;
}

function eventDocumentId(namespace: string, eventId: string): string {
  return crypto
    .createHash('sha256')
    .update(namespace + ':' + eventId)
    .digest('hex');
}

function eventExpiry(): Timestamp {
  return Timestamp.fromMillis(Date.now() + EVENT_TTL_MS);
}

function httpUrlCandidates(text: string): string[] {
  const pattern = /https?:\/\/[^\s<>()]+/gi;
  const candidates: string[] = [];
  const seen = new Set<string>();
  let match: RegExpExecArray | null;
  while (candidates.length < MAX_LINK_URL_CANDIDATES &&
      (match = pattern.exec(text)) != null) {
    const value = match[0].replace(/[.,!?;:]+$/, '');
    if (value && !seen.has(value)) {
      seen.add(value);
      candidates.push(value);
    }
  }
  return candidates;
}

function canonicalWebUrl(raw: string): URL {
  if (!raw || raw.length > MAX_URL_LENGTH) {
    throw new UnsafeUrlError('Invalid URL length.');
  }
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch (_) {
    throw new UnsafeUrlError('Invalid URL.');
  }
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') {
    throw new UnsafeUrlError('Only HTTP and HTTPS URLs are supported.');
  }
  if (parsed.username || parsed.password) {
    throw new UnsafeUrlError('URL credentials are not allowed.');
  }
  const hostname = parsed.hostname.toLowerCase().replace(/\.$/, '');
  if (!hostname || hostname === 'localhost' ||
      hostname.endsWith('.localhost') ||
      hostname.endsWith('.local') ||
      hostname.endsWith('.internal') ||
      hostname.endsWith('.lan') ||
      hostname.endsWith('.home')) {
    throw new UnsafeUrlError('Local network URLs are not allowed.');
  }
  const allowedPort = parsed.protocol === 'https:' ? '443' : '80';
  if (parsed.port && parsed.port !== allowedPort) {
    throw new UnsafeUrlError('Non-standard URL ports are not allowed.');
  }
  parsed.hash = '';
  return parsed;
}

function ipv4Number(address: string): number | null {
  const parts = address.split('.');
  if (parts.length !== 4) return null;
  let value = 0;
  for (const rawPart of parts) {
    if (!/^\d{1,3}$/.test(rawPart)) return null;
    const part = Number(rawPart);
    if (part < 0 || part > 255) return null;
    value = (value * 256) + part;
  }
  return value >>> 0;
}

function ipv4InCidr(value: number, base: string, prefix: number): boolean {
  const baseValue = ipv4Number(base);
  if (baseValue == null) return false;
  if (prefix === 0) return true;
  const mask = (0xffffffff << (32 - prefix)) >>> 0;
  return (value & mask) === (baseValue & mask);
}

function isPublicIpv4(address: string): boolean {
  const value = ipv4Number(address);
  if (value == null) return false;
  const blocked: Array<[string, number]> = [
    ['0.0.0.0', 8],
    ['10.0.0.0', 8],
    ['100.64.0.0', 10],
    ['127.0.0.0', 8],
    ['169.254.0.0', 16],
    ['172.16.0.0', 12],
    ['192.0.0.0', 24],
    ['192.0.2.0', 24],
    ['192.88.99.0', 24],
    ['192.168.0.0', 16],
    ['198.18.0.0', 15],
    ['198.51.100.0', 24],
    ['203.0.113.0', 24],
    ['224.0.0.0', 4],
    ['240.0.0.0', 4],
  ];
  return !blocked.some(([base, prefix]) =>
    ipv4InCidr(value, base, prefix));
}

function parseIpv6(address: string): number[] | null {
  let normalized = address.toLowerCase().split('%')[0];
  if (normalized.includes('.')) {
    const lastColon = normalized.lastIndexOf(':');
    const ipv4 = ipv4Number(normalized.slice(lastColon + 1));
    if (lastColon < 0 || ipv4 == null) return null;
    const high = ((ipv4 >>> 16) & 0xffff).toString(16);
    const low = (ipv4 & 0xffff).toString(16);
    normalized = normalized.slice(0, lastColon) + ':' + high + ':' + low;
  }
  const halves = normalized.split('::');
  if (halves.length > 2) return null;
  const left = halves[0] ? halves[0].split(':') : [];
  const right = halves.length === 2 && halves[1] ? halves[1].split(':') : [];
  const missing = 8 - left.length - right.length;
  if ((halves.length === 1 && missing !== 0) ||
      (halves.length === 2 && missing < 1)) {
    return null;
  }
  const pieces = [
    ...left,
    ...Array(Math.max(0, missing)).fill('0'),
    ...right,
  ];
  if (pieces.length !== 8) return null;
  const bytes: number[] = [];
  for (const piece of pieces) {
    if (!/^[0-9a-f]{1,4}$/.test(piece)) return null;
    const value = parseInt(piece, 16);
    bytes.push((value >>> 8) & 0xff, value & 0xff);
  }
  return bytes;
}

function isPublicIpv6(address: string): boolean {
  const bytes = parseIpv6(address);
  if (bytes == null) return false;
  // Only globally routable unicast (2000::/3) is accepted. Explicitly reject
  // documentation/benchmark/ORCHID ranges that sit inside that broad prefix.
  // ULA (fc00::/7), link-local (fe80::/10), multicast (ff00::/8), loopback,
  // unspecified, IPv4-mapped and translation ranges fail the /3 check.
  if (bytes[0] < 0x20 || bytes[0] > 0x3f) return false;
  const is2001 = bytes[0] === 0x20 && bytes[1] === 0x01;
  if (is2001 && bytes[2] === 0x0d && bytes[3] === 0xb8) return false;
  if (is2001 && bytes[2] === 0x00 && bytes[3] === 0x02) return false;
  if (is2001 && bytes[2] === 0x00 && (bytes[3] & 0xf0) === 0x10) return false;
  // 3fff::/20 is reserved for documentation.
  if (bytes[0] === 0x3f && bytes[1] === 0xff && (bytes[2] & 0xf0) === 0) {
    return false;
  }
  return true;
}

function isPublicIp(address: string): boolean {
  const family = net.isIP(address);
  if (family === 4) return isPublicIpv4(address);
  if (family === 6) return isPublicIpv6(address);
  return false;
}

async function resolvePublicAddress(
  target: URL,
  timeoutMs = DNS_TIMEOUT_MS,
): Promise<{address: string; family: number}> {
  const hostname = target.hostname.replace(/^\[|\]$/g, '');
  const literalFamily = net.isIP(hostname);
  if (literalFamily !== 0) {
    if (!isPublicIp(hostname)) {
      throw new UnsafeUrlError('Private or reserved IP addresses are blocked.');
    }
    return {address: hostname, family: literalFamily};
  }
  let addresses: dns.LookupAddress[];
  let timer: NodeJS.Timeout | undefined;
  try {
    addresses = await Promise.race([
      dns.promises.lookup(hostname, {all: true, verbatim: true}),
      new Promise<dns.LookupAddress[]>((_, reject) => {
        timer = setTimeout(
          () => reject(new LinkFetchError('DNS lookup timed out.')),
          Math.max(1, Math.min(DNS_TIMEOUT_MS, timeoutMs)),
        );
      }),
    ]);
  } catch (_) {
    throw new LinkFetchError('The host could not be resolved.');
  } finally {
    if (timer) clearTimeout(timer);
  }
  if (addresses.length === 0 ||
      addresses.some((entry) => !isPublicIp(entry.address))) {
    throw new UnsafeUrlError('Private or reserved network targets are blocked.');
  }
  return addresses[0];
}

async function firstSafePublicHttpUrl(text: string): Promise<URL | null> {
  const deadlineMs = Date.now() + LINK_URL_SELECTION_TIMEOUT_MS;
  for (const rawCandidate of httpUrlCandidates(text)) {
    const remainingMs = deadlineMs - Date.now();
    if (remainingMs <= 0) return null;
    try {
      const candidate = canonicalWebUrl(rawCandidate);
      await resolvePublicAddress(candidate, remainingMs);
      return candidate;
    } catch (error) {
      // A malformed, private/reserved, or unresolvable earlier URL must not
      // prevent a later public URL in the same message from getting a card.
      if (error instanceof UnsafeUrlError || error instanceof LinkFetchError) {
        continue;
      }
      throw error;
    }
  }
  return null;
}

function headerValue(value: string | string[] | undefined): string {
  if (Array.isArray(value)) return value[0] ?? '';
  return value ?? '';
}

async function requestHtmlOnce(
  target: URL,
  deadlineMs: number,
): Promise<{
  status: number;
  location: string;
  contentType: string;
  body: string;
}> {
  const remaining = deadlineMs - Date.now();
  if (remaining <= 0) throw new LinkFetchError('The request timed out.');
  const resolved = await resolvePublicAddress(target);
  const remainingAfterDns = deadlineMs - Date.now();
  if (remainingAfterDns <= 0) {
    throw new LinkFetchError('The request timed out.');
  }
  const timeout = Math.max(
    1,
    Math.min(HTTP_TIMEOUT_MS, remainingAfterDns),
  );
  const originalHostname = target.hostname.replace(/^\[|\]$/g, '');

  return new Promise((resolve, reject) => {
    let settled = false;
    const succeed = (value: {
      status: number;
      location: string;
      contentType: string;
      body: string;
    }): void => {
      if (settled) return;
      settled = true;
      clearTimeout(deadlineTimer);
      resolve(value);
    };
    const fail = (error: Error): void => {
      if (settled) return;
      settled = true;
      clearTimeout(deadlineTimer);
      reject(error);
    };
    const options: https.RequestOptions = {
      protocol: target.protocol,
      hostname: resolved.address,
      family: resolved.family,
      port: target.port || (target.protocol === 'https:' ? 443 : 80),
      method: 'GET',
      path: target.pathname + target.search,
      servername: net.isIP(originalHostname) === 0
        ? originalHostname
        : undefined,
      rejectUnauthorized: true,
      headers: {
        host: target.host,
        accept: 'text/html,application/xhtml+xml;q=0.9',
        'accept-encoding': 'identity',
        'user-agent': 'WefillingLinkPreview/1.0',
      },
    };
    const handleResponse = (response: http.IncomingMessage): void => {
      const status = response.statusCode ?? 0;
      const location = headerValue(response.headers.location);
      if ([301, 302, 303, 307, 308].includes(status)) {
        response.resume();
        succeed({status, location, contentType: '', body: ''});
        return;
      }
      if (status < 200 || status >= 300) {
        response.resume();
        fail(new LinkFetchError('The page returned an error response.'));
        return;
      }
      const contentType = headerValue(response.headers['content-type'])
        .toLowerCase();
      if (!contentType.startsWith('text/html') &&
          !contentType.startsWith('application/xhtml+xml')) {
        response.resume();
        fail(new LinkFetchError('The URL does not contain an HTML page.'));
        return;
      }
      const encoding = headerValue(response.headers['content-encoding'])
        .toLowerCase();
      if (encoding && encoding !== 'identity') {
        response.resume();
        fail(new LinkFetchError('Compressed HTML is not accepted.'));
        return;
      }
      const contentLength = Number(
        headerValue(response.headers['content-length']),
      );
      if (Number.isFinite(contentLength) && contentLength > MAX_HTML_BYTES) {
        response.resume();
        fail(new LinkFetchError('The HTML document is too large.'));
        return;
      }

      const chunks: Buffer[] = [];
      let byteLength = 0;
      response.on('data', (chunk: Buffer | string) => {
        const buffer = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
        byteLength += buffer.length;
        if (byteLength > MAX_HTML_BYTES) {
          response.destroy(new LinkFetchError('The HTML document is too large.'));
          return;
        }
        chunks.push(buffer);
      });
      response.on('end', () => {
        succeed({
          status,
          location: '',
          contentType,
          body: Buffer.concat(chunks, byteLength).toString('utf8'),
        });
      });
      response.on('error', fail);
    };
    const request = target.protocol === 'https:'
      ? https.request(options, handleResponse)
      : http.request(options, handleResponse);
    // ClientRequest.setTimeout is only an inactivity timer and can be defeated
    // by a slow-drip response. Enforce the absolute cross-redirect deadline as
    // well so link-preview workers cannot be held open indefinitely.
    const deadlineTimer = setTimeout(() => {
      const error = new LinkFetchError('The request timed out.');
      fail(error);
      request.destroy(error);
    }, Math.max(1, deadlineMs - Date.now()));
    request.setTimeout(timeout, () => {
      const error = new LinkFetchError('The request timed out.');
      fail(error);
      request.destroy(error);
    });
    request.on('error', fail);
    request.end();
  });
}

async function fetchHtmlWithRedirects(
  requested: URL,
): Promise<{html: string; finalUrl: URL}> {
  let current = requested;
  const visited = new Set<string>();
  const deadline = Date.now() + HTTP_TOTAL_TIMEOUT_MS;
  for (let redirect = 0; redirect <= MAX_REDIRECTS; redirect += 1) {
    const canonical = current.toString();
    if (visited.has(canonical)) {
      throw new LinkFetchError('The URL redirected in a loop.');
    }
    visited.add(canonical);
    const response = await requestHtmlOnce(current, deadline);
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      if (!response.location || redirect === MAX_REDIRECTS) {
        throw new LinkFetchError('Too many redirects.');
      }
      let redirected: URL;
      try {
        redirected = canonicalWebUrl(
          new URL(response.location, current).toString(),
        );
      } catch (error) {
        if (error instanceof UnsafeUrlError) throw error;
        throw new UnsafeUrlError('Invalid redirect target.');
      }
      current = redirected;
      continue;
    }
    return {html: response.body, finalUrl: current};
  }
  throw new LinkFetchError('Too many redirects.');
}

function decodeHtml(value: string): string {
  const named: Record<string, string> = {
    amp: '&',
    quot: '"',
    apos: '\'',
    lt: '<',
    gt: '>',
    nbsp: ' ',
  };
  return value
    .replace(/&#x([0-9a-f]+);?/gi, (_match, hex: string) => {
      const code = parseInt(hex, 16);
      return Number.isFinite(code) ? String.fromCodePoint(code) : '';
    })
    .replace(/&#(\d+);?/g, (_match, raw: string) => {
      const code = parseInt(raw, 10);
      return Number.isFinite(code) ? String.fromCodePoint(code) : '';
    })
    .replace(/&([a-z]+);/gi, (match, name: string) =>
      named[name.toLowerCase()] ?? match)
    .replace(/\s+/g, ' ')
    .trim();
}

function tagAttributes(tag: string): Record<string, string> {
  const attributes: Record<string, string> = {};
  const pattern = /([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>]+))/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(tag)) != null) {
    const key = match[1].toLowerCase();
    attributes[key] = match[2] ?? match[3] ?? match[4] ?? '';
  }
  return attributes;
}

function htmlMetadata(html: string): Map<string, string> {
  const metadata = new Map<string, string>();
  const metaPattern = /<meta\b[^>]*>/gi;
  let match: RegExpExecArray | null;
  while ((match = metaPattern.exec(html)) != null) {
    const attributes = tagAttributes(match[0]);
    const key = stringValue(attributes.property || attributes.name)
      .toLowerCase();
    const content = decodeHtml(attributes.content ?? '');
    if (key && content && !metadata.has(key)) metadata.set(key, content);
  }
  const title = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html);
  if (title) {
    const value = decodeHtml(title[1].replace(/<[^>]+>/g, ' '));
    if (value) metadata.set('document:title', value);
  }
  return metadata;
}

async function linkPreviewFromHtml(
  requested: URL,
  finalUrl: URL,
  html: string,
): Promise<LinkPreview> {
  const metadata = htmlMetadata(html);
  const domain = finalUrl.hostname.replace(/^www\./i, '');
  const title = boundedString(
    metadata.get('og:title') ??
      metadata.get('twitter:title') ??
      metadata.get('document:title') ??
      domain,
    200,
  );
  const description = boundedString(
    metadata.get('og:description') ??
      metadata.get('twitter:description') ??
      metadata.get('description') ??
      '',
    500,
  );
  const rawImage = stringValue(
    metadata.get('og:image:secure_url') ??
      metadata.get('og:image') ??
      metadata.get('twitter:image') ??
      '',
  );
  let imageUrl: string | undefined;
  if (rawImage) {
    try {
      const parsedImage = canonicalWebUrl(new URL(rawImage, finalUrl).toString());
      await resolvePublicAddress(parsedImage);
      imageUrl = parsedImage.toString();
    } catch (_) {
      imageUrl = undefined;
    }
  }
  return {
    url: requested.toString(),
    domain: boundedString(domain, 255),
    title: title || domain,
    description,
    ...(imageUrl ? {imageUrl} : {}),
  };
}

function normalizedCachedPreview(value: unknown): LinkPreview | null {
  const data = objectValue(value);
  const url = stringValue(data.url);
  const domain = boundedString(data.domain, 255);
  const title = boundedString(data.title, 200);
  const description = boundedString(data.description, 500);
  const imageUrl = stringValue(data.imageUrl);
  if (!url || !domain || !title) return null;
  try {
    canonicalWebUrl(url);
    if (imageUrl) canonicalWebUrl(imageUrl);
  } catch (_) {
    return null;
  }
  return {
    url,
    domain,
    title,
    description,
    ...(imageUrl ? {imageUrl} : {}),
  };
}

async function callableMessageAccess(
  uid: string,
  raw: unknown,
): Promise<{
  roomId: string;
  messageId: string;
  roomRef: FirebaseFirestore.DocumentReference;
  messageRef: FirebaseFirestore.DocumentReference;
  room: FirebaseFirestore.DocumentSnapshot;
  message: FirebaseFirestore.DocumentSnapshot;
}> {
  const data = objectValue(raw);
  const roomId = firestoreId(
    data.snackChatId ?? data.roomId ?? data.chatId,
    'Snack Chat id',
  );
  const messageId = firestoreId(data.messageId ?? data.targetId, 'message id');
  const roomRef = db().collection(SNACK_CHATS).doc(roomId);
  const messageRef = roomRef.collection('messages').doc(messageId);
  const [room, message] = await Promise.all([roomRef.get(), messageRef.get()]);
  if (!room.exists || !message.exists) {
    throw new functions.https.HttpsError('not-found', 'Message not found.');
  }
  if (!uniqueStrings(room.get('participantIds')).includes(uid)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only current room participants can perform this action.',
    );
  }
  return {roomId, messageId, roomRef, messageRef, room, message};
}

type SnackChatFileRequest = {
  roomId: string;
  messageId: string;
  uploadId: string;
  fileId: string;
  originalFileName: string;
  fileExtension: string;
  mimeType: string;
  fileSize: number;
  replyToMessageId: string;
};

function snackChatFileRequest(raw: unknown): SnackChatFileRequest {
  const data = objectValue(raw);
  const fileExtension = stringValue(data.fileExtension).toLowerCase();
  const mimeType = stringValue(data.mimeType).toLowerCase();
  const expectedMime = SNACK_CHAT_FILE_MIME_BY_EXTENSION[fileExtension];
  const originalFileName = stringValue(data.originalFileName);
  const fileSize = Number(data.fileSize);
  if (!expectedMime || mimeType !== expectedMime ||
      !originalFileName || originalFileName.includes('/') ||
      originalFileName.includes('\\') ||
      Array.from(originalFileName).length > 240 ||
      /[\u0000-\u001F\u007F]/.test(originalFileName) ||
      !Number.isInteger(fileSize) || fileSize <= 0 ||
      fileSize > SNACK_CHAT_FILE_MAX_BYTES) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Invalid Snack Chat file metadata.',
    );
  }
  return {
    roomId: firestoreId(
      data.snackChatId ?? data.roomId ?? data.chatId,
      'Snack Chat id',
    ),
    messageId: firestoreId(data.messageId, 'message id'),
    uploadId: firestoreId(data.uploadId, 'upload id'),
    fileId: firestoreId(data.fileId, 'file id'),
    originalFileName,
    fileExtension,
    mimeType,
    fileSize,
    replyToMessageId: stringValue(data.replyToMessageId)
      ? firestoreId(data.replyToMessageId, 'reply message id')
      : '',
  };
}

function fileJobMatches(
  job: Data,
  uid: string,
  request: SnackChatFileRequest,
): boolean {
  return stringValue(job.senderId) === uid &&
    stringValue(job.chatRoomId) === request.roomId &&
    stringValue(job.messageId) === request.messageId &&
    stringValue(job.uploadId) === request.uploadId &&
    stringValue(job.fileId) === request.fileId &&
    stringValue(job.originalFileName) === request.originalFileName &&
    stringValue(job.fileExtension) === request.fileExtension &&
    stringValue(job.mimeType) === request.mimeType &&
    Number(job.fileSize) === request.fileSize &&
    stringValue(job.replyToMessageId) === request.replyToMessageId;
}

function fileReplyPreview(
  messageId: string,
  snapshot: FirebaseFirestore.DocumentSnapshot,
): Data {
  const data = snapshot.data() ?? {};
  const explicitType = stringValue(data.type);
  const type = ['text', 'image', 'file', 'poll'].includes(explicitType)
    ? explicitType
    : stringValue(data.imagePath) || stringValue(data.imageUrl)
      ? 'image'
      : 'text';
  const text = stringValue(data.text);
  const imageUrl = stringValue(data.imageUrl);
  const imagePath = stringValue(data.imagePath);
  const originalFileName = stringValue(data.originalFileName);
  const expiresAt = data.expiresAt;
  return {
    messageId,
    senderId: stringValue(data.senderId),
    senderName: '',
    type,
    textPreview: Array.from(text).length <= 160 ? text : '',
    ...(imageUrl ? {imageUrl} : {}),
    ...(imagePath ? {imagePath} : {}),
    ...(type === 'file' && originalFileName ? {originalFileName} : {}),
    ...(type === 'file' && expiresAt instanceof Timestamp
      ? {fileExpiresAt: expiresAt}
      : {}),
    isDeleted: data.isDeleted === true,
  };
}

function startsWithBytes(value: Buffer, signature: Buffer): boolean {
  return value.length >= signature.length &&
    value.subarray(0, signature.length).equals(signature);
}

function utf16LeMarker(value: string): Buffer {
  return Buffer.from(value, 'utf16le');
}

function isKnownBlockedFileSignature(head: Buffer): boolean {
  return startsWithBytes(head, Buffer.from([0xFF, 0xD8, 0xFF])) ||
    startsWithBytes(head, Buffer.from([0x89, 0x50, 0x4E, 0x47])) ||
    startsWithBytes(head, Buffer.from('GIF8', 'ascii')) ||
    startsWithBytes(head, Buffer.from('ID3', 'ascii')) ||
    head.subarray(0, 4).toString('ascii') === 'RIFF' ||
    (head.length >= 12 &&
      head.subarray(4, 12).toString('ascii').includes('ftyp'));
}

/**
 * Validates the real Storage object bytes without buffering the whole file.
 * Storage Rules can verify metadata but cannot inspect content signatures, so
 * this server-side gate prevents a modified client from publishing a renamed
 * image, video, archive, or executable as a document message.
 */
async function snackChatFileContentMatches(
  storagePath: string,
  extension: string,
): Promise<boolean> {
  const markerGroups: Buffer[][] = [];
  if (['doc', 'xls', 'ppt', 'hwp'].includes(extension)) {
    const markers = extension === 'doc'
      ? ['WordDocument']
      : extension === 'xls'
        ? ['Workbook', 'Book']
        : extension === 'ppt'
          ? ['PowerPoint Document']
          : ['HWP Document File'];
    const alternatives: Buffer[] = [];
    markers.forEach((marker) => {
      alternatives.push(
        Buffer.from(marker, 'ascii'),
        utf16LeMarker(marker),
      );
    });
    markerGroups.push(alternatives);
  } else if (['docx', 'xlsx', 'pptx', 'hwpx'].includes(extension)) {
    const documentDirectory = extension === 'docx'
      ? 'word/'
      : extension === 'xlsx'
        ? 'xl/'
        : extension === 'pptx'
          ? 'ppt/'
          : 'Contents/';
    markerGroups.push(
      [Buffer.from('[Content_Types].xml', 'ascii')],
      [Buffer.from(documentDirectory, 'ascii')],
    );
  }

  const matchedGroups = markerGroups.map(() => false);
  let maxMarkerLength = 1;
  markerGroups.forEach((group) => group.forEach((marker) => {
    maxMarkerLength = Math.max(maxMarkerLength, marker.length);
  }));
  const isText = extension === 'txt' || extension === 'csv';
  const decoder = isText ? new TextDecoder('utf-8', {fatal: true}) : null;
  let utf8Valid = true;
  let containsNul = false;
  let head = Buffer.alloc(0);
  let overlap: Buffer = Buffer.alloc(0);
  let totalBytes = 0;
  let suspiciousControls = 0;
  let hasNonWhitespace = false;

  const stream = admin.storage().bucket().file(storagePath).createReadStream();
  await new Promise<void>((resolve, reject) => {
    stream.on('data', (rawChunk: Buffer | Uint8Array) => {
      const chunk = Buffer.isBuffer(rawChunk) ? rawChunk : Buffer.from(rawChunk);
      totalBytes += chunk.length;
      if (head.length < 32) {
        head = Buffer.concat([head, chunk]).subarray(0, 32);
      }

      if (isText) {
        for (const byte of chunk) {
          if (byte === 0) containsNul = true;
          if (byte > 0x20) hasNonWhitespace = true;
          if (byte < 0x09 || (byte > 0x0D && byte < 0x20)) {
            suspiciousControls++;
          }
        }
        if (utf8Valid && decoder) {
          try {
            decoder.decode(chunk, {stream: true});
          } catch (_) {
            utf8Valid = false;
          }
        }
      }

      if (markerGroups.length > 0) {
        const candidate = overlap.length > 0
          ? Buffer.concat([overlap, chunk])
          : chunk;
        markerGroups.forEach((group, groupIndex) => {
          if (!matchedGroups[groupIndex]) {
            matchedGroups[groupIndex] = group.some(
              (marker) => candidate.indexOf(marker) >= 0,
            );
          }
        });
        const retained = Math.max(0, maxMarkerLength - 1);
        overlap = retained === 0
          ? Buffer.alloc(0)
          : candidate.subarray(Math.max(0, candidate.length - retained));
      }
    });
    stream.once('end', resolve);
    stream.once('error', reject);
  });

  if (totalBytes <= 0 || isKnownBlockedFileSignature(head)) return false;
  if (extension === 'pdf') {
    return startsWithBytes(head, Buffer.from('%PDF-', 'ascii'));
  }
  if (isText) {
    if (containsNul || !hasNonWhitespace) return false;
    if (utf8Valid && decoder) {
      try {
        decoder.decode();
      } catch (_) {
        utf8Valid = false;
      }
    }
    return utf8Valid || suspiciousControls / totalBytes <= 0.002;
  }
  if (['doc', 'xls', 'ppt', 'hwp'].includes(extension)) {
    return startsWithBytes(
      head,
      Buffer.from([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]),
    ) && matchedGroups.every((matched) => matched);
  }
  if (['docx', 'xlsx', 'pptx', 'hwpx'].includes(extension)) {
    return startsWithBytes(head, Buffer.from([0x50, 0x4B])) &&
      matchedGroups.every((matched) => matched);
  }
  return false;
}

/** Creates one idempotent, server-authorized Storage upload job. */
export const prepareSnackChatFileUpload = functions
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    await requireActiveUser(uid);
    const request = snackChatFileRequest(raw);
    const roomRef = db().collection(SNACK_CHATS).doc(request.roomId);
    const messageRef = roomRef.collection('messages').doc(request.messageId);
    const jobRef = roomRef.collection('fileUploadJobs').doc(request.uploadId);
    const result = await db().runTransaction(async (transaction) => {
      const [room, message, job] = await transaction.getAll(
        roomRef,
        messageRef,
        jobRef,
      );
      if (!room.exists ||
          !uniqueStrings(room.get('participantIds')).includes(uid)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Only current room participants can upload files.',
        );
      }
      if (message.exists) {
        const messageData = message.data() ?? {};
        if (stringValue(messageData.senderId) !== uid ||
            stringValue(messageData.uploadId) !== request.uploadId ||
            stringValue(messageData.type) !== 'file') {
          throw new functions.https.HttpsError(
            'already-exists',
            'The message id is already in use.',
          );
        }
        return {
          committed: true,
          storagePath: stringValue(messageData.storagePath),
          retentionMode: stringValue(messageData.retentionMode),
        };
      }
      if (job.exists) {
        const jobData = job.data() ?? {};
        if (!fileJobMatches(jobData, uid, request)) {
          throw new functions.https.HttpsError(
            'permission-denied',
            'The upload job does not belong to this request.',
          );
        }
        return {
          committed: stringValue(jobData.status) === 'committed',
          storagePath: stringValue(jobData.storagePath),
          retentionMode: stringValue(jobData.retentionMode),
        };
      }
      if (request.replyToMessageId) {
        const original = await transaction.get(
          roomRef.collection('messages').doc(request.replyToMessageId),
        );
        if (!original.exists) {
          throw new functions.https.HttpsError(
            'not-found',
            'The reply target no longer exists.',
          );
        }
      }
      const retentionMode = Number(room.get('activeDurationHours')) === 0
        ? 'permanent'
        : 'temporary24h';
      const storagePath = [
        'snack_chat_files',
        retentionMode,
        request.roomId,
        request.messageId,
        request.fileId,
      ].join('/');
      const now = Timestamp.now();
      transaction.create(jobRef, {
        uploadId: request.uploadId,
        messageId: request.messageId,
        chatRoomId: request.roomId,
        senderId: uid,
        fileId: request.fileId,
        storagePath,
        retentionMode,
        originalFileName: request.originalFileName,
        fileExtension: request.fileExtension,
        mimeType: request.mimeType,
        fileSize: request.fileSize,
        ...(request.replyToMessageId
          ? {replyToMessageId: request.replyToMessageId}
          : {}),
        status: 'pending',
        createdAt: now,
        cleanupAt: Timestamp.fromMillis(
          now.toMillis() + SNACK_CHAT_FILE_JOB_TTL_MS,
        ),
      });
      return {committed: false, storagePath, retentionMode};
    });
    return {success: true, ...result};
  });

/** Atomically publishes the final file message after verifying the object. */
export const commitSnackChatFileUpload = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    await requireActiveUser(uid);
    const request = snackChatFileRequest(raw);
    const roomRef = db().collection(SNACK_CHATS).doc(request.roomId);
    const messageRef = roomRef.collection('messages').doc(request.messageId);
    const jobRef = roomRef.collection('fileUploadJobs').doc(request.uploadId);
    const initialJob = await jobRef.get();
    if (!initialJob.exists ||
        !fileJobMatches(initialJob.data() ?? {}, uid, request)) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'A matching upload job is required.',
      );
    }
    const initialJobData = initialJob.data() ?? {};
    const storagePath = stringValue(initialJobData.storagePath);
    let objectMetadata: Record<string, unknown>;
    try {
      const metadataResult = await admin.storage().bucket()
        .file(storagePath).getMetadata();
      objectMetadata = objectValue(metadataResult[0]);
    } catch (error) {
      const code = Number(objectValue(error).code);
      if (code === 404) {
        throw new functions.https.HttpsError(
          'not-found',
          'The uploaded object is not ready.',
        );
      }
      throw error;
    }
    const customMetadata = objectValue(objectMetadata['metadata']);
    if (Number(objectMetadata['size']) !== request.fileSize ||
        stringValue(objectMetadata['contentType']).toLowerCase() !==
          request.mimeType ||
        stringValue(customMetadata.senderId) !== uid ||
        stringValue(customMetadata.chatRoomId) !== request.roomId ||
        stringValue(customMetadata.uploadId) !== request.uploadId ||
        stringValue(customMetadata.messageId) !== request.messageId ||
        stringValue(customMetadata.fileId) !== request.fileId ||
        stringValue(customMetadata.fileExtension) !== request.fileExtension ||
        stringValue(customMetadata.retentionMode) !==
          stringValue(initialJobData.retentionMode)) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'The uploaded object metadata is invalid.',
      );
    }
    if (!await snackChatFileContentMatches(
      storagePath,
      request.fileExtension,
    )) {
      await admin.storage().bucket().file(storagePath)
        .delete({ignoreNotFound: true});
      throw new functions.https.HttpsError(
        'failed-precondition',
        'The uploaded object content does not match the document type.',
      );
    }

    const committed = await db().runTransaction(async (transaction) => {
      const [room, message, job] = await transaction.getAll(
        roomRef,
        messageRef,
        jobRef,
      );
      if (!room.exists ||
          !uniqueStrings(room.get('participantIds')).includes(uid)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Only current room participants can send files.',
        );
      }
      if (message.exists) {
        const existing = message.data() ?? {};
        if (stringValue(existing.senderId) !== uid ||
            stringValue(existing.uploadId) !== request.uploadId ||
            stringValue(existing.storagePath) !== storagePath) {
          throw new functions.https.HttpsError(
            'already-exists',
            'The message id is already in use.',
          );
        }
        if (job.exists && stringValue(job.get('status')) !== 'committed') {
          transaction.update(jobRef, {
            status: 'committed',
            cleanupAt: Timestamp.fromMillis(
              Date.now() + SNACK_CHAT_FILE_COMMITTED_JOB_TTL_MS,
            ),
          });
        }
        return false;
      }
      if (!job.exists || !fileJobMatches(job.data() ?? {}, uid, request) ||
          stringValue(job.get('storagePath')) !== storagePath ||
          stringValue(job.get('status')) === 'canceled') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The upload job is no longer available.',
        );
      }
      const createdAt = nextRoomMessageTimestamp(room);
      const retentionMode = stringValue(job.get('retentionMode'));
      const expiresAt = retentionMode === 'temporary24h'
        ? Timestamp.fromMillis(
          createdAt.toMillis() + SNACK_CHAT_FILE_RETENTION_MS,
        )
        : null;
      const sequence = nonNegativeInteger(room.get('lastMessageSequence')) + 1;
      const recipients = uniqueStrings(room.get('participantIds'))
        .filter((participantId) => participantId !== uid);
      const replyTarget = request.replyToMessageId
        ? await transaction.get(
          roomRef.collection('messages').doc(request.replyToMessageId),
        )
        : null;
      if (request.replyToMessageId && !replyTarget?.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'The reply target no longer exists.',
        );
      }
      transaction.create(messageRef, {
        messageId: request.messageId,
        messageScope: 'snack_chat',
        chatId: request.roomId,
        chatRoomId: request.roomId,
        senderId: uid,
        type: 'file',
        text: '',
        originalFileName: request.originalFileName,
        fileExtension: request.fileExtension,
        mimeType: request.mimeType,
        fileSize: request.fileSize,
        storagePath,
        retentionMode,
        createdAt,
        ...(expiresAt == null ? {} : {expiresAt, deleteAt: expiresAt}),
        uploadId: request.uploadId,
        ...(replyTarget?.exists ? {
          replyToMessageId: request.replyToMessageId,
          replyPreview: fileReplyPreview(
            request.replyToMessageId,
            replyTarget,
          ),
        } : {}),
        sequence,
        recipientIds: recipients,
        readBy: [uid],
        isDeleted: false,
        linkPreviewRemoved: true,
        reactionCounts: {},
      });
      const previewName = boundedString(request.originalFileName, 120);
      transaction.update(roomRef, {
        lastMessage: '📎 ' + previewName,
        lastMessageId: request.messageId,
        lastMessageTime: createdAt,
        lastMessageSenderId: uid,
        lastMessageSequence: sequence,
        lastMessageType: 'file',
        lastMessageExpiresAt: expiresAt,
        ['unreadCount.' + uid]: 0,
        updatedAt: createdAt,
      });
      transaction.update(jobRef, {
        status: 'committed',
        cleanupAt: Timestamp.fromMillis(
          createdAt.toMillis() + SNACK_CHAT_FILE_COMMITTED_JOB_TTL_MS,
        ),
      });
      return true;
    });
    return {success: true, committed};
  });

/** Cancels an unfinished upload and removes any partially-created object. */
export const cancelSnackChatFileUpload = functions
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    const data = objectValue(raw);
    const roomId = firestoreId(
      data.snackChatId ?? data.roomId ?? data.chatId,
      'Snack Chat id',
    );
    const uploadId = firestoreId(data.uploadId, 'upload id');
    const jobRef = db().collection(SNACK_CHATS).doc(roomId)
      .collection('fileUploadJobs').doc(uploadId);
    let storagePath = '';
    await db().runTransaction(async (transaction) => {
      const job = await transaction.get(jobRef);
      if (!job.exists) return;
      if (stringValue(job.get('senderId')) !== uid) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'The upload job belongs to another user.',
        );
      }
      if (stringValue(job.get('status')) === 'committed') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'A committed message cannot be canceled.',
        );
      }
      storagePath = stringValue(job.get('storagePath'));
      transaction.update(jobRef, {
        status: 'canceled',
        cleanupAt: Timestamp.fromMillis(Date.now() + 60 * 60 * 1000),
      });
    });
    if (storagePath.startsWith('snack_chat_files/')) {
      await admin.storage().bucket().file(storagePath)
        .delete({ignoreNotFound: true});
    }
    return {success: true};
  });

/**
 * Creates a normal Snack Chat after authoritatively validating active accounts
 * and the creator's friendship with every invited participant.
 */
export const createSnackChatSecure = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const creatorId = requireUid(context);
    await requireActiveUser(creatorId);
    const request = objectValue(raw);
    if (typeof request.title !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'A Snack Chat name is required.',
      );
    }
    const title = request.title.trim();
    if (!title || Array.from(title).length > 40) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'The Snack Chat name must contain 1 to 40 characters.',
      );
    }
    const requestedIds = firestoreIdList(
      request.participantIds,
      'participantIds',
      MAX_ROOM_PARTICIPANTS,
    );
    const participantIds = Array.from(new Set([creatorId, ...requestedIds]));
    if (participantIds.length < 2 ||
        participantIds.length > MAX_ROOM_PARTICIPANTS) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'A normal Snack Chat requires 2 to 50 participants.',
      );
    }
    const visibleToCategoryIds = boundedStringList(
      request.visibleToCategoryIds,
      'visibleToCategoryIds',
      100,
      128,
    );
    const activeDurationHours = Number(request.activeDurationHours);
    if (!Number.isInteger(activeDurationHours) ||
        (activeDurationHours !== 0 && activeDurationHours !== 24)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'activeDurationHours must be 0 or 24.',
      );
    }

    const invitedIds = participantIds.filter((id) => id !== creatorId);
    const roomRef = db().collection(SNACK_CHATS).doc();
    await db().runTransaction(async (transaction) => {
      const userRefs = participantIds.map((id) =>
        db().collection(USERS).doc(id));
      const friendshipRefs = invitedIds.map((id) =>
        db().collection(FRIENDSHIPS).doc(friendshipId(creatorId, id)));
      const userDocs = await transaction.getAll(...userRefs);
      const friendshipDocs = await transaction.getAll(...friendshipRefs);
      userDocs.forEach(assertActiveUserSnapshot);
      friendshipDocs.forEach((snapshot, index) =>
        assertFriendshipSnapshot(snapshot, creatorId, invitedIds[index]));

      const now = Timestamp.now();
      const expiresAt = activeDurationHours === 0
        ? Timestamp.fromDate(
          new Date(Date.UTC(9999, 11, 31)),
        )
        : Timestamp.fromMillis(
          now.toMillis() + activeDurationHours * 60 * 60 * 1000,
        );
      const unreadCount: Record<string, number> = {};
      participantIds.forEach((id) => {
        unreadCount[id] = 0;
      });
      transaction.create(roomRef, {
        title,
        creatorId,
        participantIds,
        visibleToCategoryIds,
        createdAt: now,
        listPolicyVersion: CURRENT_LIST_POLICY_VERSION,
        activeDurationHours,
        expiresAt,
        favoriteUserIds: [],
        lastMessage: '',
        lastMessageId: '',
        lastMessageTime: now,
        lastMessageSenderId: creatorId,
        lastMessageSequence: 0,
        unreadCount,
        updatedAt: now,
      });
    });
    return {success: true, snackChatId: roomRef.id};
  });

/**
 * Creates the single Snack Chat linked to a Meetup. The stored Meetup is the
 * authority for ownership, title, and frozen visibility; client display data
 * is deliberately ignored so it cannot widen or rename the linked room.
 */
export const createMeetupSnackChatSecure = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const creatorId = requireUid(context);
    const request = objectValue(raw);
    const meetupId = firestoreId(request.meetupId, 'Meetup id');
    const meetupRef = db().collection(MEETUPS).doc(meetupId);
    const creatorRef = db().collection(USERS).doc(creatorId);
    const newRoomRef = db().collection(SNACK_CHATS).doc();

    const result = await db().runTransaction(async (transaction) => {
      const [meetup, creator] = await transaction.getAll(
        meetupRef,
        creatorRef,
      );
      assertActiveUserSnapshot(creator);
      if (!meetup.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Meetup not found.',
        );
      }

      const meetupData = meetup.data() ?? {};
      const ownerId = stringValue(meetupData.ownerId);
      const legacyOwnerId = stringValue(meetupData.userId);
      if (meetupHasEnded(meetupData)) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'An ended Meetup cannot create a Snack Chat.',
        );
      }

      const hasSchema2 =
        nonNegativeInteger(meetupData.visibilitySchemaVersion) >= 2;
      let visibilityMode: string;
      let audience: string[];
      let sourceGroupIds: string[];
      let legacyBackfill: Data | null = null;

      if (hasSchema2) {
        if (ownerId !== creatorId ||
            (legacyOwnerId && legacyOwnerId !== creatorId)) {
          throw new functions.https.HttpsError(
            'permission-denied',
            'Only the Meetup owner can create its Snack Chat.',
          );
        }
        visibilityMode = stringValue(meetupData.visibilityMode);
        const rawAudience = meetupData.audienceUserIdsFrozen;
        const rawSourceGroupIds = meetupData.sourceGroupIds;
        if (!Array.isArray(rawAudience) ||
            !Array.isArray(rawSourceGroupIds)) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'The Meetup does not have a valid frozen audience.',
          );
        }
        audience = boundedStringList(
          rawAudience,
          'Meetup frozen audience',
          500,
          128,
        );
        sourceGroupIds = boundedStringList(
          rawSourceGroupIds,
          'Meetup source group ids',
          100,
          128,
        );
        const hasCanonicalFrozenAudience =
          ['public', 'friends', 'category'].includes(visibilityMode) &&
          audience.length === rawAudience.length &&
          audience.includes(creatorId) &&
          sourceGroupIds.length === rawSourceGroupIds.length &&
          meetupData.visibilityLockedAt instanceof
            Timestamp &&
          (visibilityMode === 'category'
            ? sourceGroupIds.length > 0
            : sourceGroupIds.length === 0);
        if (!hasCanonicalFrozenAudience) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'The Meetup does not have a valid frozen audience.',
          );
        }
      } else {
        // Legacy fields are accepted only once and are frozen in the same
        // transaction as the room link. Unknown values never fall through to
        // a permissive default.
        if (legacyOwnerId !== creatorId ||
            (ownerId && ownerId !== creatorId)) {
          throw new functions.https.HttpsError(
            'permission-denied',
            'Only the Meetup owner can create its Snack Chat.',
          );
        }
        visibilityMode = stringValue(meetupData.visibility);
        if (!['public', 'friends', 'category'].includes(visibilityMode)) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'The legacy Meetup visibility is invalid.',
          );
        }
        const rawLegacyAudience = meetupData.allowedUserIds ?? [];
        const rawLegacySourceGroupIds =
          meetupData.visibleToCategoryIds ?? [];
        if (!Array.isArray(rawLegacyAudience) ||
            !Array.isArray(rawLegacySourceGroupIds)) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'The legacy Meetup audience is malformed.',
          );
        }
        audience = boundedStringList(
          rawLegacyAudience,
          'legacy Meetup audience',
          500,
          128,
        );
        if (!audience.includes(creatorId)) {
          if (audience.length >= 500) {
            throw new functions.https.HttpsError(
              'failed-precondition',
              'The legacy Meetup audience is too large to freeze safely.',
            );
          }
          audience.push(creatorId);
        }
        const legacySourceGroupIds = boundedStringList(
          rawLegacySourceGroupIds,
          'legacy Meetup source group ids',
          100,
          128,
        );
        sourceGroupIds = visibilityMode === 'category'
          ? legacySourceGroupIds
          : [];
        if (visibilityMode === 'category' && sourceGroupIds.length === 0) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'The legacy category Meetup has no source group.',
          );
        }
        legacyBackfill = {
          ownerId: creatorId,
          visibilityMode,
          audienceUserIdsFrozen: audience,
          sourceGroupIds,
          visibilitySchemaVersion: 2,
        };
      }

      const title = boundedString(meetupData.title, 40);
      if (typeof meetupData.title !== 'string' || !title) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The Meetup does not have a valid title.',
        );
      }
      const canonicalCategoryIds = visibilityMode === 'category'
        ? sourceGroupIds
        : [];

      const existingId = stringValue(meetupData.snackChatId);
      if (existingId) {
        const safeExistingId = firestoreId(existingId, 'Snack Chat id');
        const existingRoom = await transaction.get(
          db().collection(SNACK_CHATS).doc(safeExistingId),
        );
        if (!existingRoom.exists ||
            stringValue(existingRoom.get('meetupId')) !== meetupId ||
            existingRoom.get('allowMeetupJoin') !== true ||
            Number(existingRoom.get('activeDurationHours')) !== 24 ||
            !(existingRoom.get('createdAt') instanceof
              Timestamp) ||
            !(existingRoom.get('expiresAt') instanceof
              Timestamp)) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'The Meetup has an invalid Snack Chat link.',
          );
        }
        const existingCategories = uniqueStrings(
          existingRoom.get('visibleToCategoryIds'),
        );
        if (existingCategories.length !== canonicalCategoryIds.length ||
            !canonicalCategoryIds.every((id) =>
              existingCategories.includes(id))) {
          throw new functions.https.HttpsError(
            'failed-precondition',
            'The linked Snack Chat audience is invalid.',
          );
        }
        const roomExpired =
          timestampMillis(existingRoom.get('expiresAt')) <= Date.now();
        if (!roomExpired) {
          const existingParticipants = uniqueStrings(
            existingRoom.get('participantIds'),
          );
          if (!existingParticipants.includes(creatorId)) {
            if (existingParticipants.length >= MAX_ROOM_PARTICIPANTS) {
              throw new functions.https.HttpsError(
                'resource-exhausted',
                'The linked Snack Chat is full.',
              );
            }
            const nextParticipants = [...existingParticipants, creatorId];
            const previousUnread = normalizedCountMap(
              existingRoom.get('unreadCount'),
            );
            const unreadCount: Record<string, number> = {};
            nextParticipants.forEach((id) => {
              unreadCount[id] = previousUnread[id] ?? 0;
            });
            unreadCount[creatorId] = 0;
            transaction.update(existingRoom.ref, {
              participantIds: nextParticipants,
              unreadCount,
              updatedAt: FieldValue.serverTimestamp(),
            });
          }
          if (legacyBackfill) {
            const now = Timestamp.now();
            transaction.update(meetupRef, {
              ...legacyBackfill,
              visibilityLockedAt: now,
              updatedAt: now,
            });
          }
          return {snackChatId: safeExistingId, created: false};
        }

        // Preserve the old room and its history for existing participants,
        // but prevent the stale Meetup link from admitting anybody else.
        transaction.update(existingRoom.ref, {
          allowMeetupJoin: false,
          updatedAt: FieldValue.serverTimestamp(),
        });
      }

      const now = Timestamp.now();
      const expiresAt = Timestamp.fromMillis(
        now.toMillis() + 24 * 60 * 60 * 1000,
      );
      transaction.create(newRoomRef, {
        title,
        creatorId,
        participantIds: [creatorId],
        visibleToCategoryIds: canonicalCategoryIds,
        meetupId,
        allowMeetupJoin: true,
        createdAt: now,
        listPolicyVersion: CURRENT_LIST_POLICY_VERSION,
        activeDurationHours: 24,
        expiresAt,
        favoriteUserIds: [],
        lastMessage: '',
        lastMessageId: '',
        lastMessageTime: now,
        lastMessageSenderId: creatorId,
        lastMessageSequence: 0,
        unreadCount: {[creatorId]: 0},
        updatedAt: now,
      });
      transaction.update(meetupRef, {
        ...(legacyBackfill ?? {}),
        ...(legacyBackfill ? {visibilityLockedAt: now} : {}),
        snackChatId: newRoomRef.id,
        groupChatEnabled: true,
        updatedAt: now,
      });
      return {snackChatId: newRoomRef.id, created: true};
    });

    return {
      success: true,
      snackChatId: result.snackChatId,
      created: result.created,
    };
  });

/** Adds active friends to an existing room. Only the current creator may call. */
export const inviteSnackChatParticipants = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const creatorId = requireUid(context);
    await requireActiveUser(creatorId);
    const request = objectValue(raw);
    const snackChatId = firestoreId(request.snackChatId, 'Snack Chat id');
    const requestedIds = firestoreIdList(
      request.participantIds,
      'participantIds',
      MAX_ROOM_PARTICIPANTS,
    ).filter((id) => id !== creatorId);
    const roomRef = db().collection(SNACK_CHATS).doc(snackChatId);

    const invitedUserIds = await db().runTransaction(async (transaction) => {
      const room = await transaction.get(roomRef);
      if (!room.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Snack Chat not found.',
        );
      }
      const current = uniqueStrings(room.get('participantIds'));
      if (stringValue(room.get('creatorId')) !== creatorId ||
          !current.includes(creatorId)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Only the current room creator can invite participants.',
        );
      }
      if (room.get('allowMeetupJoin') === true ||
          stringValue(room.get('meetupId')).length > 0) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'Meetup Snack Chat participants must join through the Meetup.',
        );
      }
      const currentSet = new Set(current);
      const toAdd = requestedIds.filter((id) => !currentSet.has(id));
      if (toAdd.length === 0) return [];
      if (current.length + toAdd.length > MAX_ROOM_PARTICIPANTS) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'A Snack Chat can contain at most 50 participants.',
        );
      }

      const userRefs = [creatorId, ...toAdd].map((id) =>
        db().collection(USERS).doc(id));
      const friendshipRefs = toAdd.map((id) =>
        db().collection(FRIENDSHIPS).doc(friendshipId(creatorId, id)));
      const userDocs = await transaction.getAll(...userRefs);
      const friendshipDocs = await transaction.getAll(...friendshipRefs);
      userDocs.forEach(assertActiveUserSnapshot);
      friendshipDocs.forEach((snapshot, index) =>
        assertFriendshipSnapshot(snapshot, creatorId, toAdd[index]));

      const nextParticipants = [...current, ...toAdd];
      const previousUnread = normalizedCountMap(room.get('unreadCount'));
      const unreadCount: Record<string, number> = {};
      nextParticipants.forEach((id) => {
        unreadCount[id] = previousUnread[id] ?? 0;
      });
      toAdd.forEach((id) => {
        unreadCount[id] = 0;
      });
      transaction.update(roomRef, {
        participantIds: nextParticipants,
        unreadCount,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return toAdd;
    });
    return {success: true, invitedUserIds};
  });

/**
 * Joins a Meetup-linked room without exposing its participant/unread metadata
 * to a non-participant. Meetup visibility and the room link are checked here.
 */
export const joinMeetupSnackChatSecure = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const userId = requireUid(context);
    await requireActiveUser(userId);
    const request = objectValue(raw);
    const snackChatId = firestoreId(request.snackChatId, 'Snack Chat id');
    const meetupId = firestoreId(request.meetupId, 'Meetup id');
    const roomRef = db().collection(SNACK_CHATS).doc(snackChatId);
    const meetupRef = db().collection(MEETUPS).doc(meetupId);
    const userRef = db().collection(USERS).doc(userId);

    const joined = await db().runTransaction(async (transaction) => {
      const [room, meetup, user] = await transaction.getAll(
        roomRef,
        meetupRef,
        userRef,
      );
      assertActiveUserSnapshot(user);
      if (!room.exists || !meetup.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Meetup Snack Chat not found.',
        );
      }
      if (room.get('allowMeetupJoin') !== true ||
          stringValue(room.get('meetupId')) !== meetupId) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'This room is not linked to the requested Meetup.',
        );
      }
      const linkedRoomId = stringValue(meetup.get('snackChatId'));
      if (linkedRoomId !== snackChatId) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'The Meetup does not point to this Snack Chat.',
        );
      }
      const meetupData = meetup.data() ?? {};
      if (meetupHasEnded(meetupData)) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'This Meetup has ended.',
        );
      }
      if (uniqueStrings(meetupData.kickedUserIds).includes(userId)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'You cannot join this Meetup Snack Chat.',
        );
      }
      if (!meetupAudienceAllows(meetupData, userId)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'You cannot join this Meetup Snack Chat.',
        );
      }
      const participants = uniqueStrings(room.get('participantIds'));
      if (participants.includes(userId)) return true;
      if (participants.length >= MAX_ROOM_PARTICIPANTS) {
        throw new functions.https.HttpsError(
          'resource-exhausted',
          'This Snack Chat already has 50 participants.',
        );
      }
      if (Number(room.get('activeDurationHours')) !== 0 &&
          timestampMillis(room.get('expiresAt')) <= Date.now()) {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'This Snack Chat has expired.',
        );
      }

      const nextParticipants = [...participants, userId];
      const previousUnread = normalizedCountMap(room.get('unreadCount'));
      const unreadCount: Record<string, number> = {};
      nextParticipants.forEach((id) => {
        unreadCount[id] = previousUnread[id] ?? 0;
      });
      unreadCount[userId] = 0;
      transaction.update(roomRef, {
        participantIds: nextParticipants,
        unreadCount,
        ...(participants.length === 0 ? {creatorId: userId} : {}),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    return {success: true, joined};
  });

/**
 * Repairs only a missing/stale materialized member document for somebody who
 * is still an authoritative room participant. The deterministic repair event
 * prevents repeated screen opens from creating duplicate membership periods.
 */
export const ensureSnackChatMembershipSecure = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const userId = requireUid(context);
    await requireActiveUser(userId);
    const request = objectValue(raw);
    const snackChatId = firestoreId(request.snackChatId, 'Snack Chat id');
    const roomRef = db().collection(SNACK_CHATS).doc(snackChatId);
    const memberRef = roomRef.collection('members').doc(userId);
    const [room, member] = await db().getAll(roomRef, memberRef);
    if (!room.exists) {
      throw new functions.https.HttpsError(
        'not-found',
        'Snack Chat not found.',
      );
    }
    if (!uniqueStrings(room.get('participantIds')).includes(userId)) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only a current participant can repair membership.',
      );
    }

    const memberData = member.data() ?? {};
    const hasOpenPeriod = periodsFrom(memberData.periods)
      .some((period) => period.leftAfterSequence == null);
    if (member.exists &&
        stringValue(memberData.status) === 'active' &&
        hasOpenPeriod) {
      return {success: true};
    }

    const boundary = nonNegativeInteger(room.get('lastMessageSequence'));
    const roomUpdatedAt = room.get('updatedAt');
    const revision = roomUpdatedAt instanceof Timestamp
      ? roomUpdatedAt.seconds + ':' + roomUpdatedAt.nanoseconds
      : String(timestampMillis(roomUpdatedAt));
    const occurredAt = roomUpdatedAt instanceof Timestamp
      ? roomUpdatedAt
      : Timestamp.now();
    await recordMembershipEvent({
      roomRef,
      userId,
      kind: 'join',
      boundary,
      sourceEventId: [
        'membership-repair',
        snackChatId,
        userId,
        String(boundary),
        revision,
      ].join(':'),
      occurredAt,
      requireCurrentParticipant: true,
    });
    return {success: true};
  });

/**
 * Removes the caller from a room in one idempotent server transaction. A
 * retry after an uncertain client timeout succeeds even if the first attempt
 * already committed.
 */
export const leaveSnackChatSecure = functions
  .runWith({timeoutSeconds: 30, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const userId = requireUid(context);
    const request = objectValue(raw);
    const snackChatId = firestoreId(request.snackChatId, 'Snack Chat id');
    const roomRef = db().collection(SNACK_CHATS).doc(snackChatId);

    const left = await db().runTransaction(async (transaction) => {
      const room = await transaction.get(roomRef);
      if (!room.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Snack Chat not found.',
        );
      }
      const participants = uniqueStrings(room.get('participantIds'));
      if (!participants.includes(userId)) return false;

      const nextParticipants = participants.filter((id) => id !== userId);
      const previousUnread = normalizedCountMap(room.get('unreadCount'));
      const unreadCount: Record<string, number> = {};
      nextParticipants.forEach((id) => {
        unreadCount[id] = previousUnread[id] ?? 0;
      });

      const update: Record<string, unknown> = {
        participantIds: nextParticipants,
        unreadCount,
        updatedAt: FieldValue.serverTimestamp(),
      };
      if (stringValue(room.get('creatorId')) === userId) {
        update.creatorId = nextParticipants[0] ?? '';
      }
      transaction.update(roomRef, update);
      return true;
    });
    return {success: true, left};
  });

/** Creator-only title update. The existing room-write trigger emits the
 * localized title_changed system event after the transaction commits. */
export const updateSnackChatTitleSecure = functions
  .runWith({timeoutSeconds: 15, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const creatorId = requireUid(context);
    const request = objectValue(raw);
    const snackChatId = firestoreId(request.snackChatId, 'Snack Chat id');
    if (typeof request.title !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'A Snack Chat name is required.',
      );
    }
    const title = request.title.trim();
    if (!title || Array.from(title).length > 40) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'The Snack Chat name must contain 1 to 40 characters.',
      );
    }
    const roomRef = db().collection(SNACK_CHATS).doc(snackChatId);
    const creatorRef = db().collection(USERS).doc(creatorId);
    const changed = await db().runTransaction(async (transaction) => {
      const [room, creator] = await transaction.getAll(roomRef, creatorRef);
      assertActiveUserSnapshot(creator);
      if (!room.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Snack Chat not found.',
        );
      }
      const participants = uniqueStrings(room.get('participantIds'));
      if (!participants.includes(creatorId) ||
          stringValue(room.get('creatorId')) !== creatorId) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Only the current room creator can change its name.',
        );
      }
      if (stringValue(room.get('title')) === title) return false;
      transaction.update(roomRef, {
        title,
        updatedAt: FieldValue.serverTimestamp(),
      });
      return true;
    });
    return {success: true, changed, title};
  });

/**
 * Creator-only announcement. A client-generated event id maps to one stable
 * message document so callable retries cannot append the announcement twice.
 */
export const createSnackChatAnnouncementSecure = functions
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const creatorId = requireUid(context);
    const request = objectValue(raw);
    const snackChatId = firestoreId(request.snackChatId, 'Snack Chat id');
    const eventId = firestoreId(request.eventId, 'announcement event id');
    if (eventId.length < 16 || eventId.length > 128) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Invalid announcement event id.',
      );
    }
    if (typeof request.text !== 'string') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Announcement text is required.',
      );
    }
    const body = request.text.trim();
    if (!body || Array.from(body).length > 500) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Announcement text must contain 1 to 500 characters.',
      );
    }

    const roomRef = db().collection(SNACK_CHATS).doc(snackChatId);
    const creatorRef = db().collection(USERS).doc(creatorId);
    const messageId = 'announcement_' + eventId;
    const messageRef = roomRef.collection('messages').doc(messageId);
    const result = await db().runTransaction(async (transaction) => {
      const [room, creator, existing] = await transaction.getAll(
        roomRef,
        creatorRef,
        messageRef,
      );
      assertActiveUserSnapshot(creator);
      if (!room.exists) {
        throw new functions.https.HttpsError(
          'not-found',
          'Snack Chat not found.',
        );
      }
      const participants = uniqueStrings(room.get('participantIds'));
      if (!participants.includes(creatorId) ||
          stringValue(room.get('creatorId')) !== creatorId) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'Only the current room creator can post an announcement.',
        );
      }

      if (existing.exists) {
        const metadata = objectValue(existing.get('metadata'));
        const isSameAnnouncement =
          stringValue(existing.get('type')) === 'system' &&
          stringValue(existing.get('senderId')) === creatorId &&
          stringValue(existing.get('text')) === body &&
          stringValue(existing.get('eventId')) === eventId &&
          stringValue(metadata.systemType) === 'announcement';
        if (!isSameAnnouncement) {
          throw new functions.https.HttpsError(
            'already-exists',
            'The announcement event id is already in use.',
          );
        }
        return {created: false, sequence: nonNegativeInteger(
          existing.get('sequence'),
        )};
      }

      const now = nextRoomMessageTimestamp(room);
      const sequence = nonNegativeInteger(room.get('lastMessageSequence')) + 1;
      const recipientIds = participants.filter((id) => id !== creatorId);
      const senderName = boundedString(
        creator.get('nickname') ?? creator.get('name') ?? 'User',
        80,
      ) || 'User';
      const lastMessage = boundedString('📢 ' + body, 500);
      transaction.create(messageRef, {
        senderId: creatorId,
        senderName,
        messageScope: 'snack_chat',
        chatId: snackChatId,
        type: 'system',
        text: body,
        createdAt: now,
        sequence,
        recipientIds,
        readBy: [creatorId],
        isDeleted: false,
        linkPreviewRemoved: true,
        reactionCounts: {},
        eventId,
        metadata: {
          systemType: 'announcement',
          announcement: body,
          userId: creatorId,
          userName: senderName,
          eventId,
        },
      });
      transaction.update(roomRef, {
        lastMessage,
        lastMessageId: messageId,
        lastMessageTime: now,
        lastMessageSenderId: creatorId,
        lastMessageSequence: sequence,
        updatedAt: now,
      });
      return {created: true, sequence};
    });
    return {
      success: true,
      created: result.created,
      snackChatId,
      messageId,
      sequence: result.sequence,
    };
  });

export const fetchSnackChatLinkPreview = functions
  .runWith({timeoutSeconds: 20, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const uid = requireUid(context);
    await requireActiveUser(uid);
    const request = objectValue(raw);
    const access = await callableMessageAccess(uid, request);
    const messageData = access.message.data() ?? {};
    if (stringValue(messageData.senderId) !== uid) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Only the message owner can manage its link preview.',
      );
    }

    if (request.remove === true) {
      await db().runTransaction(async (transaction) => {
        const room = await transaction.get(access.roomRef);
        const message = await transaction.get(access.messageRef);
        if (!room.exists || !message.exists ||
            !uniqueStrings(room.get('participantIds')).includes(uid) ||
            stringValue(message.get('senderId')) !== uid) {
          throw new functions.https.HttpsError(
            'permission-denied',
            'The link preview can no longer be changed.',
          );
        }
        transaction.update(access.messageRef, {
          linkPreview: FieldValue.delete(),
          linkPreviewRemoved: true,
        });
      });
      return {success: true, removed: true};
    }

    if (messageData.linkPreviewRemoved === true) {
      if (messageData.linkPreview != null) {
        await access.messageRef.update({
          linkPreview: FieldValue.delete(),
        });
      }
      return {success: true, removed: true};
    }

    const originalMessageText = stringValue(messageData.text);
    if (httpUrlCandidates(originalMessageText).length === 0) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'The message does not contain a previewable URL.',
      );
    }

    let selectedUrl: URL | null;
    try {
      // The message is the authority. `request.url` is intentionally ignored
      // for backward compatibility with older clients; trusting it would let
      // callers fetch arbitrary URLs unrelated to the stored message.
      selectedUrl = await firstSafePublicHttpUrl(originalMessageText);
    } catch (error) {
      console.warn('Snack Chat safe link candidate selection failed.', error);
      return {success: false};
    }
    if (selectedUrl == null) {
      return {success: false};
    }
    const requested = selectedUrl;

    const urlHash = crypto
      .createHash('sha256')
      .update(requested.toString())
      .digest('hex');
    const cacheRef = db().collection(LINK_PREVIEW_CACHE).doc(urlHash);
    const cached = await cacheRef.get();
    let preview: LinkPreview | null = null;
    if (cached.exists &&
        timestampMillis(cached.get('expiresAt')) > Date.now() &&
        stringValue(cached.get('url')) === requested.toString()) {
      preview = normalizedCachedPreview(cached.get('preview'));
    }

    if (!preview) {
      try {
        const result = await fetchHtmlWithRedirects(requested);
        preview = await linkPreviewFromHtml(
          requested,
          result.finalUrl,
          result.html,
        );
        const now = Timestamp.now();
        try {
          await cacheRef.set({
            urlHash,
            url: requested.toString(),
            preview,
            createdAt: now,
            updatedAt: now,
            expiresAt: Timestamp.fromMillis(
              now.toMillis() + LINK_CACHE_TTL_MS,
            ),
          });
        } catch (cacheError) {
          // Cache availability must never suppress an otherwise valid card.
          console.warn('Snack Chat link cache write failed.', cacheError);
        }
      } catch (error) {
        if (error instanceof UnsafeUrlError) {
          throw new functions.https.HttpsError(
            'invalid-argument',
            error.message,
          );
        }
        console.warn(
          'Snack Chat link preview fetch failed for hash=' + urlHash,
          error,
        );
        return {success: false};
      }
    }

    const finalPreview = preview;
    let updated = false;
    await db().runTransaction(async (transaction) => {
      const room = await transaction.get(access.roomRef);
      const message = await transaction.get(access.messageRef);
      const current = message.data() ?? {};
      if (!room.exists || !message.exists ||
          !uniqueStrings(room.get('participantIds')).includes(uid) ||
          stringValue(current.senderId) !== uid ||
          current.linkPreviewRemoved === true ||
          stringValue(current.text) !== originalMessageText) {
        return;
      }
      transaction.update(access.messageRef, {linkPreview: finalPreview});
      updated = true;
    });
    return {success: updated, preview: updated ? finalPreview : null};
  });

function snapshotValue(
  value: unknown,
  depth = 0,
): unknown {
  if (depth > 4 || value == null) return null;
  if (value instanceof Timestamp) return value;
  if (value instanceof Date) return Timestamp.fromDate(value);
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }
  if (typeof value === 'string') return boundedString(value, 2000);
  if (Array.isArray(value)) {
    return value.slice(0, 30).map((entry) => snapshotValue(entry, depth + 1));
  }
  if (typeof value === 'object') {
    const result: Record<string, unknown> = {};
    for (const [key, entry] of Object.entries(
      value as Record<string, unknown>,
    ).slice(0, 40)) {
      result[boundedString(key, 80)] = snapshotValue(entry, depth + 1);
    }
    return result;
  }
  return boundedString(value, 2000);
}

function reportMessageSnapshot(data: Data): Data {
  const keys = [
    'senderId',
    'senderName',
    'type',
    'text',
    'imageUrl',
    'imagePath',
    'originalFileName',
    'fileExtension',
    'mimeType',
    'fileSize',
    'storagePath',
    'retentionMode',
    'expiresAt',
    'uploadId',
    'createdAt',
    'sequence',
    'recipientIds',
    'replyToMessageId',
    'replyPreview',
    'isDeleted',
    'metadata',
    'linkPreview',
    'linkPreviewRemoved',
    'poll',
  ];
  const snapshot: Data = {};
  for (const key of keys) {
    if (data[key] !== undefined) snapshot[key] = snapshotValue(data[key]);
  }
  return snapshot;
}

/**
 * Report content is copied from the server snapshot. The caller cannot
 * substitute a different author, message body, or room for moderator review.
 */
export const reportSnackChatMessage = functions
  .runWith({timeoutSeconds: 15, memory: '256MB'})
  .https.onCall(async (raw, context) => {
    const reporterId = requireUid(context);
    const reporter = await requireActiveUser(reporterId);
    const request = objectValue(raw);
    const reason = boundedString(request.reason, 120);
    const description = boundedString(request.description, 500);
    if (!ALLOWED_REPORT_REASONS.has(reason)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'A supported report reason is required.',
      );
    }
    const access = await callableMessageAccess(reporterId, request);
    const message = access.message.data() ?? {};
    const reportedUserId = stringValue(message.senderId);
    if (!reportedUserId || stringValue(message.type) === 'system') {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'System messages cannot be reported.',
      );
    }
    if (reportedUserId === reporterId) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'You cannot report your own message.',
      );
    }

    const reportKey = [
      reporterId,
      access.roomId,
      access.messageId,
    ].join(':');
    const reportId = eventDocumentId('snack-chat-report', reportKey);
    const reportRef = db().collection(REPORTS).doc(reportId);
    const now = Timestamp.now();
    await db().runTransaction(async (transaction) => {
      const existing = await transaction.get(reportRef);
      if (existing.exists) return;
      const room = await transaction.get(access.roomRef);
      const currentMessage = await transaction.get(access.messageRef);
      if (!room.exists || !currentMessage.exists ||
          !uniqueStrings(room.get('participantIds')).includes(reporterId)) {
        throw new functions.https.HttpsError(
          'permission-denied',
          'You are no longer a participant in this Snack Chat.',
        );
      }
      const current = currentMessage.data() ?? {};
      const currentAuthor = stringValue(current.senderId);
      if (!currentAuthor || currentAuthor === reporterId ||
          stringValue(current.type) === 'system') {
        throw new functions.https.HttpsError(
          'failed-precondition',
          'This message cannot be reported.',
        );
      }
      transaction.create(reportRef, {
        id: reportId,
        reporterId,
        reporterName: boundedString(
          reporter.nickname ?? reporter.name ?? 'User',
          80,
        ),
        reportedUserId: currentAuthor,
        targetType: 'snack_chat_message',
        targetId: access.messageId,
        targetTitle: boundedString(room.get('title'), 120),
        snackChatId: access.roomId,
        messageId: access.messageId,
        reason,
        description,
        status: 'pending',
        messageSnapshot: reportMessageSnapshot(current),
        roomSnapshot: {
          title: boundedString(room.get('title'), 120),
          creatorId: stringValue(room.get('creatorId')),
        },
        createdAt: now,
        updatedAt: now,
      });
    });
    return {success: true, reportId};
  });

function periodsFrom(value: unknown): Period[] {
  if (!Array.isArray(value)) return [];
  const result: Period[] = [];
  for (const entry of value) {
    const data = objectValue(entry);
    const joinedAfterSequence = nonNegativeInteger(
      data.joinedAfterSequence,
    );
    const rawLeft = data.leftAfterSequence;
    const leftAfterSequence = rawLeft == null
      ? null
      : Math.max(joinedAfterSequence, nonNegativeInteger(rawLeft));
    result.push({joinedAfterSequence, leftAfterSequence});
  }
  return result;
}

function membershipEventsFrom(
  snapshots: FirebaseFirestore.QuerySnapshot,
): MembershipEvent[] {
  const events: MembershipEvent[] = [];
  for (const document of snapshots.docs) {
    const data = document.data();
    const kind = stringValue(data.kind);
    if (kind !== 'join' && kind !== 'leave') continue;
    events.push({
      id: document.id,
      kind,
      boundary: nonNegativeInteger(data.boundary),
      occurredAtMs: timestampMillis(data.occurredAt),
    });
  }
  return events;
}

function rebuildPeriods(
  baseline: Period[],
  events: MembershipEvent[],
): Period[] {
  const periods = baseline.map((period) => ({...period}));
  events.sort((a, b) =>
    a.occurredAtMs - b.occurredAtMs || a.id.localeCompare(b.id));
  for (const event of events) {
    const open = [...periods]
      .reverse()
      .find((period) => period.leftAfterSequence == null);
    if (event.kind === 'join') {
      if (!open) {
        periods.push({
          joinedAfterSequence: event.boundary,
          leftAfterSequence: null,
        });
      }
      continue;
    }
    if (open) {
      open.leftAfterSequence = Math.max(
        open.joinedAfterSequence,
        event.boundary,
      );
    }
  }
  return periods;
}

async function recordMembershipEvent(args: {
  roomRef: FirebaseFirestore.DocumentReference;
  userId: string;
  kind: 'join' | 'leave';
  boundary: number;
  sourceEventId: string;
  occurredAt: Timestamp;
  requireCurrentParticipant?: boolean;
}): Promise<void> {
  const memberRef = args.roomRef.collection('members').doc(args.userId);
  const events = memberRef.collection('_events');
  const eventId = eventDocumentId(
    'membership-' + args.kind,
    args.sourceEventId + ':' + args.userId,
  );
  const eventRef = events.doc(eventId);

  await db().runTransaction(async (transaction) => {
    const existingEvent = await transaction.get(eventRef);
    if (existingEvent.exists) return;
    const member = await transaction.get(memberRef);
    const room = await transaction.get(args.roomRef);
    if (!room.exists) return;
    if (args.requireCurrentParticipant === true &&
        !uniqueStrings(room.get('participantIds')).includes(args.userId)) {
      return;
    }

    const memberData = member.data() ?? {};
    // Never read or delete an unbounded legacy event collection in one
    // transaction. New rooms normally contain at most 64 events; the larger
    // cap also lets a temporarily expanded delayed-event window self-heal.
    const eventSnapshots = await transaction.get(
      events.orderBy('occurredAt', 'asc')
        .limit(MAX_MEMBERSHIP_EVENT_READ),
    );
    const eventWindowTruncated =
      eventSnapshots.size >= MAX_MEMBERSHIP_EVENT_READ;
    let baseline = periodsFrom(
      eventWindowTruncated
        ? memberData.periods
        : memberData.baselinePeriods,
    );
    let baselineFromCompatibility =
      eventWindowTruncated ||
      memberData.baselineFromCompatibility === true ||
      memberData.baselineAssumedLegacy === true;
    if (baseline.length === 0 &&
        !Object.prototype.hasOwnProperty.call(
          memberData,
          'baselinePeriods',
        )) {
      const compatibilityPeriods = periodsFrom(memberData.periods);
      if (args.kind === 'join') {
        // ensureMyMembership may win the race and create a current-sequence
        // placeholder. A real room join event is more authoritative and must
        // not be hidden by that placeholder's already-open period.
        baseline = [];
        baselineFromCompatibility = false;
      } else if (compatibilityPeriods.length > 0) {
        baseline = compatibilityPeriods;
        baselineFromCompatibility = true;
      } else if (args.kind === 'leave') {
        // A pre-deployment member may leave before any server history exists.
        baseline = [{
          joinedAfterSequence: 0,
          leftAfterSequence: null,
        }];
        baselineFromCompatibility = true;
      }
    }
    // A very large pre-window deployment is already represented by the
    // materialized periods field. Apply the new transition to that snapshot
    // without replaying a partial event prefix; keep legacy mode until a
    // dedicated migration can see the complete bounded history.
    const existingEvents = eventWindowTruncated
      ? []
      : membershipEventsFrom(eventSnapshots);
    const newEvent: MembershipEvent = {
      id: eventId,
      kind: args.kind,
      boundary: args.boundary,
      occurredAtMs: args.occurredAt.toMillis(),
    };
    const allEvents = [...existingEvents, newEvent].sort((a, b) =>
      a.occurredAtMs - b.occurredAtMs || a.id.localeCompare(b.id));
    if (baselineFromCompatibility) {
      const firstJoin = allEvents
        .filter((event) => event.kind === 'join')
        .sort((a, b) => a.occurredAtMs - b.occurredAtMs)[0];
      const firstLeave = allEvents
        .filter((event) => event.kind === 'leave')
        .sort((a, b) => a.occurredAtMs - b.occurredAtMs)[0];
      // Firestore does not order triggers. If an earlier join event arrives
      // after its leave event, the provisional legacy [0, leave] baseline
      // must be removed and the real event pair becomes authoritative.
      if (firstJoin && firstLeave &&
          firstJoin.occurredAtMs <= firstLeave.occurredAtMs) {
        baseline = [];
        baselineFromCompatibility = false;
      }
    }
    // Fold the oldest stored events into the durable period baseline. The new
    // event always remains in the recent window so its document continues to
    // be an idempotency marker for normal trigger retries.
    const compactCount = Math.max(
      0,
      existingEvents.length + 1 - MAX_MEMBERSHIP_EVENT_WINDOW,
    );
    const proposedCompactedEvents = [...existingEvents]
      .sort((a, b) =>
        a.occurredAtMs - b.occurredAtMs || a.id.localeCompare(b.id))
      .slice(0, compactCount);
    const proposedCutoff = proposedCompactedEvents.length > 0
      ? proposedCompactedEvents[proposedCompactedEvents.length - 1]
      : null;
    const newEventSortsBeforeCutoff = proposedCutoff != null && (
      newEvent.occurredAtMs < proposedCutoff.occurredAtMs ||
      (
        newEvent.occurredAtMs === proposedCutoff.occurredAtMs &&
        newEvent.id.localeCompare(proposedCutoff.id) <= 0
      )
    );
    // Firestore triggers can arrive out of order. If this event belongs before
    // the proposed baseline cutoff, retain the complete temporary window so it
    // can be rebuilt in chronological order on the next normal transition.
    const compactedEvents = eventWindowTruncated || newEventSortsBeforeCutoff
      ? []
      : proposedCompactedEvents;
    const compactedIds = new Set(compactedEvents.map((event) => event.id));
    if (compactedEvents.length > 0) {
      baseline = rebuildPeriods(baseline, compactedEvents);
      baselineFromCompatibility = false;
    }
    const recentEvents = [
      ...existingEvents.filter((event) => !compactedIds.has(event.id)),
      newEvent,
    ];
    const periods = rebuildPeriods(baseline, recentEvents);
    const isCurrentlyActive = uniqueStrings(room.get('participantIds'))
      .includes(args.userId);
    const latest = periods.length > 0 ? periods[periods.length - 1] : null;
    const previousRead = nonNegativeInteger(memberData.lastReadSequence);
    const nextRead = args.kind === 'join'
      ? Math.max(previousRead, args.boundary)
      : previousRead;
    const latestJoin = [...allEvents]
      .reverse()
      .find((event) => event.kind === 'join');
    const latestLeave = [...allEvents]
      .reverse()
      .find((event) => event.kind === 'leave');
    const joinedAt = latestJoin
      ? Timestamp.fromMillis(latestJoin.occurredAtMs)
      : memberData.joinedAt ?? args.occurredAt;
    const leftAt = isCurrentlyActive
      ? null
      : latestLeave
        ? Timestamp.fromMillis(latestLeave.occurredAtMs)
        : memberData.leftAt ?? args.occurredAt;

    transaction.set(eventRef, {
      eventId: args.sourceEventId,
      kind: args.kind,
      boundary: args.boundary,
      occurredAt: args.occurredAt,
      createdAt: FieldValue.serverTimestamp(),
    });
    compactedEvents.forEach((event) => {
      transaction.delete(events.doc(event.id));
    });
    transaction.set(memberRef, {
      userId: args.userId,
      status: isCurrentlyActive ? 'active' : 'left',
      joinedAfterSequence: latest?.joinedAfterSequence ?? args.boundary,
      leftAfterSequence: isCurrentlyActive
        ? null
        : latest?.leftAfterSequence ?? args.boundary,
      lastReadSequence: nextRead,
      lastReadAt: nextRead > previousRead
        ? args.occurredAt
        : memberData.lastReadAt ?? args.occurredAt,
      joinedAt,
      leftAt,
      ...(!eventWindowTruncated ? {
        baselinePeriods: baseline,
        baselineFromCompatibility,
        membershipEventWindowVersion: 1,
        baselineAssumedLegacy: FieldValue.delete(),
      } : {}),
      periods,
      membershipUpdatedAt: FieldValue.serverTimestamp(),
    }, {merge: true});
  });
}

async function userDisplayName(userId: string): Promise<string> {
  try {
    const user = await db().collection(USERS).doc(userId).get();
    return boundedString(
      user.get('nickname') ?? user.get('name') ?? 'Someone',
      80,
    ) || 'Someone';
  } catch (_) {
    return 'Someone';
  }
}

async function createSystemMessage(args: {
  roomRef: FirebaseFirestore.DocumentReference;
  sourceEventId: string;
  discriminator: string;
  text: string;
  metadata: Data;
}): Promise<void> {
  const eventKey = args.sourceEventId + ':' + args.discriminator;
  const markerId = eventDocumentId('system-message', eventKey);
  const markerRef = db().collection(FUNCTION_EVENTS).doc(markerId);
  const messageId = 'system_' + markerId.slice(0, 32);
  const messageRef = args.roomRef.collection('messages').doc(messageId);
  const outcome = await db().runTransaction(async (transaction) => {
    const [marker, existingMessage, room] = await transaction.getAll(
      markerRef,
      messageRef,
      args.roomRef,
    );
    if (marker.exists) return 'skipped';
    if (!room.exists) return 'skipped';
    if (existingMessage.exists) {
      const existing = existingMessage.data() ?? {};
      const matchesEvent = stringValue(existing.type) === 'system' &&
        stringValue(existing.chatId) === args.roomRef.id &&
        stringValue(existing.eventId) === eventKey;
      // The deterministic message document outlives its TTL marker. Recover
      // that marker without incrementing the room sequence or overwriting the
      // historical message when an old Firestore event is replayed.
      transaction.create(markerRef, {
        type: matchesEvent
          ? 'snack_chat_system_message'
          : 'snack_chat_system_message_conflict',
        sourceEventId: args.sourceEventId,
        discriminator: args.discriminator,
        roomId: args.roomRef.id,
        messageId,
        recoveredFromMessage: matchesEvent,
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: eventExpiry(),
      });
      return matchesEvent ? 'existing' : 'conflict';
    }
    const now = nextRoomMessageTimestamp(room);
    const sequence = nonNegativeInteger(room.get('lastMessageSequence')) + 1;
    transaction.create(messageRef, {
      senderId: '',
      messageScope: 'snack_chat',
      chatId: args.roomRef.id,
      type: 'system',
      text: boundedString(args.text, 500),
      createdAt: now,
      sequence,
      recipientIds: [],
      readBy: [],
      isDeleted: false,
      linkPreviewRemoved: true,
      reactionCounts: {},
      eventId: eventKey,
      metadata: {
        ...args.metadata,
        eventId: eventKey,
      },
    });
    transaction.update(args.roomRef, {
      lastMessage: boundedString(args.text, 500),
      lastMessageId: messageId,
      lastMessageTime: now,
      lastMessageSenderId: '',
      lastMessageType: 'system',
      lastMessageExpiresAt: FieldValue.delete(),
      lastMessageSequence: sequence,
      updatedAt: now,
    });
    transaction.create(markerRef, {
      type: 'snack_chat_system_message',
      sourceEventId: args.sourceEventId,
      discriminator: args.discriminator,
      roomId: args.roomRef.id,
      messageId,
      createdAt: now,
      expiresAt: eventExpiry(),
    });
    return 'created';
  });
  if (outcome === 'conflict') {
    console.error(
      'Snack Chat system-message id conflict; existing message preserved.',
      {roomId: args.roomRef.id, messageId, eventKey},
    );
  }
}

/** Atomically emits one poll-closed system message and marks its source. */
async function closeExpiredPoll(
  pollDocument: FirebaseFirestore.QueryDocumentSnapshot,
  observedNow: Timestamp,
): Promise<boolean> {
  const roomRef = pollDocument.ref.parent.parent;
  if (!roomRef || roomRef.parent.id !== SNACK_CHATS) return false;
  const roomId = roomRef.id;
  const pollMessageId = pollDocument.id;
  const eventKey = 'poll-close:' + roomId + ':' + pollMessageId;
  const markerId = eventDocumentId('system-message', eventKey);
  const markerRef = db().collection(FUNCTION_EVENTS).doc(markerId);
  const systemMessageId = 'system_' + markerId.slice(0, 32);
  const systemMessageRef = roomRef.collection('messages')
    .doc(systemMessageId);

  return db().runTransaction(async (transaction) => {
    const marker = await transaction.get(markerRef);
    const pollMessage = await transaction.get(pollDocument.ref);
    if (!pollMessage.exists) return false;
    const message = pollMessage.data() ?? {};

    // A very late retry of the message-created trigger must never make an
    // already-closed poll look pending again. If the close marker committed,
    // repair a missing/null lifecycle timestamp from that durable marker.
    if (marker.exists) {
      if (stringValue(message.type) === 'poll' &&
          !(message.pollCloseNotifiedAt instanceof Timestamp)) {
        const markerCreatedAt = marker.get('createdAt');
        transaction.update(pollDocument.ref, {
          pollCloseNotifiedAt:
            markerCreatedAt instanceof Timestamp
              ? markerCreatedAt
              : observedNow,
        });
      }
      return false;
    }

    const room = await transaction.get(roomRef);
    if (!room.exists) return false;
    const poll = objectValue(message.poll);
    const closesAtMillis = timestampMillis(poll.closesAt);
    if (stringValue(message.type) !== 'poll' ||
        closesAtMillis <= 0 ||
        closesAtMillis > observedNow.toMillis() ||
        message.pollCloseNotifiedAt != null) {
      return false;
    }

    const question = boundedString(
      poll.question ?? message.text ?? 'Poll',
      160,
    ) || 'Poll';
    const text = 'Poll ended: ' + question;
    const sequence = nonNegativeInteger(room.get('lastMessageSequence')) + 1;
    const now = nextRoomMessageTimestamp(room);
    transaction.create(systemMessageRef, {
      senderId: '',
      messageScope: 'snack_chat',
      chatId: roomId,
      type: 'system',
      text,
      createdAt: now,
      sequence,
      recipientIds: [],
      readBy: [],
      isDeleted: false,
      linkPreviewRemoved: true,
      reactionCounts: {},
      eventId: eventKey,
      metadata: {
        systemType: 'poll_closed',
        pollMessageId,
        question,
        eventId: eventKey,
      },
    });
    transaction.update(roomRef, {
      lastMessage: text,
      lastMessageId: systemMessageId,
      lastMessageTime: now,
      lastMessageSenderId: '',
      lastMessageType: 'system',
      lastMessageExpiresAt: FieldValue.delete(),
      lastMessageSequence: sequence,
      updatedAt: now,
    });
    transaction.update(pollDocument.ref, {pollCloseNotifiedAt: now});
    transaction.create(markerRef, {
      type: 'snack_chat_system_message',
      sourceEventId: eventKey,
      discriminator: 'poll-closed',
      roomId,
      messageId: systemMessageId,
      pollMessageId,
      createdAt: now,
      expiresAt: eventExpiry(),
    });
    return true;
  });
}

function contextTimestamp(raw: string): Timestamp {
  const millis = Date.parse(raw);
  return Timestamp.fromMillis(
    Number.isFinite(millis) ? millis : Date.now(),
  );
}

/**
 * Room membership is materialized server-side. On creation this initializes
 * every participant; later diffs append join/leave periods and emit one
 * deterministic system message per event.
 */
export const onSnackChatRoomWrittenSecure = functions
  .runWith({
    timeoutSeconds: 300,
    memory: '512MB',
    failurePolicy: true,
  })
  .firestore.document('snack_chats/{snackChatId}')
  .onWrite(async (change, context) => {
    if (!change.after.exists) return null;
    const roomRef = change.after.ref;
    const after = change.after.data() ?? {};
    const occurredAt = contextTimestamp(context.timestamp);
    const afterParticipants = new Set(uniqueStrings(after.participantIds));

    if (!change.before.exists) {
      await runWithConcurrency(
        Array.from(afterParticipants).sort(),
        8,
        (userId) => recordMembershipEvent({
          roomRef,
          userId,
          kind: 'join',
          boundary: 0,
          sourceEventId: context.eventId,
          occurredAt,
        }),
      );
      return null;
    }

    const before = change.before.data() ?? {};
    const beforeParticipants = new Set(uniqueStrings(before.participantIds));
    const added = Array.from(afterParticipants)
      .filter((userId) => !beforeParticipants.has(userId))
      .sort();
    const removed = Array.from(beforeParticipants)
      .filter((userId) => !afterParticipants.has(userId))
      .sort();
    const boundary = nonNegativeInteger(after.lastMessageSequence);
    const membershipChanges: Array<{
      userId: string;
      kind: 'join' | 'leave';
    }> = [
      ...added.map((userId) => ({userId, kind: 'join' as const})),
      ...removed.map((userId) => ({userId, kind: 'leave' as const})),
    ];

    await runWithConcurrency(membershipChanges, 8, (membership) =>
      recordMembershipEvent({
        roomRef,
        userId: membership.userId,
        kind: membership.kind,
        boundary,
        sourceEventId: context.eventId,
        occurredAt,
      }),
    );

    await runWithConcurrency(membershipChanges, 4, async (membership) => {
      const name = await userDisplayName(membership.userId);
      const joined = membership.kind === 'join';
      await createSystemMessage({
        roomRef,
        sourceEventId: context.eventId,
        discriminator: membership.kind + ':' + membership.userId,
        text: name + (joined
          ? ' joined the Snack Chat.'
          : ' left the Snack Chat.'),
        metadata: {
          systemType: joined ? 'member_joined' : 'member_left',
          userId: membership.userId,
          userName: name,
        },
      });
    });

    const beforeTitle = boundedString(before.title, 40);
    const afterTitle = boundedString(after.title, 40);
    if (beforeTitle !== afterTitle && afterTitle) {
      await createSystemMessage({
        roomRef,
        sourceEventId: context.eventId,
        discriminator: 'title',
        text: 'The Snack Chat name changed to "' + afterTitle + '".',
        metadata: {
          systemType: 'title_changed',
          oldTitle: beforeTitle,
          newTitle: afterTitle,
        },
      });
    }
    return null;
  });

function sequenceIsInMembership(data: Data, sequence: number): boolean {
  let periods = periodsFrom(data.periods);
  if (periods.length === 0 &&
      Object.prototype.hasOwnProperty.call(data, 'joinedAfterSequence')) {
    const joinedAfterSequence = nonNegativeInteger(data.joinedAfterSequence);
    const leftAfterSequence = data.leftAfterSequence == null
      ? null
      : nonNegativeInteger(data.leftAfterSequence);
    periods = [{joinedAfterSequence, leftAfterSequence}];
  }
  if (periods.length === 0) return true;
  return periods.some((period) =>
    sequence > period.joinedAfterSequence &&
    (period.leftAfterSequence == null ||
      sequence <= period.leftAfterSequence));
}

function normalizedCountMap(value: unknown): Record<string, number> {
  const raw = objectValue(value);
  const result: Record<string, number> = {};
  for (const [key, count] of Object.entries(raw)) {
    const normalizedKey = stringValue(key);
    if (!normalizedKey) continue;
    result[normalizedKey] = nonNegativeInteger(count);
  }
  return result;
}

async function applySnackChatUnreadOnce(args: {
  roomRef: FirebaseFirestore.DocumentReference;
  message: Data;
  eventId: string;
  messageId: string;
}): Promise<{
  eventRef: FirebaseFirestore.DocumentReference;
  recipientIds: string[];
}> {
  const markerId = eventDocumentId('message-created', args.eventId);
  const eventRef = db().collection(FUNCTION_EVENTS).doc(markerId);
  const messageRef = args.roomRef.collection('messages').doc(args.messageId);
  const senderId = stringValue(args.message.senderId);
  const sequence = nonNegativeInteger(args.message.sequence);
  const hasCanonicalRecipientSnapshot =
    stringValue(args.message.messageScope) === 'snack_chat' &&
    stringValue(args.message.chatId) === args.roomRef.id &&
    Array.isArray(args.message.recipientIds);
  const frozenRecipients = uniqueStrings(args.message.recipientIds)
    .filter((userId) => userId !== senderId);

  const pushRecipientIds = await db().runTransaction(async (transaction) => {
    const marker = await transaction.get(eventRef);
    if (marker.exists) {
      const delivered = uniqueStrings(marker.get('deliveryRecipientIds'));
      const pushRecipients = Array.isArray(marker.get('pushRecipientIds'))
        ? uniqueStrings(marker.get('pushRecipientIds'))
        // Markers written before this split used the delivery list for pushes.
        : delivered;
      // Repair messages processed before deliveryRecipientIds was
      // materialized. The marker is the immutable source of truth.
      transaction.update(messageRef, {deliveryRecipientIds: delivered});
      return pushRecipients;
    }
    const room = await transaction.get(args.roomRef);
    if (!room.exists || !senderId || sequence <= 0) {
      transaction.create(eventRef, {
        type: 'snack_chat_message_created',
        roomId: args.roomRef.id,
        messageId: args.messageId,
        sourceEventId: args.eventId,
        deliveryRecipientIds: [],
        pushRecipientIds: [],
        pushAttemptedRecipientIds: [],
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: eventExpiry(),
      });
      transaction.update(messageRef, {deliveryRecipientIds: []});
      return [];
    }

    const currentParticipants = uniqueStrings(room.get('participantIds'));
    const currentSet = new Set(currentParticipants);
    const candidates = (hasCanonicalRecipientSnapshot
      ? frozenRecipients
      : currentParticipants.filter((userId) => userId !== senderId))
      .filter((userId) => userId !== senderId);
    const memberRefs = candidates.map((userId) =>
      args.roomRef.collection('members').doc(userId));
    const userRefs = candidates.map((userId) =>
      db().collection(USERS).doc(userId));
    const blockRefs: FirebaseFirestore.DocumentReference[] = [];
    for (const userId of candidates) {
      blockRefs.push(
        db().collection(BLOCKS).doc(senderId + '_' + userId),
        db().collection(BLOCKS).doc(userId + '_' + senderId),
      );
    }
    const memberDocs = memberRefs.length > 0
      ? await transaction.getAll(...memberRefs)
      : [];
    const userDocs = userRefs.length > 0
      ? await transaction.getAll(...userRefs)
      : [];
    const blockDocs = blockRefs.length > 0
      ? await transaction.getAll(...blockRefs)
      : [];

    const deliveryRecipients: string[] = [];
    const unreadRecipients: string[] = [];
    candidates.forEach((userId, index) => {
      const member = memberDocs[index];
      const user = userDocs[index];
      if (!user?.exists || !activeUserData(user.data() ?? {})) return;
      if (blockDocs[index * 2]?.exists || blockDocs[index * 2 + 1]?.exists) {
        return;
      }
      const memberData = member?.data() ?? {};
      // Canonical recipientIds are the immutable send-time audience. A user
      // who leaves before this trigger runs still counts in the historical
      // read-receipt denominator, but no longer receives unread/push updates.
      if (!hasCanonicalRecipientSnapshot &&
          !sequenceIsInMembership(memberData, sequence)) {
        return;
      }
      deliveryRecipients.push(userId);
      if (!currentSet.has(userId) ||
          nonNegativeInteger(memberData.lastReadSequence) >= sequence) {
        return;
      }
      unreadRecipients.push(userId);
    });

    const unreadBefore = normalizedCountMap(room.get('unreadCount'));
    const unreadAfter: Record<string, number> = {};
    for (const participantId of currentParticipants) {
      unreadAfter[participantId] = unreadBefore[participantId] ?? 0;
    }
    for (const recipientId of unreadRecipients) {
      unreadAfter[recipientId] = (unreadAfter[recipientId] ?? 0) + 1;
    }
    const roomUpdate: Data = {};
    if (unreadRecipients.length > 0) roomUpdate.unreadCount = unreadAfter;
    const messageCreatedAtMillis = timestampMillis(args.message.createdAt);
    if (Number(room.get('activeDurationHours')) === 24 &&
        messageCreatedAtMillis > 0) {
      const nextExpiresAtMillis =
        messageCreatedAtMillis + 24 * 60 * 60 * 1000;
      if (nextExpiresAtMillis > timestampMillis(room.get('expiresAt'))) {
        roomUpdate.expiresAt = Timestamp.fromMillis(
          nextExpiresAtMillis,
        );
      }
    }
    if (Object.keys(roomUpdate).length > 0) {
      transaction.update(args.roomRef, {
        ...roomUpdate,
        updatedAt: FieldValue.serverTimestamp(),
      });
    }
    transaction.update(messageRef, {
      deliveryRecipientIds: deliveryRecipients,
    });
    transaction.create(eventRef, {
      type: 'snack_chat_message_created',
      roomId: args.roomRef.id,
      messageId: args.messageId,
      sourceEventId: args.eventId,
      sequence,
      senderId,
      deliveryRecipientIds: deliveryRecipients,
      pushRecipientIds: unreadRecipients,
      pushAttemptedRecipientIds: [],
      createdAt: FieldValue.serverTimestamp(),
      expiresAt: eventExpiry(),
    });
    return unreadRecipients;
  });
  return {eventRef, recipientIds: pushRecipientIds};
}

async function pushTokensOwnedByUser(
  userId: string,
  rawCandidates: unknown[],
): Promise<string[]> {
  const candidates = Array.from(new Set(rawCandidates
    .map(stringValue)
    .filter((token) => token.length > 0 && token.length <= 4096)))
    .slice(0, MAX_PUSH_TOKENS_PER_USER);
  if (candidates.length === 0) return [];
  try {
    const registry = await db().getAll(...candidates.map((token) =>
      db().collection('fcm_tokens').doc(token)));
    const result = new Set<string>();
    const missing: string[] = [];
    candidates.forEach((token, index) => {
      const owner = registry[index];
      if (!owner.exists) {
        missing.push(token);
      } else if (stringValue(owner.get('userId')) === userId) {
        result.add(token);
      }
    });
    for (const token of missing) {
      const [arrayOwners, singleOwners] = await Promise.all([
        db().collection(USERS)
          .where('fcmTokens', 'array-contains', token).limit(3).get(),
        db().collection(USERS)
          .where('fcmToken', '==', token).limit(3).get(),
      ]);
      const owners = new Set<string>();
      arrayOwners.docs.forEach((document) => owners.add(document.id));
      singleOwners.docs.forEach((document) => owners.add(document.id));
      if (owners.size === 1 && owners.has(userId)) result.add(token);
    }
    return candidates.filter((token) => result.has(token));
  } catch (error) {
    console.warn('Snack Chat token ownership verification failed.', error);
    return [];
  }
}

async function hasBlockBetween(userA: string, userB: string): Promise<boolean> {
  const documents = await db().getAll(
    db().collection(BLOCKS).doc(userA + '_' + userB),
    db().collection(BLOCKS).doc(userB + '_' + userA),
  );
  return documents.some((document) => document.exists);
}

async function claimPushAttempt(
  eventRef: FirebaseFirestore.DocumentReference,
  recipientId: string,
): Promise<boolean> {
  return db().runTransaction(async (transaction) => {
    const event = await transaction.get(eventRef);
    if (!event.exists) return false;
    const attempted = uniqueStrings(event.get('pushAttemptedRecipientIds'));
    if (attempted.includes(recipientId)) return false;
    transaction.update(eventRef, {
      pushAttemptedRecipientIds:
        FieldValue.arrayUnion(recipientId),
      lastPushAttemptAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
}

function snackChatVisibleForUser(room: Data, userId: string): boolean {
  const policyStart = Date.UTC(2026, 6, 23, 15, 0, 0, 0);
  const createdAt = timestampMillis(room.createdAt);
  if (createdAt <= 0 || createdAt < policyStart) return false;
  if (Number(room.activeDurationHours) === 0) return true;
  const expiresAt = timestampMillis(room.expiresAt);
  if (expiresAt <= 0 || Date.now() < expiresAt) return true;
  return uniqueStrings(room.favoriteUserIds).includes(userId) ||
    (room.isFavorited === true && stringValue(room.creatorId) === userId);
}

async function snackChatUnreadTotal(userId: string): Promise<number> {
  const rooms = await db().collection(SNACK_CHATS)
    .where('participantIds', 'array-contains', userId).get();
  let result = 0;
  for (const room of rooms.docs) {
    const data = room.data();
    if (!snackChatVisibleForUser(data, userId)) continue;
    result += nonNegativeInteger(objectValue(data.unreadCount)[userId]);
  }
  return result;
}

async function cleanInvalidPushTokens(
  userId: string,
  user: Data,
  tokens: string[],
): Promise<void> {
  if (tokens.length === 0) return;
  const userUpdate: Data = {
    fcmTokens: FieldValue.arrayRemove(...tokens),
  };
  if (tokens.includes(stringValue(user.fcmToken))) {
    userUpdate.fcmToken = FieldValue.delete();
  }
  await db().collection(USERS).doc(userId).set(userUpdate, {merge: true});
  const batch = db().batch();
  tokens.forEach((token) =>
    batch.delete(db().collection('fcm_tokens').doc(token)));
  await batch.commit();
}

async function sendSnackChatPush(args: {
  roomRef: FirebaseFirestore.DocumentReference;
  eventRef: FirebaseFirestore.DocumentReference;
  recipientId: string;
  senderId: string;
  senderName: string;
  message: Data;
}): Promise<void> {
  try {
    const [room, recipient, blocked] = await Promise.all([
      args.roomRef.get(),
      db().collection(USERS).doc(args.recipientId).get(),
      hasBlockBetween(args.senderId, args.recipientId),
    ]);
    const roomData = room.data() ?? {};
    const userData = recipient.data() ?? {};
    if (!room.exists || !recipient.exists || !activeUserData(userData) ||
        blocked ||
        !uniqueStrings(roomData.participantIds).includes(args.recipientId) ||
        uniqueStrings(userData.mutedSnackChatIds).includes(args.roomRef.id)) {
      return;
    }
    const tokens = await pushTokensOwnedByUser(args.recipientId, [
      userData.fcmToken,
      ...(Array.isArray(userData.fcmTokens) ? userData.fcmTokens : []),
    ]);
    if (tokens.length === 0) return;
    // Claim immediately before FCM. Retried Firestore events cannot send a
    // duplicate notification; a process crash favors at-most-once delivery.
    if (!await claimPushAttempt(args.eventRef, args.recipientId)) return;

    const messageType = stringValue(args.message.type);
    const rawText = boundedString(args.message.text, 100);
    const preview = messageType === 'image'
      ? (rawText || '📷 Photo')
      : messageType === 'file'
        ? '📎 ' + (boundedString(args.message.originalFileName, 80) || 'File')
      : messageType === 'poll'
        ? '📊 ' + (rawText || 'Poll')
        : (rawText || 'Message');
    const roomTitle = boundedString(roomData.title, 80) || 'Snack Chat';
    const language = stringValue(
      userData.preferredLanguage ?? userData.locale ?? userData.language,
    ).toLowerCase();
    const isKorean = !language.startsWith('en');
    const body = args.senderName + ': ' + preview;
    let badge: number | null = null;
    try {
      badge = nonNegativeInteger(userData.notificationUnreadTotal) +
        nonNegativeInteger(userData.dmUnreadTotal) +
        await snackChatUnreadTotal(args.recipientId);
    } catch (error) {
      console.warn('Snack Chat badge calculation failed.', error);
    }

    const invalid: string[] = [];
    for (let offset = 0; offset < tokens.length; offset += 500) {
      const chunk = tokens.slice(offset, offset + 500);
      const result = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        notification: {title: roomTitle, body},
        data: {
          type: 'snack_chat_message',
          recipientUserId: args.recipientId,
          snackChatId: args.roomRef.id,
          senderId: args.senderId,
          senderName: args.senderName,
          roomTitle,
          ...(badge == null ? {} : {badge: String(badge)}),
          language: isKorean ? 'ko' : 'en',
        },
        apns: {
          headers: {
            'apns-push-type': 'alert',
            'apns-priority': '10',
          },
          payload: {
            aps: {
              sound: 'default',
              ...(badge == null ? {} : {badge}),
            },
          },
        },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'high_importance_channel',
            ...(badge == null ? {} : {notificationCount: badge}),
          },
        },
      });
      result.responses.forEach((response, index) => {
        if (response.success) return;
        const code = response.error?.code ?? '';
        if (code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token') {
          invalid.push(chunk[index]);
        }
      });
    }
    await cleanInvalidPushTokens(args.recipientId, userData, invalid);
  } catch (error) {
    console.error(
      'Snack Chat push failed for recipient=' + args.recipientId,
      error,
    );
  }
}

async function runWithConcurrency<T>(
  values: T[],
  limit: number,
  task: (value: T) => Promise<void>,
): Promise<void> {
  let cursor = 0;
  async function worker(): Promise<void> {
    while (cursor < values.length) {
      const index = cursor;
      cursor += 1;
      await task(values[index]);
    }
  }
  const count = Math.min(Math.max(1, limit), values.length);
  await Promise.all(Array.from({length: count}, () => worker()));
}

/**
 * Applies unread counters and push delivery once per Firestore event. System
 * messages intentionally bypass both behaviors.
 */
export const onSnackChatMessageCreatedSecure = functions
  .runWith({
    timeoutSeconds: 180,
    memory: '512MB',
    failurePolicy: true,
  })
  .firestore
  .document('snack_chats/{snackChatId}/messages/{messageId}')
  .onCreate(async (snapshot, context) => {
    const message = snapshot.data() ?? {};
    if (stringValue(message.type) === 'system') return null;
    const senderId = stringValue(message.senderId);
    if (!senderId) return null;
    const roomRef = db().collection(SNACK_CHATS)
      .doc(stringValue(context.params.snackChatId));
    if (stringValue(message.type) === 'poll' &&
        timestampMillis(objectValue(message.poll).closesAt) > 0) {
      // Read current state inside a transaction. The onCreate snapshot never
      // changes across retries, so checking it directly could overwrite an
      // already-committed close timestamp with null on a late retry.
      await db().runTransaction(async (transaction) => {
        const current = await transaction.get(snapshot.ref);
        if (!current.exists) return;
        const currentData = current.data() ?? {};
        if (stringValue(currentData.type) !== 'poll' ||
            timestampMillis(objectValue(currentData.poll).closesAt) <= 0 ||
            Object.prototype.hasOwnProperty.call(
              currentData,
              'pollCloseNotifiedAt',
            )) {
          return;
        }
        // The explicit null makes the deadline query selective; clients cannot
        // author or later mutate this server-owned lifecycle field.
        transaction.update(snapshot.ref, {pollCloseNotifiedAt: null});
      });
    }
    const applied = await applySnackChatUnreadOnce({
      roomRef,
      message,
      eventId: context.eventId,
      messageId: stringValue(context.params.messageId),
    });
    let senderName = boundedString(message.senderName, 80);
    if (!senderName) senderName = await userDisplayName(senderId);
    if (stringValue(message.type) === 'poll') {
      const poll = objectValue(message.poll);
      const question = boundedString(
        poll.question ?? message.text ?? 'Poll',
        160,
      ) || 'Poll';
      await createSystemMessage({
        roomRef,
        sourceEventId: context.eventId,
        discriminator: 'poll-created:' + stringValue(context.params.messageId),
        text: senderName + ' created a poll: ' + question,
        metadata: {
          systemType: 'poll_created',
          userId: senderId,
          userName: senderName,
          pollMessageId: stringValue(context.params.messageId),
          question,
        },
      });
    }
    await runWithConcurrency(applied.recipientIds, 5, (recipientId) =>
      sendSnackChatPush({
        roomRef,
        eventRef: applied.eventRef,
        recipientId,
        senderId,
        senderName,
        message,
      }));
    return null;
  });

function expectedSnackChatFilePath(
  roomId: string,
  messageId: string,
  data: Data,
): string {
  const retentionMode = stringValue(data.retentionMode);
  const uploadId = stringValue(data.uploadId);
  const storagePath = stringValue(data.storagePath);
  if (!['temporary24h', 'permanent'].includes(retentionMode) ||
      !uploadId || !storagePath) {
    return '';
  }
  const prefix = [
    'snack_chat_files',
    retentionMode,
    roomId,
    messageId,
  ].join('/') + '/';
  return storagePath.startsWith(prefix) &&
      storagePath.slice(prefix.length).match(/^[A-Za-z0-9_-]{1,256}$/)
    ? storagePath
    : '';
}

/** Removes the private Storage object after TTL or a server-side hard delete. */
export const onSnackChatFileMessageDeleted = functions
  .runWith({timeoutSeconds: 60, memory: '256MB', failurePolicy: true})
  .firestore
  .document('snack_chats/{snackChatId}/messages/{messageId}')
  .onDelete(async (snapshot, context) => {
    const data = snapshot.data() ?? {};
    if (stringValue(data.type) !== 'file') return null;
    const storagePath = expectedSnackChatFilePath(
      stringValue(context.params.snackChatId),
      stringValue(context.params.messageId),
      data,
    );
    if (!storagePath) return null;
    await admin.storage().bucket().file(storagePath)
      .delete({ignoreNotFound: true});
    return null;
  });

/** A TTL-deleted unfinished job owns only an orphan object, never a message. */
export const onSnackChatFileUploadJobDeleted = functions
  .runWith({timeoutSeconds: 60, memory: '256MB', failurePolicy: true})
  .firestore
  .document('snack_chats/{snackChatId}/fileUploadJobs/{uploadId}')
  .onDelete(async (snapshot, context) => {
    const data = snapshot.data() ?? {};
    if (stringValue(data.status) === 'committed') return null;
    const messageId = stringValue(data.messageId);
    const storagePath = expectedSnackChatFilePath(
      stringValue(context.params.snackChatId),
      messageId,
      data,
    );
    if (!storagePath) return null;
    await admin.storage().bucket().file(storagePath)
      .delete({ignoreNotFound: true});
    return null;
  });

/**
 * Processes only the next bounded page of due polls. Normal load is notified
 * within the one-minute schedule interval; bursts above the page size drain
 * over subsequent invocations without an unbounded scan loop.
 */
export const notifyClosedSnackChatPolls = functions
  .runWith({
    timeoutSeconds: 300,
    memory: '512MB',
    failurePolicy: true,
  })
  .pubsub.schedule('* * * * *')
  .timeZone('UTC')
  .onRun(async () => {
    const observedNow = Timestamp.now();
    const canonicalDueQuery = db().collectionGroup('messages')
      .where('messageScope', '==', 'snack_chat')
      .where('type', '==', 'poll')
      .where('pollCloseNotifiedAt', '==', null)
      .where('poll.closesAt', '<=', observedNow)
      .orderBy('poll.closesAt', 'asc');
    const duePolls: FirebaseFirestore.QueryDocumentSnapshot[] = [];
    const canonicalPage = await canonicalDueQuery.limit(100).get();
    for (const document of canonicalPage.docs) {
      const roomRef = document.ref.parent.parent;
      if (roomRef?.parent.id === SNACK_CHATS &&
          stringValue(document.get('chatId')) === roomRef.id) {
        duePolls.push(document);
      }
    }

    // Transitional best effort for pre-discriminator Snack Chat polls. This
    // bounded legacy scan cannot starve the canonical query above and can be
    // removed after old 24-hour rooms have aged out.
    const legacyDueQuery = db().collectionGroup('messages')
      .where('type', '==', 'poll')
      .where('pollCloseNotifiedAt', '==', null)
      .where('poll.closesAt', '<=', observedNow)
      .orderBy('poll.closesAt', 'asc');
    const pageSize = 100;
    const maxScannedDocuments = 1000;
    let scannedDocuments = 0;
    let cursor: FirebaseFirestore.QueryDocumentSnapshot | null = null;

    while (duePolls.length < 100 &&
        scannedDocuments < maxScannedDocuments) {
      const remainingScan = maxScannedDocuments - scannedDocuments;
      const currentPageSize = Math.min(pageSize, remainingScan);
      let pageQuery = legacyDueQuery.limit(currentPageSize);
      if (cursor != null) pageQuery = pageQuery.startAfter(cursor);
      const page = await pageQuery.get();
      if (page.empty) break;
      scannedDocuments += page.size;
      cursor = page.docs[page.docs.length - 1];
      for (const document of page.docs) {
        if (stringValue(document.get('messageScope')) === 'snack_chat') {
          continue;
        }
        const roomRef = document.ref.parent.parent;
        if (roomRef?.parent.id === SNACK_CHATS) {
          duePolls.push(document);
          if (duePolls.length >= 100) break;
        }
      }
      if (page.size < currentPageSize) break;
    }
    let notified = 0;
    await runWithConcurrency(duePolls, 5, async (document) => {
      if (await closeExpiredPoll(document, observedNow)) notified += 1;
    });
    console.log(
      'Snack Chat closed poll notifications: selected=' +
      duePolls.length + ', scanned=' + scannedDocuments +
      ', notified=' + notified,
    );
    return null;
  });

/** Maintains list-view counts; participant-only detail reads remain on demand. */
export const onSnackChatReactionWritten = functions
  .runWith({
    timeoutSeconds: 60,
    memory: '256MB',
    failurePolicy: true,
  })
  .firestore
  .document(
    'snack_chats/{snackChatId}/messages/{messageId}/reactions/{userId}',
  )
  .onWrite(async (_change, context) => {
    const markerId = eventDocumentId('reaction-write', context.eventId);
    const markerRef = db().collection(FUNCTION_EVENTS).doc(markerId);
    const messageRef = db().collection(SNACK_CHATS)
      .doc(stringValue(context.params.snackChatId))
      .collection('messages')
      .doc(stringValue(context.params.messageId));
    await db().runTransaction(async (transaction) => {
      const marker = await transaction.get(markerRef);
      if (marker.exists) return;
      const message = await transaction.get(messageRef);
      if (message.exists) {
        // Firestore triggers are at-least-once and may arrive out of order.
        // Rebuilding from the authoritative per-user documents makes the
        // aggregate converge to the current state even after rapid changes.
        const reactions = await transaction.get(
          messageRef.collection('reactions'),
        );
        const counts: Record<string, number> = {};
        for (const reaction of reactions.docs) {
          const emoji = stringValue(reaction.get('emoji'));
          if (!ALLOWED_REACTIONS.has(emoji)) continue;
          counts[emoji] = (counts[emoji] ?? 0) + 1;
        }
        transaction.update(messageRef, {reactionCounts: counts});
      }
      transaction.create(markerRef, {
        type: 'snack_chat_reaction_write',
        sourceEventId: context.eventId,
        roomId: stringValue(context.params.snackChatId),
        messageId: stringValue(context.params.messageId),
        userId: stringValue(context.params.userId),
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: eventExpiry(),
      });
    });
    return null;
  });

/** Maintains poll aggregates while each participant can read only their vote. */
export const onSnackChatVoteWritten = functions
  .runWith({
    timeoutSeconds: 60,
    memory: '256MB',
    failurePolicy: true,
  })
  .firestore
  .document('snack_chats/{snackChatId}/messages/{messageId}/votes/{userId}')
  .onWrite(async (_change, context) => {
    const markerId = eventDocumentId('vote-write', context.eventId);
    const markerRef = db().collection(FUNCTION_EVENTS).doc(markerId);
    const messageRef = db().collection(SNACK_CHATS)
      .doc(stringValue(context.params.snackChatId))
      .collection('messages')
      .doc(stringValue(context.params.messageId));
    await db().runTransaction(async (transaction) => {
      const marker = await transaction.get(markerRef);
      if (marker.exists) return;
      const message = await transaction.get(messageRef);
      if (message.exists) {
        const messageData = message.data() ?? {};
        const poll = objectValue(messageData.poll);
        const allowed = new Set(uniqueStrings(poll.optionIds));
        if (stringValue(messageData.type) === 'poll' && allowed.size >= 2) {
          // As with reactions, recompute from the current vote documents so
          // a delayed older trigger cannot overwrite a newer selection.
          const votes = await transaction.get(messageRef.collection('votes'));
          const counts: Record<string, number> = {};
          allowed.forEach((optionId) => {
            counts[optionId] = 0;
          });
          let totalVoters = 0;
          for (const vote of votes.docs) {
            const selected = uniqueStrings(vote.get('optionIds'))
              .filter((optionId) => allowed.has(optionId));
            if (selected.length === 0) continue;
            totalVoters += 1;
            for (const optionId of selected) {
              counts[optionId] = (counts[optionId] ?? 0) + 1;
            }
          }
          transaction.update(messageRef, {
            poll: {...poll, voteCounts: counts, totalVoters},
          });
        }
      }
      transaction.create(markerRef, {
        type: 'snack_chat_vote_write',
        sourceEventId: context.eventId,
        roomId: stringValue(context.params.snackChatId),
        messageId: stringValue(context.params.messageId),
        userId: stringValue(context.params.userId),
        createdAt: FieldValue.serverTimestamp(),
        expiresAt: eventExpiry(),
      });
    });
    return null;
  });
