#!/usr/bin/env node
// Summarizes ChatTiming stage lines into p50/p95 per (kind, stage).
//
// Input: any text with lines containing `[SnackChatTiming]` / `[DMChatTiming]`
// (client logs via `adb logcat` / Xcode console with CHAT_TIMING_RELEASE=true,
// or Cloud Logging exports with WEFILLING_VERBOSE_FUNCTION_LOGS=true).
// Usage:
//   node scripts/report_chat_timing.js < logcat.txt
//   node scripts/report_chat_timing.js client.txt server.txt --json
// Only stage names, ids and durations are read; message text is never parsed.
const fs = require('node:fs');

const files = process.argv.slice(2).filter((arg) => !arg.startsWith('--'));
const asJson = process.argv.includes('--json');
const input = files.length > 0
  ? files.map((file) => fs.readFileSync(file, 'utf8')).join('\n')
  : fs.readFileSync(0, 'utf8');

const linePattern = /\[(Snack|DM)ChatTiming\]\s+(.*)$/;
const samples = new Map(); // key: kind/stage/metric -> number[]
const counters = new Map(); // key: kind/stage -> count

for (const rawLine of input.split(/\r?\n/)) {
  const match = linePattern.exec(rawLine);
  if (!match) continue;
  const kind = match[1] === 'Snack' ? 'snack' : 'dm';
  const fields = {};
  for (const token of match[2].split(/\s+/)) {
    const eq = token.indexOf('=');
    if (eq <= 0) continue;
    fields[token.slice(0, eq)] = token.slice(eq + 1);
  }
  const stage = fields.stage;
  if (!stage) continue;
  const stageKey = `${kind}/${stage}`;
  counters.set(stageKey, (counters.get(stageKey) ?? 0) + 1);
  for (const metric of ['durationMs', 'totalDurationMs', 'commitAgeMs', 'sinceLastSendMs']) {
    const value = Number(fields[metric]);
    if (!Number.isFinite(value) || value < 0) continue;
    const key = `${stageKey}/${metric}`;
    if (!samples.has(key)) samples.set(key, []);
    samples.get(key).push(value);
  }
}

function percentile(sorted, p) {
  if (sorted.length === 0) return null;
  const index = Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1);
  return sorted[Math.max(0, index)];
}

const rows = [];
for (const [key, values] of samples) {
  const sorted = [...values].sort((a, b) => a - b);
  const [kind, stage, metric] = key.split('/');
  rows.push({
    kind, stage, metric, n: sorted.length,
    p50: percentile(sorted, 50), p95: percentile(sorted, 95), p99: percentile(sorted, 99),
    max: sorted[sorted.length - 1],
  });
}
rows.sort((a, b) => a.kind.localeCompare(b.kind) || a.stage.localeCompare(b.stage) || a.metric.localeCompare(b.metric));

if (asJson) {
  process.stdout.write(JSON.stringify({rows, counts: Object.fromEntries(counters)}, null, 2) + '\n');
} else {
  if (rows.length === 0) {
    process.stdout.write('No ChatTiming lines with durations found.\n');
  } else {
    const header = ['kind', 'stage', 'metric', 'n', 'p50', 'p95', 'p99', 'max'];
    const table = [header, ...rows.map((row) => header.map((column) => String(row[column])))];
    const widths = header.map((_, i) => Math.max(...table.map((cells) => cells[i].length)));
    for (const cells of table) {
      process.stdout.write(cells.map((cell, i) => cell.padEnd(widths[i])).join('  ') + '\n');
    }
  }
  const countOnly = [...counters.entries()].filter(([key]) =>
    !rows.some((row) => `${row.kind}/${row.stage}` === key));
  if (countOnly.length > 0) {
    process.stdout.write('\nStages without durations (counts): ' +
      countOnly.map(([key, count]) => `${key}=${count}`).join(', ') + '\n');
  }
}
