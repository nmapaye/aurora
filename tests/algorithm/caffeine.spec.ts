import { mgActive, mgActiveEffect } from '~/domain/algorithm/caffeine';

describe('mgActive', () => {
  const now = Date.UTC(2024, 0, 1, 12, 0, 0); // fixed for determinism

  it('returns 0 with no doses', () => {
    expect(mgActive(now, [], 5)).toBe(0);
  });

  it('decays across multiple half-lives', () => {
    const doses = [{ timestamp: now - 10 * 3600_000, mg: 400 }];
    const mg = mgActive(now, doses, 5); // two half-lives
    expect(mg).toBeGreaterThan(90);
    expect(mg).toBeLessThan(120); // ~100 mg should remain
  });

  it('adds overlapping doses correctly', () => {
    const doses = [
      { timestamp: now - 1 * 3600_000, mg: 80 },
      { timestamp: now - 3 * 3600_000, mg: 120 },
    ];
    const mg = mgActive(now, doses, 6);
    expect(mg).toBeGreaterThan(150);
    expect(mg).toBeLessThan(220);
  });
});

describe('mgActiveEffect', () => {
  const now = Date.UTC(2024, 0, 1, 12, 0, 0);

  it('clamps to at most 1', () => {
    const E = mgActiveEffect(now, [{ timestamp: now, mg: 10_000 }], 5);
    expect(E).toBeLessThanOrEqual(1);
    expect(E).toBeGreaterThan(0.9);
  });

  it('is monotonic with respect to total mg', () => {
    const low = mgActiveEffect(now, [{ timestamp: now, mg: 50 }], 5);
    const high = mgActiveEffect(now, [{ timestamp: now, mg: 200 }], 5);
    expect(high).toBeGreaterThan(low);
  });
});
  
