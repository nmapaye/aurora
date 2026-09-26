import type { SleepSessionInput } from '../models';

// Awakenings shorter than this are treated as part of one sleep episode.
export const BRIEF_AWAKENING_MS = 30 * 60_000;

// Merges overlapping (or nearly adjacent, within gapMs) samples so that stage
// segments and duplicate sources (Watch + iPhone) are counted once.
export function mergeSleepIntervals(
  sleeps: readonly SleepSessionInput[],
  gapMs = 0,
): SleepSessionInput[] {
  const ordered = sleeps
    .filter((s) => Number.isFinite(s.start) && Number.isFinite(s.end) && s.end > s.start)
    .map((s) => ({ start: s.start, end: s.end }))
    .sort((a, b) => a.start - b.start || a.end - b.end);
  const merged: SleepSessionInput[] = [];
  for (const s of ordered) {
    const last = merged[merged.length - 1];
    if (last && s.start <= last.end + gapMs) {
      last.end = Math.max(last.end, s.end);
    } else {
      merged.push(s);
    }
  }
  return merged;
}
