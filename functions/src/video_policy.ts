// functions/src/video_policy.ts
// 포스트·스낵챗·DM 영상 업로드의 서버 측 한도와 검증.
// lib/services/media/video_upload_policy.dart와 같은 값을 유지한다.
import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';
import * as functions from 'firebase-functions';
import {bucketFor} from './backend';

type Mp4Info = {
  duration?: number;
  timescale?: number;
  videoTracks?: Array<{
    duration?: number; timescale?: number;
    movie_duration?: number; movie_timescale?: number;
    track_width?: number; track_height?: number;
    video?: {width?: number; height?: number};
    matrix?: ArrayLike<number>;
    codec?: string;
  }>;
  tracks?: Array<{
    duration?: number; timescale?: number;
    movie_duration?: number; movie_timescale?: number;
    track_width?: number; track_height?: number;
    video?: {width?: number; height?: number};
    matrix?: ArrayLike<number>;
    codec?: string;
  }>;
};
type Mp4Parser = {
  onReady?: (info: Mp4Info) => void;
  onError?: (error: unknown) => void;
  appendBuffer(buffer: ArrayBuffer & {fileStart?: number}): number;
  flush(): void;
};
// eslint-disable-next-line @typescript-eslint/no-var-requires
const MP4Box = require('mp4box') as {createFile(): Mp4Parser};

export interface VideoLimits {
  maxDurationSeconds: number;
  maxBytes: number;
  label: string;
}

export const POST_VIDEO_LIMITS: VideoLimits = {
  maxDurationSeconds: 60,
  maxBytes: 40 * 1024 * 1024,
  label: 'post-720p-60s',
};
export const CHAT_VIDEO_LIMITS: VideoLimits = {
  maxDurationSeconds: 60,
  maxBytes: 25 * 1024 * 1024,
  label: 'chat-540p-60s',
};
export const VIDEO_CONTENT_TYPE = 'video/mp4';
export const VIDEO_THUMBNAIL_CONTENT_TYPE = 'image/jpeg';
export const MAX_VIDEO_THUMBNAIL_BYTES = 2 * 1024 * 1024;
// 컨테이너 길이는 트랙보다 약간 길 수 있다.
const DURATION_TOLERANCE_SECONDS = 0.5;

function seconds(duration: unknown, timescale: unknown): number {
  const d = Number(duration);
  const t = Number(timescale);
  if (!Number.isFinite(d) || !Number.isFinite(t) || t <= 0 || d < 0) return 0;
  return d / t;
}

export interface InspectedVideo {
  durationSeconds: number;
  /** 화면에 보이는 방향(tkhd 회전 행렬 적용) 기준의 가로·세로. */
  width: number;
  height: number;
  /** 첫 영상 트랙의 코덱 문자열(예: avc1.640028, hvc1.1.6.L93.B0). */
  codec: string;
}

/**
 * tkhd 행렬 [a, b, u, c, d, v, x, y, w]가 90°/270° 회전이면 true.
 * 휴대폰 세로 영상은 픽셀을 가로로 저장하고 이 행렬로 세워 보여준다
 * (iOS AVAssetExportSession, Android MediaMuxer 모두 이 방식).
 */
function isQuarterTurn(matrix: ArrayLike<number> | undefined): boolean {
  if (!matrix || matrix.length < 5) return false;
  const a = Number(matrix[0]);
  const b = Number(matrix[1]);
  const c = Number(matrix[3]);
  const d = Number(matrix[4]);
  return a === 0 && d === 0 && (b !== 0 || c !== 0);
}

/** 모든 기기(구형 Android 포함)가 하드웨어로 재생하는 코덱인지. */
export function isPortableVideoCodec(codec: string): boolean {
  return /^avc[13]/i.test(codec.trim());
}

/** 로컬 MP4의 길이·해상도를 읽는다. moov를 찾지 못하면 거부한다. */
export function inspectMp4(localPath: string): Promise<InspectedVideo> {
  return new Promise((resolve, reject) => {
    const parser = MP4Box.createFile();
    const input = fs.createReadStream(localPath, {highWaterMark: 1024 * 1024});
    let offset = 0;
    let settled = false;
    const fail = (error: unknown) => {
      if (settled) return;
      settled = true;
      input.destroy();
      reject(error instanceof Error ? error : new Error(String(error)));
    };
    parser.onError = fail;
    parser.onReady = (info) => {
      if (settled) return;
      settled = true;
      input.destroy();
      const tracks = (info.videoTracks && info.videoTracks.length > 0) ?
        info.videoTracks :
        (info.tracks ?? []).filter((track) => track.video != null);
      const movie = seconds(info.duration, info.timescale);
      let track = 0;
      let width = 0;
      let height = 0;
      for (const candidate of tracks) {
        track = Math.max(track,
          seconds(candidate.duration, candidate.timescale) ||
          seconds(candidate.movie_duration, candidate.movie_timescale));
        const codedWidth = Number(candidate.video?.width ?? candidate.track_width ?? 0) || 0;
        const codedHeight = Number(candidate.video?.height ?? candidate.track_height ?? 0) || 0;
        const rotated = isQuarterTurn(candidate.matrix);
        width = Math.max(width, rotated ? codedHeight : codedWidth);
        height = Math.max(height, rotated ? codedWidth : codedHeight);
      }
      if (tracks.length === 0) {
        reject(new Error('video-track-missing'));
        return;
      }
      resolve({
        durationSeconds: Math.max(movie, track),
        width,
        height,
        codec: String(tracks[0].codec ?? ''),
      });
    };
    input.on('data', (chunk: string | Buffer) => {
      if (settled) return;
      try {
        const source = typeof chunk === 'string' ? Buffer.from(chunk) : chunk;
        const copy = new Uint8Array(source.byteLength);
        copy.set(source);
        const buffer = copy.buffer as ArrayBuffer & {fileStart?: number};
        buffer.fileStart = offset;
        offset += source.byteLength;
        parser.appendBuffer(buffer);
      } catch (error) {
        fail(error);
      }
    });
    input.on('error', fail);
    input.on('end', () => {
      if (settled) return;
      try {
        parser.flush();
      } catch (error) {
        fail(error);
        return;
      }
      setImmediate(() => {
        if (!settled) fail(new Error('video-metadata-missing'));
      });
    });
  });
}

export interface ValidatedVideo extends InspectedVideo {
  bytes: number;
  storagePath: string;
  storageBucket: string;
}

/**
 * 클라이언트가 올린 영상 객체를 검증한다: 존재, MIME, 크기, 소유자 metadata,
 * 길이. 실패 시 HttpsError를 던지고 호출자가 객체 삭제 여부를 정한다.
 */
export async function validateUploadedVideo(options: {
  storagePath: string;
  storageBucket?: string | null;
  ownerUid: string;
  limits: VideoLimits;
  expectedPathPrefix: string;
}): Promise<ValidatedVideo> {
  const {storagePath, ownerUid, limits, expectedPathPrefix} = options;
  if (typeof storagePath !== 'string' || !storagePath.startsWith(expectedPathPrefix) ||
      storagePath.includes('..') || !storagePath.endsWith('.mp4')) {
    throw new functions.https.HttpsError('invalid-argument', '영상 경로가 올바르지 않습니다.');
  }
  const bucket = bucketFor(options.storageBucket ?? undefined);
  const file = bucket.file(storagePath);
  const [exists] = await file.exists();
  if (!exists) {
    throw new functions.https.HttpsError('not-found', '업로드된 영상을 찾을 수 없습니다.');
  }
  const [metadata] = await file.getMetadata();
  const bytes = Number(metadata.size ?? 0);
  const custom = (metadata.metadata ?? {}) as Record<string, unknown>;
  if (metadata.contentType !== VIDEO_CONTENT_TYPE) {
    throw new functions.https.HttpsError('invalid-argument', 'MP4 영상만 올릴 수 있습니다.');
  }
  if (!Number.isFinite(bytes) || bytes <= 0 || bytes > limits.maxBytes) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `영상은 ${Math.floor(limits.maxBytes / (1024 * 1024))}MB 이하여야 합니다.`,
    );
  }
  if (custom.ownerUid !== ownerUid) {
    throw new functions.https.HttpsError('permission-denied', '본인이 올린 영상만 사용할 수 있습니다.');
  }
  const localPath = path.join(
    os.tmpdir(),
    `video_${Date.now()}_${Math.random().toString(36).slice(2)}.mp4`,
  );
  try {
    await file.download({destination: localPath});
    const inspected = await inspectMp4(localPath);
    if (inspected.durationSeconds > limits.maxDurationSeconds + DURATION_TOLERANCE_SECONDS) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        `영상은 ${limits.maxDurationSeconds}초 이하여야 합니다.`,
      );
    }
    // 앱은 항상 H.264로 재인코딩한다. HEVC 등은 구형 Android에서 재생되지 않는다.
    if (!isPortableVideoCodec(inspected.codec)) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        '지원하지 않는 영상 코덱입니다.',
      );
    }
    return {
      ...inspected,
      bytes,
      storagePath,
      storageBucket: bucket.name,
    };
  } catch (error) {
    if (error instanceof functions.https.HttpsError) throw error;
    throw new functions.https.HttpsError('invalid-argument', '영상 형식을 읽을 수 없습니다.');
  } finally {
    await fs.promises.unlink(localPath).catch(() => undefined);
  }
}

/** 썸네일 객체 검증(JPEG, 2MB, 소유자). */
export async function validateUploadedThumbnail(options: {
  storagePath: string;
  storageBucket?: string | null;
  ownerUid: string;
  expectedPathPrefix: string;
}): Promise<{bytes: number}> {
  const {storagePath, ownerUid, expectedPathPrefix} = options;
  if (typeof storagePath !== 'string' || !storagePath.startsWith(expectedPathPrefix) ||
      storagePath.includes('..') || !storagePath.endsWith('.jpg')) {
    throw new functions.https.HttpsError('invalid-argument', '썸네일 경로가 올바르지 않습니다.');
  }
  const file = bucketFor(options.storageBucket ?? undefined).file(storagePath);
  const [exists] = await file.exists();
  if (!exists) throw new functions.https.HttpsError('not-found', '썸네일을 찾을 수 없습니다.');
  const [metadata] = await file.getMetadata();
  const bytes = Number(metadata.size ?? 0);
  const custom = (metadata.metadata ?? {}) as Record<string, unknown>;
  if (metadata.contentType !== VIDEO_THUMBNAIL_CONTENT_TYPE || bytes <= 0 ||
      bytes > MAX_VIDEO_THUMBNAIL_BYTES || custom.ownerUid !== ownerUid) {
    throw new functions.https.HttpsError('invalid-argument', '썸네일이 올바르지 않습니다.');
  }
  return {bytes};
}

/** 객체 삭제(없어도 성공). 포스트/메시지 삭제와 계정 삭제 경로에서 사용. */
export async function deleteStorageObjectQuietly(
  storagePath: string | null | undefined,
  storageBucket?: string | null,
): Promise<void> {
  if (!storagePath) return;
  try {
    await bucketFor(storageBucket ?? undefined).file(storagePath).delete({ignoreNotFound: true});
  } catch (error) {
    console.warn('storage object delete failed', {storagePath, message: (error as Error)?.message});
  }
}

export function videoDownloadUrlFromToken(
  bucketName: string,
  storagePath: string,
  token: string,
): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(storagePath)}?alt=media&token=${token}`;
}

