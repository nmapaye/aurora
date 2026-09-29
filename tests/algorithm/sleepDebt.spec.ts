import { totalSleepHoursLast24, sleepDebt } from '~/domain/algorithm/sleepDebt';
import type { SleepSessionInput } from '~/domain/models';

describe('sleep debt', () => {
  it('aggregates overlapping sleep episodes in last 24h', () => {
    const now = Date.now();
    const sleeps: SleepSessionInput[] = [
      { start: now - 8 * 3600_000, end: now - 1 * 3600_000 }, // 7h
      { start: now - 26 * 3600_000, end: now - 25 * 3600_000 }, // outside window
    ];
    const hours = totalSleepHoursLast24(now, sleeps);
    expect(Math.round(hours)).toBe(7);
  });

  it('computes normalized debt in [0,1]', () => {
    const now = Date.now();
    const sleeps: SleepSessionInput[] = [{ start: now - 7.5 * 3600_000, end: now - 0.5 * 3600_000 }]; // 7h
    const debt = sleepDebt(now, sleeps, 8);
    expect(debt).toBeGreaterThan(0);
    expect(debt).toBeLessThan(1);
  });
});

describe('sleep debt with overlapping sources', () => {
  it('counts overlapping Watch and iPhone samples once', () => {
    const now = Date.now();
    const sleeps: SleepSessionInput[] = [
      { start: now - 8 * 3600_000, end: now - 1 * 3600_000 }, // iPhone asleep block, 7h
      { start: now - 7.5 * 3600_000, end: now - 5 * 3600_000 }, // Watch core stage
      { start: now - 5 * 3600_000, end: now - 4 * 3600_000 }, // Watch REM stage
      { start: now - 4 * 3600_000, end: now - 0.5 * 3600_000 }, // Watch core stage, extends 30m
    ];
    expect(totalSleepHoursLast24(now, sleeps)).toBeCloseTo(7.5, 5);
  });

  it('keeps separated sleep episodes additive', () => {
    const now = Date.now();
    const sleeps: SleepSessionInput[] = [
      { start: now - 20 * 3600_000, end: now - 14 * 3600_000 },
      { start: now - 3 * 3600_000, end: now - 2 * 3600_000 },
    ];
    expect(totalSleepHoursLast24(now, sleeps)).toBeCloseTo(7, 5);
  });
});
