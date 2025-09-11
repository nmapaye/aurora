import { circadianC } from '~/domain/algorithm/circadian';

describe('circadianC', () => {
  it('is periodic over 24h and within [0,1]', () => {
    const t = new Date('2025-01-01T00:00:00Z').getTime();
    const vals = Array.from({ length: 24 }, (_, h) => circadianC(t + h * 3600_000));
    for (const v of vals) {
      expect(v).toBeGreaterThanOrEqual(0);
      expect(v).toBeLessThanOrEqual(1);
    }
    // 24h later same value (same UTC tz for test)
    expect(circadianC(t)).toBeCloseTo(circadianC(t + 24 * 3600_000), 5);
  });
});

