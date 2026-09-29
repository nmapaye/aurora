import { minutesSinceLastWake, inertia } from '~/domain/algorithm/inertia';
import type { SleepSessionInput } from '~/domain/models';

describe('inertia', () => {
  it('returns Infinity when no prior sleep', () => {
    const now = Date.now();
    expect(minutesSinceLastWake(now, [])).toBe(Infinity);
  });

  it('decays with minutes since wake and zeros after 90m', () => {
    const now = Date.now();
    const sleeps: SleepSessionInput[] = [{ start: now - 9 * 3600_000, end: now - 10 * 60_000 }];
    const valSoon = inertia(now - 5 * 60_000, sleeps);  // 5m after wake
    const valLate = inertia(now + 100 * 60_000, sleeps); // 100m after wake
    expect(valSoon).toBeGreaterThan(0);
    expect(valLate).toBe(0);
  });
});

describe('inertia with stage segments', () => {
  it('uses the end of the merged sleep episode as wake time', () => {
    const now = Date.now();
    const sleeps: SleepSessionInput[] = [
      { start: now - 8 * 3600_000, end: now - 4 * 3600_000 }, // core stage ends mid-night
      { start: now - 4 * 3600_000 + 5 * 60_000, end: now - 20 * 60_000 }, // resumes after a brief awakening
    ];
    expect(minutesSinceLastWake(now - 2 * 3600_000, sleeps)).toBe(Infinity);
    expect(minutesSinceLastWake(now, sleeps)).toBeCloseTo(20, 5);
  });

  it('ignores a segment that is still in progress', () => {
    const now = Date.now();
    const sleeps: SleepSessionInput[] = [
      { start: now - 30 * 3600_000, end: now - 22 * 3600_000 },
      { start: now - 1 * 3600_000, end: now + 1 * 3600_000 },
    ];
    expect(minutesSinceLastWake(now, sleeps)).toBeCloseTo(22 * 60, 5);
  });
});
