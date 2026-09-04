/**
 * High-volume success/trace logging is disabled by default in production.
 * It can be enabled temporarily for a targeted investigation without changing
 * request handling, Firestore writes, retries, or error reporting.
 */
export const runtimeLogsEnabled =
  process.env.WEFILLING_VERBOSE_FUNCTION_LOGS === 'true';

export function runtimeInfo(...values: unknown[]): void {
  if (runtimeLogsEnabled) console.info(...values);
}
