import {
  defaultPlanningState,
  normalizePlanning,
  projectScenario,
  thresholdCrossing,
  reductionTargets,
  budgetBalance,
  experimentWindow,
} from '~/features/planning/model';
const now = new Date(2026, 8, 7, 10).getTime();
const hour = 3600000;
const scenario = {
  id: 'a',
  name: 'Morning',
  doses: [{ id: 'one', offsetMinutes: 60, mg: 100, label: 'Coffee' }],
};
describe('planning calculations', () => {
  it('keeps hypothetical doses separate and excludes sample baseline', () => {
    const baseline = [
      { id: 'mine', timestamp: now, mg: 50 },
      { id: 'demo:dose', timestamp: now, mg: 400 },
    ];
    const result = projectScenario(
      scenario,
      baseline,
      [],
      { halfLife: 5, targetSleep: 8 },
      now,
      now + 6 * hour,
      { startMinutes: 60, endMinutes: 120 },
    );
    expect(result.plannedMg).toBe(100);
    expect(result.bedtimeMg).toBeCloseTo(50 * Math.pow(0.5, 6 / 5) + 50);
    expect(baseline).toHaveLength(2);
    expect(
      result.curve.find((p) => p.timestamp === now + hour)?.mg,
    ).toBeGreaterThan(140);
    expect(result.focusMean).toBeGreaterThanOrEqual(0);
  });
  it('estimates decay after the final future dose rather than an earlier dip', () => {
    expect(
      thresholdCrossing([{ timestamp: now + 2 * hour, mg: 100 }], 5, 50, now),
    ).toBe(now + 7 * hour);
    expect(thresholdCrossing([], 5, 50, now)).toBe(now);
    expect(
      thresholdCrossing([{ timestamp: now, mg: 100 }], 5, 0, now),
    ).toBeNull();
  });
  it('generates inclusive linear daily targets and preserves endpoints', () => {
    expect(
      reductionTargets({
        startDate: '2026-03-07',
        startMg: 200,
        endMg: 50,
        days: 3,
      }),
    ).toEqual([
      { date: '2026-03-07', mg: 200 },
      { date: '2026-03-08', mg: 125 },
      { date: '2026-03-09', mg: 50 },
    ]);
    expect(
      reductionTargets({ startDate: 'bad', startMg: 200, endMg: 50, days: 3 }),
    ).toEqual([]);
    expect(
      budgetBalance({
        targetMg: 150,
        allocations: [{ id: '1', label: 'Tea', mg: 200 }],
      }),
    ).toEqual({ allocatedMg: 200, remainingMg: -50 });
  });
  it('rejects malformed persisted plans and clamps none into clinical recommendations', () => {
    expect(
      normalizePlanning({
        scenarios: [
          {
            ...scenario,
            doses: [{ id: 'x', offsetMinutes: -3, mg: 100, label: 'bad' }],
          },
        ],
        thresholdMg: -1,
        sensitivityHours: [0, Infinity, NaN],
        checkIns: [{ id: 'x', timestamp: now, rating: 6, note: '' }],
      }),
    ).toEqual(defaultPlanningState());
  });
  it('distinguishes missing caffeine days from explicit zero and excludes samples', () => {
    const result = experimentWindow(
      { start: '2026-09-07', end: '2026-09-08' },
      [{ id: 'demo:x', timestamp: now, mg: 500 }],
      ['2026-09-07'],
      [],
      [],
      [],
      now + 48 * hour,
    );
    expect(result.caffeine).toEqual({ count: 1, mean: 0, missingDays: 1 });
    expect(result.sleep.count).toBe(0);
    expect(result.checkIns.mean).toBeNull();
    expect(result.vigilance.count).toBe(0);
  });
});
