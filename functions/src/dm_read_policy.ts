import {Timestamp} from 'firebase-admin/firestore';

// Keep nanoseconds: millis/Date conversion can include the next message.
export function dmTimeCompare(a: Timestamp, b: Timestamp): number {
  return a.seconds === b.seconds ? a.nanoseconds - b.nanoseconds :
    a.seconds - b.seconds;
}

export function dmCovered(time: unknown, watermark: unknown): boolean {
  return time instanceof Timestamp && watermark instanceof Timestamp &&
    dmTimeCompare(time, watermark) <= 0;
}

// New notifications in the same millisecond must survive legacy OS APIs
// whose boundary is only millisecond precision. Conservatively retain that ms.
export function dmNotificationBoundary(time: Timestamp): number {
  return Math.floor(time.toMillis()) - 1;
}

export function nextDMReceiptToken(previous: unknown): Timestamp {
  const now = Timestamp.now();
  if (!(previous instanceof Timestamp) || dmTimeCompare(now, previous) > 0) return now;
  const nanos = previous.nanoseconds + 1;
  return new Timestamp(previous.seconds + (nanos >= 1000000000 ? 1 : 0),
    nanos % 1000000000);
}
