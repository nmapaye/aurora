import { totalSleepHoursLast24, sleepDebt } from '~/domain/algorithm/sleepDebt';

describe('sleep debt', () => {
  it('aggregates overlapping sleep episodes in last 24h', () => {
    const now = Date.now();
    const sleeps = [
      { start: now - 8 * 3600_000, end: now - 1 * 3600_000 }, // 7h
      { start: now - 26 * 3600_000, end: now - 25 * 3600_000 }, // outside window
    ];
    const hours = totalSleepHoursLast24(now, sleeps as any);
    expect(Math.round(hours)).toBe(7);
  });

  it('computes normalized debt in [0,1]', () => {
    const now = Date.now();
    const sleeps = [{ start: now - 7.5 * 3600_000, end: now - 0.5 * 3600_000 }]; // 7h
    const debt = sleepDebt(now, sleeps as any, 8);
    expect(debt).toBeGreaterThan(0);
    expect(debt).toBeLessThan(1);
  });
});

