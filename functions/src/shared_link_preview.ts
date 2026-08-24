import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import * as https from 'https';

type YouTubeThumbnail = {
  url?: unknown;
};

type YouTubeSnippet = {
  title?: unknown;
  channelTitle?: unknown;
  publishedAt?: unknown;
  thumbnails?: Record<string, YouTubeThumbnail>;
};

type YouTubeApiItem = {
  snippet?: YouTubeSnippet;
};

type YouTubeLinkPreview = {
  provider: 'youtube';
  contentType: 'video';
  videoId: string;
  originalUrl: string;
  canonicalUrl: string;
  title: string;
  authorName: string;
  thumbnailUrl: string | null;
  aspectRatio: number;
  publishedAt: string | null;
  previewMode: 'image';
  previewStatus: 'ready';
};

type InstagramLinkPreview = {
  provider: 'instagram';
  contentType: 'post' | 'reel';
  shortcode: string;
  originalUrl: string;
  canonicalUrl: string;
  title: string;
  authorName: string;
  thumbnailUrl: string | null;
  aspectRatio: number;
  embedHtml: string;
  previewMode: 'embed' | 'image';
  previewStatus: 'ready';
};

type SharedLinkPreview = YouTubeLinkPreview | InstagramLinkPreview;

type ParsedSharedLink =
  | {provider: 'youtube'; originalUrl: string; videoId: string; canonicalUrl: string}
  | {
    provider: 'instagram';
    originalUrl: string;
    shortcode: string;
    contentType: 'post' | 'reel';
    canonicalUrl: string;
  };

const CACHE_COLLECTION = 'linkPreviewCache';
const CACHE_TTL_MS = 3 * 24 * 60 * 60 * 1000;
const INSTAGRAM_METADATA_VERSION = 2;
const REQUEST_TIMEOUT_MS = 5_000;
const MAX_RESPONSE_BYTES = 512 * 1024;
const META_GRAPH_API_VERSION = 'v25.0';
const INSTAGRAM_OEMBED_ENDPOINT =
  `https://graph.facebook.com/${META_GRAPH_API_VERSION}/instagram_oembed`;
const YOUTUBE_VIDEO_ID_PATTERN = /^[A-Za-z0-9_-]{11}$/;
const INSTAGRAM_SHORTCODE_PATTERN = /^[A-Za-z0-9_-]{3,100}$/;
const YOUTUBE_HOSTS = new Set([
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'youtu.be',
]);
const INSTAGRAM_HOSTS = new Set(['instagram.com', 'www.instagram.com']);

function callableError(
  code: functions.https.FunctionsErrorCode,
  reason: string,
  message: string,
): functions.https.HttpsError {
  return new functions.https.HttpsError(code, message, {reason});
}

function requireAuthenticatedUser(context: functions.https.CallableContext): void {
  if (!context.auth?.uid?.trim()) {
    throw callableError('unauthenticated', 'unauthenticated', 'Sign-in is required.');
  }
}

function requireUrl(data: unknown): string {
  const raw = data && typeof data === 'object'
    ? (data as Record<string, unknown>).url
    : null;
  if (typeof raw !== 'string') {
    throw callableError('invalid-argument', 'invalid-argument', 'A URL string is required.');
  }
  const value = raw.trim();
  if (!value || value.length > 2048) {
    throw callableError('invalid-argument', 'invalid-argument', 'A valid URL is required.');
  }
  return value;
}

function parseYouTubeUrl(value: string): {videoId: string; canonicalUrl: string} {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch (_) {
    throw callableError('invalid-argument', 'invalid-argument', 'Invalid URL.');
  }

  const hostname = parsed.hostname.toLowerCase().replace(/\.$/, '');
  if (
    parsed.protocol !== 'https:' ||
    parsed.username ||
    parsed.password ||
    parsed.port ||
    !YOUTUBE_HOSTS.has(hostname)
  ) {
    throw callableError('invalid-argument', 'unsupported-url', 'Unsupported URL.');
  }

  const pathSegments = parsed.pathname.split('/').filter(Boolean);
  let videoId = '';
  if (hostname === 'youtu.be') {
    videoId = pathSegments[0] ?? '';
  } else if (parsed.pathname === '/watch') {
    videoId = parsed.searchParams.get('v') ?? '';
  } else if (pathSegments[0] === 'shorts' || pathSegments[0] === 'live') {
    videoId = pathSegments[1] ?? '';
  }

  if (!YOUTUBE_VIDEO_ID_PATTERN.test(videoId)) {
    throw callableError(
      'invalid-argument',
      'invalid-youtube-url',
      'A valid YouTube video URL is required.',
    );
  }

  return {
    videoId,
    canonicalUrl: `https://www.youtube.com/watch?v=${videoId}`,
  };
}

function parseInstagramUrl(
  value: string,
): {shortcode: string; contentType: 'post' | 'reel'; canonicalUrl: string} {
  let parsed: URL;
  try {
    parsed = new URL(value);
  } catch (_) {
    throw callableError('invalid-argument', 'invalid-argument', 'Invalid URL.');
  }

  const hostname = parsed.hostname.toLowerCase().replace(/\.$/, '');
  if (
    !['http:', 'https:'].includes(parsed.protocol) ||
    parsed.username ||
    parsed.password ||
    parsed.port ||
    !INSTAGRAM_HOSTS.has(hostname)
  ) {
    throw callableError('invalid-argument', 'unsupported-url', 'Unsupported URL.');
  }

  const segments = parsed.pathname.split('/').filter(Boolean);
  const route = segments[0];
  const shortcode = segments[1] ?? '';
  if (
    segments.length !== 2 ||
    (route !== 'p' && route !== 'reel') ||
    !INSTAGRAM_SHORTCODE_PATTERN.test(shortcode)
  ) {
    throw callableError(
      'invalid-argument',
      'invalid-instagram-url',
      'A public Instagram post or reel URL is required.',
    );
  }

  const contentType = route === 'reel' ? 'reel' : 'post';
  return {
    shortcode,
    contentType,
    canonicalUrl: `https://www.instagram.com/${route}/${shortcode}/`,
  };
}

function parseSharedLink(value: string): ParsedSharedLink {
  let host = '';
  try {
    host = new URL(value).hostname.toLowerCase().replace(/\.$/, '');
  } catch (_) {
    throw callableError('invalid-argument', 'invalid-argument', 'Invalid URL.');
  }
  if (YOUTUBE_HOSTS.has(host)) {
    const parsed = parseYouTubeUrl(value);
    return {provider: 'youtube', originalUrl: value, ...parsed};
  }
  if (INSTAGRAM_HOSTS.has(host)) {
    const parsed = parseInstagramUrl(value);
    return {provider: 'instagram', originalUrl: value, ...parsed};
  }
  throw callableError('invalid-argument', 'unsupported-url', 'Unsupported URL.');
}

function fetchJson(url: URL, allowedHostname: string): Promise<Record<string, unknown>> {
  if (url.protocol !== 'https:' || url.hostname !== allowedHostname) {
    return Promise.reject(new Error('Unexpected metadata endpoint.'));
  }

  return new Promise((resolve, reject) => {
    const request = https.get(url, {headers: {Accept: 'application/json'}}, (response) => {
      const statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        response.resume();
        reject(new Error(`Metadata endpoint returned HTTP ${statusCode}.`));
        return;
      }

      const chunks: Buffer[] = [];
      let receivedBytes = 0;
      response.on('data', (chunk: Buffer) => {
        receivedBytes += chunk.length;
        if (receivedBytes > MAX_RESPONSE_BYTES) {
          request.destroy(new Error('Metadata response exceeded the size limit.'));
          return;
        }
        chunks.push(chunk);
      });
      response.on('end', () => {
        try {
          const decoded = JSON.parse(Buffer.concat(chunks).toString('utf8')) as unknown;
          if (!decoded || typeof decoded !== 'object' || Array.isArray(decoded)) {
            reject(new Error('Metadata endpoint returned an invalid payload.'));
            return;
          }
          resolve(decoded as Record<string, unknown>);
        } catch (error) {
          reject(error);
        }
      });
    });

    request.setTimeout(REQUEST_TIMEOUT_MS, () => {
      request.destroy(new Error('YouTube API request timed out.'));
    });
    request.on('error', reject);
  });
}

function fetchHtml(url: URL, allowedHostname: string): Promise<string> {
  if (url.protocol !== 'https:' || url.hostname !== allowedHostname) {
    return Promise.reject(new Error('Unexpected HTML metadata endpoint.'));
  }

  return new Promise((resolve, reject) => {
    const request = https.get(url, {
      headers: {
        Accept: 'text/html,application/xhtml+xml',
        'Accept-Language': 'ko-KR,ko;q=0.9,en;q=0.8',
        'User-Agent': 'Mozilla/5.0 (compatible; WefillingLinkPreview/1.0)',
      },
    }, (response) => {
      const statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 300) {
        response.resume();
        reject(new Error(`Instagram page returned HTTP ${statusCode}.`));
        return;
      }
      const contentType = (response.headers['content-type'] ?? '').toLowerCase();
      if (!contentType.includes('text/html')) {
        response.resume();
        reject(new Error('Instagram page did not return HTML.'));
        return;
      }

      const chunks: Buffer[] = [];
      let receivedBytes = 0;
      response.on('data', (chunk: Buffer) => {
        receivedBytes += chunk.length;
        if (receivedBytes > MAX_RESPONSE_BYTES) {
          request.destroy(new Error('Instagram page exceeded the size limit.'));
          return;
        }
        chunks.push(chunk);
      });
      response.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    });
    request.setTimeout(REQUEST_TIMEOUT_MS, () => {
      request.destroy(new Error('Instagram page request timed out.'));
    });
    request.on('error', reject);
  });
}

function thumbnailUrl(snippet: YouTubeSnippet): string | null {
  const thumbnails = snippet.thumbnails ?? {};
  for (const size of ['maxres', 'standard', 'high', 'medium', 'default']) {
    const raw = thumbnails[size]?.url;
    if (typeof raw !== 'string') continue;
    const value = raw.trim();
    if (value.startsWith('https://')) return value;
  }
  return null;
}

function stringValue(value: unknown, maxLength: number): string {
  return typeof value === 'string' ? value.trim().slice(0, maxLength) : '';
}

function decodeHtml(value: string): string {
  const named: Record<string, string> = {
    amp: '&', quot: '"', apos: '\'', lt: '<', gt: '>', nbsp: ' ',
  };
  return value
    .replace(/&#x([0-9a-f]+);?/gi, (_match, raw: string) =>
      String.fromCodePoint(parseInt(raw, 16)))
    .replace(/&#(\d+);?/g, (_match, raw: string) =>
      String.fromCodePoint(parseInt(raw, 10)))
    .replace(/&([a-z]+);/gi, (match, name: string) =>
      named[name.toLowerCase()] ?? match)
    .replace(/\\u0026/gi, '&')
    .replace(/\\\//g, '/')
    .replace(/\s+/g, ' ')
    .trim();
}

function tagAttributes(tag: string): Record<string, string> {
  const attributes: Record<string, string> = {};
  const pattern = /([^\s=/>]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>]+))/g;
  let match: RegExpExecArray | null;
  while ((match = pattern.exec(tag)) != null) {
    attributes[match[1].toLowerCase()] = match[2] ?? match[3] ?? match[4] ?? '';
  }
  return attributes;
}

function htmlMetadata(html: string): Map<string, string> {
  const metadata = new Map<string, string>();
  for (const match of html.matchAll(/<meta\b[^>]*>/gi)) {
    const attributes = tagAttributes(match[0]);
    const key = (attributes.property || attributes.name || '').toLowerCase();
    const content = decodeHtml(attributes.content ?? '');
    if (key && content && !metadata.has(key)) metadata.set(key, content);
  }
  return metadata;
}

function instagramImageUrl(value: unknown): string | null {
  const raw = optionalHttpsUrl(value);
  if (!raw) return null;
  const host = new URL(raw).hostname.toLowerCase().replace(/\.$/, '');
  const allowed = host === 'instagram.com' || host.endsWith('.instagram.com') ||
    host === 'cdninstagram.com' || host.endsWith('.cdninstagram.com') ||
    host === 'fbcdn.net' || host.endsWith('.fbcdn.net');
  return allowed ? raw : null;
}

function instagramImageFromHtml(html: string, metadata: Map<string, string>): string | null {
  for (const key of ['og:image', 'og:image:secure_url', 'twitter:image']) {
    const image = instagramImageUrl(metadata.get(key));
    if (image) return image;
  }
  for (const pattern of [
    /"display_url"\s*:\s*"([^"]+)"/i,
    /"thumbnail_src"\s*:\s*"([^"]+)"/i,
    /"thumbnail_url"\s*:\s*"([^"]+)"/i,
  ]) {
    const match = pattern.exec(html);
    const image = instagramImageUrl(match ? decodeHtml(match[1]) : '');
    if (image) return image;
  }
  return null;
}

function instagramCaptionFromEmbed(html: string): string {
  const candidates: string[] = [];
  for (const match of html.matchAll(/<p\b[^>]*>([\s\S]*?)<\/p>/gi)) {
    const value = decodeHtml(match[1].replace(/<[^>]+>/g, ' '));
    if (!value || /^A post shared by\b/i.test(value) ||
        /^View this post on Instagram/i.test(value)) continue;
    candidates.push(value);
  }
  return stringValue(candidates.sort((a, b) => b.length - a.length)[0], 300);
}

function instagramCaptionFromPage(metadata: Map<string, string>): string {
  const description = metadata.get('og:description') ??
    metadata.get('twitter:description') ?? '';
  const quoted = /:\s*["“]([\s\S]+?)["”]\.?$/.exec(description);
  const candidate = quoted?.[1] ?? description;
  if (/^(See Instagram|Instagram photos)/i.test(candidate)) return '';
  return stringValue(candidate, 300);
}

function instagramAuthorFromPage(metadata: Map<string, string>): string {
  const title = metadata.get('og:title') ?? metadata.get('twitter:title') ?? '';
  return stringValue(title.split(/\s+[•|]\s+Instagram/i)[0], 160);
}

function isoDate(value: unknown): string | null {
  if (typeof value !== 'string' || !value.trim()) return null;
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? null : date.toISOString();
}

function previewFromCache(
  data: FirebaseFirestore.DocumentData,
  originalUrl: string,
  videoId: string,
  canonicalUrl: string,
): YouTubeLinkPreview | null {
  const fetchedAt = data.fetchedAt;
  if (!(fetchedAt instanceof admin.firestore.Timestamp)) return null;
  if (Date.now() - fetchedAt.toMillis() > CACHE_TTL_MS) return null;
  if (data.provider !== 'youtube' || data.videoId !== videoId) return null;

  const title = stringValue(data.title, 300);
  const authorName = stringValue(data.authorName, 160);
  if (!title || !authorName) return null;

  return {
    provider: 'youtube',
    contentType: 'video',
    videoId,
    originalUrl,
    canonicalUrl,
    title,
    authorName,
    thumbnailUrl: typeof data.thumbnailUrl === 'string' && data.thumbnailUrl.startsWith('https://')
      ? data.thumbnailUrl
      : null,
    aspectRatio: 16 / 9,
    publishedAt: isoDate(data.publishedAt),
    previewMode: 'image',
    previewStatus: 'ready',
  };
}

async function readCachedPreview(
  originalUrl: string,
  videoId: string,
  canonicalUrl: string,
): Promise<YouTubeLinkPreview | null> {
  try {
    const snapshot = await admin.firestore()
      .collection(CACHE_COLLECTION)
      .doc(`youtube_${videoId}`)
      .get();
    return snapshot.exists
      ? previewFromCache(snapshot.data() ?? {}, originalUrl, videoId, canonicalUrl)
      : null;
  } catch (error) {
    functions.logger.warn('YouTube preview cache read failed.', {
      videoId,
      error: error instanceof Error ? error.message : 'unknown',
    });
    return null;
  }
}

async function fetchYouTubePreview(
  originalUrl: string,
  videoId: string,
  canonicalUrl: string,
): Promise<YouTubeLinkPreview> {
  const apiKey = (process.env.YOUTUBE_API_KEY ?? '').trim();
  if (!apiKey) {
    functions.logger.error('YOUTUBE_API_KEY is unavailable.');
    throw callableError('internal', 'internal', 'Link preview is temporarily unavailable.');
  }

  const endpoint = new URL('https://www.googleapis.com/youtube/v3/videos');
  endpoint.searchParams.set('part', 'snippet');
  endpoint.searchParams.set('id', videoId);
  endpoint.searchParams.set('key', apiKey);

  let response: Record<string, unknown>;
  try {
    response = await fetchJson(endpoint, 'www.googleapis.com');
  } catch (error) {
    functions.logger.error('YouTube Data API request failed.', {
      videoId,
      error: error instanceof Error ? error.message : 'unknown',
    });
    throw callableError(
      'unavailable',
      'youtube-api-error',
      'YouTube metadata is temporarily unavailable.',
    );
  }

  const items = response.items;
  if (!Array.isArray(items) || items.length === 0) {
    throw callableError('not-found', 'video-not-found', 'The YouTube video was not found.');
  }
  const item = items[0] as YouTubeApiItem;
  const snippet = item?.snippet;
  if (!snippet || typeof snippet !== 'object') {
    functions.logger.error('YouTube Data API response did not include a snippet.', {videoId});
    throw callableError('internal', 'internal', 'Invalid YouTube metadata response.');
  }

  const title = stringValue(snippet.title, 300);
  const authorName = stringValue(snippet.channelTitle, 160);
  if (!title || !authorName) {
    functions.logger.error('YouTube Data API snippet was incomplete.', {videoId});
    throw callableError('internal', 'internal', 'Invalid YouTube metadata response.');
  }

  return {
    provider: 'youtube',
    contentType: 'video',
    videoId,
    originalUrl,
    canonicalUrl,
    title,
    authorName,
    thumbnailUrl: thumbnailUrl(snippet),
    aspectRatio: 16 / 9,
    publishedAt: isoDate(snippet.publishedAt),
    previewMode: 'image',
    previewStatus: 'ready',
  };
}

async function writeYouTubePreviewCache(preview: YouTubeLinkPreview): Promise<void> {
  try {
    await admin.firestore()
      .collection(CACHE_COLLECTION)
      .doc(`youtube_${preview.videoId}`)
      .set({
        provider: preview.provider,
        videoId: preview.videoId,
        canonicalUrl: preview.canonicalUrl,
        title: preview.title,
        authorName: preview.authorName,
        thumbnailUrl: preview.thumbnailUrl,
        aspectRatio: preview.aspectRatio,
        publishedAt: preview.publishedAt,
        fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  } catch (error) {
    functions.logger.warn('YouTube preview cache write failed.', {
      videoId: preview.videoId,
      error: error instanceof Error ? error.message : 'unknown',
    });
  }
}

function instagramPreviewFromCache(
  data: FirebaseFirestore.DocumentData,
  originalUrl: string,
  shortcode: string,
  contentType: 'post' | 'reel',
  canonicalUrl: string,
): InstagramLinkPreview | null {
  const fetchedAt = data.fetchedAt;
  if (!(fetchedAt instanceof admin.firestore.Timestamp)) return null;
  if (Date.now() - fetchedAt.toMillis() > CACHE_TTL_MS) return null;
  if (data.provider !== 'instagram' || data.shortcode !== shortcode) return null;
  if (data.metadataVersion !== INSTAGRAM_METADATA_VERSION) return null;

  const embedHtml = stringValue(data.embedHtml, 100_000);
  const thumbnailUrl = instagramImageUrl(data.thumbnailUrl);
  const previewMode = data.previewMode === 'embed' &&
      embedHtml.includes('class="instagram-media"')
    ? 'embed'
    : (thumbnailUrl ? 'image' : null);
  if (!previewMode) return null;
  return {
    provider: 'instagram',
    contentType,
    shortcode,
    originalUrl,
    canonicalUrl,
    title: stringValue(data.title, 300) || 'Instagram에서 공유된 게시물',
    authorName: stringValue(data.authorName, 160),
    thumbnailUrl,
    aspectRatio: typeof data.aspectRatio === 'number' && data.aspectRatio > 0
      ? Math.min(2.4, Math.max(0.5, data.aspectRatio))
      : 1,
    embedHtml,
    previewMode,
    previewStatus: 'ready',
  };
}

async function readInstagramPreviewCache(
  originalUrl: string,
  shortcode: string,
  contentType: 'post' | 'reel',
  canonicalUrl: string,
): Promise<InstagramLinkPreview | null> {
  try {
    const snapshot = await admin.firestore()
      .collection(CACHE_COLLECTION)
      .doc(`instagram_${shortcode}`)
      .get();
    return snapshot.exists
      ? instagramPreviewFromCache(
        snapshot.data() ?? {},
        originalUrl,
        shortcode,
        contentType,
        canonicalUrl,
      )
      : null;
  } catch (error) {
    functions.logger.warn('Instagram preview cache read failed.', {
      shortcode,
      error: error instanceof Error ? error.message : 'unknown',
    });
    return null;
  }
}

function optionalHttpsUrl(value: unknown): string | null {
  const raw = stringValue(value, 2048);
  if (!raw) return null;
  try {
    const parsed = new URL(raw);
    return parsed.protocol === 'https:' && !parsed.username && !parsed.password
      ? raw
      : null;
  } catch (_) {
    return null;
  }
}

function instagramEmbedHtml(value: unknown): string {
  const html = stringValue(value, 100_000);
  if (!html || !html.includes('class="instagram-media"')) {
    throw callableError(
      'unavailable',
      'invalid-instagram-oembed',
      'Instagram did not return a usable embed.',
    );
  }
  // `omitscript=true` should already omit scripts. Strip them defensively so
  // the Flutter wrapper is the only place that loads Instagram's embed.js.
  return html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '').trim();
}

async function fetchInstagramPreview(
  originalUrl: string,
  shortcode: string,
  contentType: 'post' | 'reel',
  canonicalUrl: string,
): Promise<InstagramLinkPreview> {
  const endpoint = new URL(INSTAGRAM_OEMBED_ENDPOINT);
  endpoint.searchParams.set('url', canonicalUrl);
  endpoint.searchParams.set('omitscript', 'true');

  const embedPageUrl = new URL(`${canonicalUrl}embed/captioned/`);
  const [oEmbedResult, pageResult, embedPageResult] = await Promise.allSettled([
    fetchJson(endpoint, 'graph.facebook.com'),
    fetchHtml(new URL(canonicalUrl), 'www.instagram.com'),
    fetchHtml(embedPageUrl, 'www.instagram.com'),
  ]);

  const response = oEmbedResult.status === 'fulfilled' ? oEmbedResult.value : {};
  if (oEmbedResult.status === 'rejected') {
    functions.logger.warn('Instagram oEmbed request failed.', {
      shortcode,
      error: oEmbedResult.reason instanceof Error ? oEmbedResult.reason.message : 'unknown',
    });
  }

  const pageHtml = pageResult.status === 'fulfilled' ? pageResult.value : '';
  const embedPageHtml = embedPageResult.status === 'fulfilled' ? embedPageResult.value : '';
  const pageMetadata = htmlMetadata(pageHtml);
  const embedPageMetadata = htmlMetadata(embedPageHtml);
  const rawEmbedHtml = stringValue(response.html, 100_000);
  let safeEmbedHtml = '';
  if (rawEmbedHtml) {
    try {
      safeEmbedHtml = instagramEmbedHtml(rawEmbedHtml);
    } catch (error) {
      functions.logger.warn('Instagram returned unusable embed HTML.', {
        shortcode,
        error: error instanceof Error ? error.message : 'unknown',
      });
    }
  }
  const thumbnail = instagramImageUrl(response.thumbnail_url) ??
    instagramImageFromHtml(pageHtml, pageMetadata) ??
    instagramImageFromHtml(embedPageHtml, embedPageMetadata);
  const thumbnailWidth = Number(response.thumbnail_width);
  const thumbnailHeight = Number(response.thumbnail_height);
  const metadataWidth = Number(pageMetadata.get('og:image:width') ??
    embedPageMetadata.get('og:image:width'));
  const metadataHeight = Number(pageMetadata.get('og:image:height') ??
    embedPageMetadata.get('og:image:height'));
  const resolvedWidth = Number.isFinite(thumbnailWidth) && thumbnailWidth > 0
    ? thumbnailWidth : metadataWidth;
  const resolvedHeight = Number.isFinite(thumbnailHeight) && thumbnailHeight > 0
    ? thumbnailHeight : metadataHeight;
  const aspectRatio = Number.isFinite(resolvedWidth) &&
      Number.isFinite(resolvedHeight) && resolvedWidth > 0 && resolvedHeight > 0
    ? Math.min(2.4, Math.max(0.5, resolvedWidth / resolvedHeight))
    : 1;
  const title = stringValue(response.title, 300) ||
    instagramCaptionFromEmbed(rawEmbedHtml) ||
    instagramCaptionFromPage(pageMetadata) ||
    instagramCaptionFromPage(embedPageMetadata);
  const authorName = stringValue(response.author_name, 160) ||
    instagramAuthorFromPage(pageMetadata) ||
    instagramAuthorFromPage(embedPageMetadata);
  if (!safeEmbedHtml && !thumbnail) {
    throw callableError(
      'unavailable',
      'instagram-metadata-error',
      'Instagram preview is temporarily unavailable.',
    );
  }
  return {
    provider: 'instagram',
    contentType,
    shortcode,
    originalUrl,
    canonicalUrl,
    title: title || 'Instagram에서 공유된 게시물',
    authorName,
    thumbnailUrl: thumbnail,
    aspectRatio,
    embedHtml: safeEmbedHtml,
    previewMode: safeEmbedHtml ? 'embed' : 'image',
    previewStatus: 'ready',
  };
}

async function writeInstagramPreviewCache(preview: InstagramLinkPreview): Promise<void> {
  try {
    await admin.firestore()
      .collection(CACHE_COLLECTION)
      .doc(`instagram_${preview.shortcode}`)
      .set({
        provider: preview.provider,
        shortcode: preview.shortcode,
        canonicalUrl: preview.canonicalUrl,
        contentType: preview.contentType,
        title: preview.title,
        authorName: preview.authorName,
        thumbnailUrl: preview.thumbnailUrl,
        aspectRatio: preview.aspectRatio,
        embedHtml: preview.embedHtml,
        previewMode: preview.previewMode,
        metadataVersion: INSTAGRAM_METADATA_VERSION,
        fetchedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  } catch (error) {
    functions.logger.warn('Instagram preview cache write failed.', {
      shortcode: preview.shortcode,
      error: error instanceof Error ? error.message : 'unknown',
    });
  }
}

export const resolveSharedLink = functions.runWith({
  timeoutSeconds: 15,
  memory: '256MB',
  secrets: ['YOUTUBE_API_KEY'],
}).https.onCall(async (data, context): Promise<SharedLinkPreview> => {
  requireAuthenticatedUser(context);
  const originalUrl = requireUrl(data);
  const parsed = parseSharedLink(originalUrl);

  if (parsed.provider === 'youtube') {
    const cached = await readCachedPreview(
      parsed.originalUrl,
      parsed.videoId,
      parsed.canonicalUrl,
    );
    if (cached) return cached;

    const preview = await fetchYouTubePreview(
      parsed.originalUrl,
      parsed.videoId,
      parsed.canonicalUrl,
    );
    await writeYouTubePreviewCache(preview);
    return preview;
  }

  const cached = await readInstagramPreviewCache(
    parsed.originalUrl,
    parsed.shortcode,
    parsed.contentType,
    parsed.canonicalUrl,
  );
  if (cached) return cached;

  const preview = await fetchInstagramPreview(
    parsed.originalUrl,
    parsed.shortcode,
    parsed.contentType,
    parsed.canonicalUrl,
  );
  await writeInstagramPreviewCache(preview);
  return preview;
});
