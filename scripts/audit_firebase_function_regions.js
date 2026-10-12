#!/usr/bin/env node

// Read-only deployed-function inventory for the Seoul migration. Never dump
// firebase-tools' full response: it can contain environment configuration.
const {execFileSync} = require('node:child_process');

const project = 'flutterproject3-af322';
let response;
try {
  const raw = execFileSync('firebase', [
    'functions:list', '--project', project, '--json',
  ], {
    encoding: 'utf8',
    env: {...process.env, DEBUG: ''},
    maxBuffer: 16 * 1024 * 1024,
  });
  response = JSON.parse(raw);
} catch (error) {
  console.error('Could not read deployed Functions inventory:', error.message);
  process.exit(1);
}

if (response.status !== 'success' || !Array.isArray(response.result)) {
  console.error('Firebase CLI returned an incomplete Functions inventory.');
  process.exit(1);
}

const functions = response.result.map((item) => {
  const trigger = item.callableTrigger ? 'callable' :
    item.httpsTrigger ? 'http' :
      item.eventTrigger ? 'event' :
        item.scheduleTrigger ? 'scheduled' : 'unknown';
  return {
    name: item.id,
    region: item.region,
    generation: item.platform,
    trigger,
    eventType: item.eventTrigger?.eventType ?? null,
    eventResource: item.eventTrigger?.eventFilters?.resource ?? null,
    runtime: item.runtime ?? null,
    state: item.state ?? null,
    serviceAccount: item.serviceAccount ?? null,
    secretNames: item.secretEnvironmentVariables?.map((entry) => entry.key) ?? [],
    extension: item.id.startsWith('ext-'),
  };
}).sort((a, b) => a.region.localeCompare(b.region) ||
    a.name.localeCompare(b.name));

const summary = {};
for (const item of functions) {
  const key = `${item.region}/${item.generation}/${item.trigger}/${item.state}`;
  summary[key] = (summary[key] ?? 0) + 1;
}
console.log(JSON.stringify({project, total: functions.length, summary, functions},
  null, 2));
