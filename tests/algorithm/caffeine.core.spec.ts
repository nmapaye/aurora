import { mgActive, mgActiveEffect } from '~/domain/algorithm/caffeine';

describe('caffeine model', () => {
  const now = Date.now();
  const d = (h: number) => now - h * 3600_000;

  it('decays by half-life', () => {
    const doses = [{ timestamp: d(4), mg: 200 }];
    const hl = 4; // hours
    const mg = mgActive(now, doses, hl);
    // ~100 mg remains after one half-life
    expect(mg).toBeGreaterThan(95);
    expect(mg).toBeLessThan(105);
  });

  it('sums multiple doses with different ages', () => {
    const doses = [
      { timestamp: d(0), mg: 50 },
      { timestamp: d(2), mg: 100 },
      { timestamp: d(8), mg: 200 },
    ];
    const hl = 5;
    const mg = mgActive(now, doses, hl);
    expect(mg).toBeGreaterThan(50); // at least the immediate dose
    expect(mg).toBeLessThan(300);   // decayed older doses prevent sum
  });

  it('effect is saturating and in [0,1]', () => {
    const doses = [{ timestamp: d(0), mg: 1000 }];
    const E = mgActiveEffect(now, doses, 5);
    expect(E).toBeGreaterThan(0.9);
    expect(E).toBeLessThanOrEqual(1);
  });
});

