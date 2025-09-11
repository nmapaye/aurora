import { minutesSinceLastWake, inertia } from '~/domain/algorithm/inertia';

describe('inertia', () => {
  it('returns Infinity when no prior sleep', () => {
    const now = Date.now();
    expect(minutesSinceLastWake(now, [])).toBe(Infinity);
  });

  it('decays with minutes since wake and zeros after 90m', () => {
    const now = Date.now();
    const sleeps = [{ start: now - 9 * 3600_000, end: now - 10 * 60_000 } as any];
    const valSoon = inertia(now - 5 * 60_000, sleeps);  // 5m after wake
    const valLate = inertia(now + 100 * 60_000, sleeps); // 100m after wake
    expect(valSoon).toBeGreaterThan(0);
    expect(valLate).toBe(0);
  });
});

