const assert = require('node:assert/strict');
const {validatedSnapshotVideoInfo} = require('../lib/snapshot');

function videoInfo({videoMs, movieMs, codec = 'avc1.640028'}) {
  return {
    duration: movieMs,
    timescale: 1000,
    videoTracks: [{
      duration: videoMs,
      timescale: 1000,
      video: {width: 1080, height: 1920},
      codec,
    }],
  };
}

const exact = validatedSnapshotVideoInfo(videoInfo({videoMs: 12000, movieMs: 12000}));
assert.equal(exact.durationMs, 12000);
assert.equal(exact.codec, 'avc1.640028');

const muxerTail = validatedSnapshotVideoInfo(videoInfo({videoMs: 12034, movieMs: 12160}));
assert.equal(muxerTail.durationMs, 12000);

const hevc = validatedSnapshotVideoInfo(videoInfo({
  videoMs: 11000,
  movieMs: 11030,
  codec: 'hvc1.1.6.L93.B0',
}));
assert.equal(hevc.codec, 'hvc1.1.6.l93.b0');

assert.throws(
  () => validatedSnapshotVideoInfo(videoInfo({videoMs: 12200, movieMs: 12200})),
  /invalid-video-stream/,
);
assert.throws(
  () => validatedSnapshotVideoInfo(videoInfo({videoMs: 11900, movieMs: 13000})),
  /invalid-video-stream/,
);
assert.throws(
  () => validatedSnapshotVideoInfo(videoInfo({videoMs: 8000, movieMs: 0})),
  /invalid-video-stream/,
);
assert.throws(
  () => validatedSnapshotVideoInfo(videoInfo({
    videoMs: 8000,
    movieMs: 8000,
    codec: 'av01.0.05M.08',
  })),
  /invalid-video-stream/,
);

console.log('snapshot video metadata checks passed');
