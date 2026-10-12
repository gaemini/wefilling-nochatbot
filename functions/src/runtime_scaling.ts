/**
 * Warm instances for latency-critical chat functions (the Snack Chat and DM
 * message triggers and the DM bounded read).
 *
 * The value is a source constant because `firebase deploy` analyses the code
 * without `.env`, so an environment variable would silently deploy as 0.
 * One warm 256MB instance per function costs a few dollars a month and removes
 * the 2–4 s Node cold start from the first push notification after an idle
 * period. 1st gen serves one request per instance, so a burst can still cold
 * start a second instance; raise the constant (max 3) if p95 push latency
 * shows cold starts under normal load.
 *
 * `CHAT_HOT_FUNCTIONS_MIN_INSTANCES` still overrides the constant for local
 * tooling (e.g. set to 0 when inventorying with the emulator flag).
 */
export const DEFAULT_CHAT_HOT_MIN_INSTANCES = 1;

export function chatHotMinInstances(): number {
  const override = process.env.CHAT_HOT_FUNCTIONS_MIN_INSTANCES;
  const raw = override === undefined || override === ''
    ? DEFAULT_CHAT_HOT_MIN_INSTANCES
    : Number(override);
  if (!Number.isFinite(raw) || raw <= 0) return 0;
  return Math.min(Math.floor(raw), 3);
}

/** Spread into `runWith` so a zero value leaves the options untouched. */
export function chatHotRunWithOptions(): {minInstances?: number} {
  const minInstances = chatHotMinInstances();
  return minInstances > 0 ? {minInstances} : {};
}
