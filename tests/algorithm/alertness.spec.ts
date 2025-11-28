import { alertnessScore } from '~/domain/algorithm/alertness';

describe('alertnessScore', () => {
  const now = Date.UTC(2024, 0, 2, 8, 0, 0); // 8am

  const baseParams = { halfLife: 5, targetSleep: 8 };

  const fullNight = [{ id: 'sleep', start: now - 8 * 3600_000 - 30 * 60000, end: now - 30 * 60000, type: 'sleep' as const }];
  const shortSleep = [{ id: 'sleep', start: now - 4 * 3600_000 - 30 * 60000, end: now - 30 * 60000, type: 'sleep' as const }];

  it('increases with caffeine when other factors equal', () => {
    const noCaf = alertnessScore(now, [], fullNight, baseParams);
    const withCaf = alertnessScore(now, [{ timestamp: now - 30 * 60000, mg: 120 }], fullNight, baseParams);
    expect(withCaf).toBeGreaterThan(noCaf);
  });

  it('decreases when sleep debt is higher', () => {
    const rested = alertnessScore(now, [], fullNight, baseParams);
    const tired = alertnessScore(now, [], shortSleep, baseParams);
    expect(tired).toBeLessThan(rested);
  });
});
  
