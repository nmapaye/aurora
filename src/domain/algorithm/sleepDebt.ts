import type { SleepSessionInput } from '../models';

export function totalSleepHoursLast24(
  nowMs: number,
  sleeps: SleepSessionInput[],
) {
  const from = nowMs - 24 * 3600_000;
  const intervals = sleeps
    .filter(
      (sleep) =>
        Number.isFinite(sleep.start) &&
        Number.isFinite(sleep.end) &&
        Number.isFinite(new Date(sleep.start).getTime()) &&
        Number.isFinite(new Date(sleep.end).getTime()),
    )
    .map((sleep) => ({
      start: Math.max(sleep.start, from),
      end: Math.min(sleep.end, nowMs),
    }))
    .filter((sleep) => sleep.end > sleep.start)
    .sort((left, right) => left.start - right.start);

  let totalMs = 0;
  let start: number | undefined;
  let end = 0;
  for (const interval of intervals) {
    if (start === undefined) {
      start = interval.start;
      end = interval.end;
    } else if (interval.start <= end) {
      end = Math.max(end, interval.end);
    } else {
      totalMs += end - start;
      start = interval.start;
      end = interval.end;
    }
  }
  if (start !== undefined) totalMs += end - start;
  return totalMs / 3600_000;
}
export function sleepDebt(
  nowMs: number,
  sleeps: SleepSessionInput[],
  targetH: number,
) {
  const H = totalSleepHoursLast24(nowMs, sleeps);
  const debt = (targetH - H) / targetH;
  return Math.max(0, Math.min(1, debt));
}
