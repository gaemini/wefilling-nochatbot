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
  previewMode: 'embed';
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

  const embedHtml = stringValue(data.embedHtml, 100_000);
  if (!embedHtml || !embedHtml.includes('class="instagram-media"')) return null;
  return {
    provider: 'instagram',
    contentType,
    shortcode,
    originalUrl,
    canonicalUrl,
    title: stringValue(data.title, 300) || 'Instagram에서 공유된 게시물',
    authorName: stringValue(data.authorName, 160),
    thumbnailUrl: typeof data.thumbnailUrl === 'string' &&
        data.thumbnailUrl.startsWith('https://')
      ? data.thumbnailUrl
      : null,
    aspectRatio: typeof data.aspectRatio === 'number' && data.aspectRatio > 0
      ? Math.min(2.4, Math.max(0.5, data.aspectRatio))
      : 1,
    embedHtml,
    previewMode: 'embed',
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

  let response: Record<string, unknown>;
  try {
    response = await fetchJson(endpoint, 'graph.facebook.com');
  } catch (error) {
    functions.logger.warn('Instagram oEmbed request failed.', {
      shortcode,
      error: error instanceof Error ? error.message : 'unknown',
    });
    throw callableError(
      'unavailable',
      'instagram-oembed-error',
      'Instagram preview is temporarily unavailable.',
    );
  }

  const thumbnail = optionalHttpsUrl(response.thumbnail_url);
  const thumbnailWidth = Number(response.thumbnail_width);
  const thumbnailHeight = Number(response.thumbnail_height);
  const aspectRatio = Number.isFinite(thumbnailWidth) &&
      Number.isFinite(thumbnailHeight) && thumbnailWidth > 0 && thumbnailHeight > 0
    ? Math.min(2.4, Math.max(0.5, thumbnailWidth / thumbnailHeight))
    : 1;
  return {
    provider: 'instagram',
    contentType,
    shortcode,
    originalUrl,
    canonicalUrl,
    title: stringValue(response.title, 300) || 'Instagram에서 공유된 게시물',
    authorName: stringValue(response.author_name, 160),
    thumbnailUrl: thumbnail,
    aspectRatio,
    embedHtml: instagramEmbedHtml(response.html),
    previewMode: 'embed',
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
