import {
  projectScenario,
  thresholdCrossing,
  reductionTargets,
  experimentWindow,
} from '~/features/planning/model';
import { buildVigilanceSession } from '~/domain/vigilance';

const hour = 3600000;
const now = new Date(2026, 8, 7, 10).getTime();
const prefs = { halfLife: 5, targetSleep: 8 };

it('solves the crossing after all future doses with carryover from recorded intake', () => {
  const doses = [
    { timestamp: now - 5 * hour, mg: 100 },
    { timestamp: now + 2 * hour, mg: 100 },
  ];
  const atLast = 100 + 100 * Math.pow(0.5, 7 / 5);
  const expected = now + 2 * hour + 5 * hour * Math.log2(atLast / 25);
  expect(thresholdCrossing(doses, 5, 25, now)).toBeCloseTo(expected, 0);
  expect(thresholdCrossing(doses, 5, 0, now)).toBeNull();
});

it('moves reusable scenario doses with the common reference time without mutating records', () => {
  const scenario = { id: 'plan', name: 'Later tea', doses: [
    { id: 'tea', label: 'Tea', offsetMinutes: 120, mg: 100 },
  ] };
  const baseline = [{ id: 'mine', timestamp: now - 5 * hour, mg: 100 }];
  Object.freeze(baseline[0]);
  Object.freeze(baseline);
  const focus = { startMinutes: 120, endMinutes: 180 };
  const first = projectScenario(scenario, baseline, [], prefs, now, now + 7 * hour, focus);
  const next = projectScenario(scenario, baseline, [], prefs, now + hour, now + 8 * hour, focus);
  expect(first.bedtimeMg).toBeCloseTo(100 * Math.pow(0.5, 12 / 5) + 50);
  expect(next.bedtimeMg).toBeCloseTo(100 * Math.pow(0.5, 13 / 5) + 50);
  expect(first.plannedMg).toBe(100);
  expect(next.plannedMg).toBe(100);
  expect(baseline).toEqual([{ id: 'mine', timestamp: now - 5 * hour, mg: 100 }]);
});

it('keeps one daily reduction row across both DST transitions', () => {
  for (const [startDate, dates] of [
    ['2026-03-07', ['2026-03-07', '2026-03-08', '2026-03-09']],
    ['2026-10-31', ['2026-10-31', '2026-11-01', '2026-11-02']],
  ] as const) {
    const rows = reductionTargets({ startDate, startMg: 201, endMg: 0, days: 3 });
    expect(rows.map(row => row.date)).toEqual(dates);
    expect(rows[0].mg).toBe(201);
    expect(rows[2].mg).toBe(0);
  }
});

it('excludes samples in every experiment measure and counts explicit zero as a recorded day', () => {
  const personalTest = buildVigilanceSession({ id: 'test', startedAt: now - 60000,
    completedAt: now, trialResults: [{ outcome: 'valid', reactionMs: 250 }], falseStartCount: 0 });
  const result = experimentWindow(
    { start: '2026-09-07', end: '2026-09-09' },
    [{ id: 'demo:dose', timestamp: now, mg: 1000 }, { id: 'dose', timestamp: now, mg: 100 }],
    ['2026-09-08'],
    [{ id: 'demo:sleep:1', start: now - 8 * hour, end: now, type: 'sleep' }],
    [{ id: 'mine', timestamp: now, rating: 2, note: '' }, { id: 'demo:check', timestamp: now, rating: 5, note: '' }],
    [personalTest, { ...personalTest, id: 'demo:test', medianReactionMs: 1000 }],
    now + 72 * hour,
  );
  expect(result.caffeine).toEqual({ count: 2, mean: 50, missingDays: 1 });
  expect(result.sleep.count).toBe(0);
  expect(result.checkIns.count).toBe(1);
  expect(result.checkIns.mean).toBe(2);
  expect(result.vigilance.count).toBe(1);
  expect(result.vigilance.mean).toBe(personalTest.medianReactionMs);
});

it('provides the pre-dose value so the curve does not show caffeine before intake', () => {
  const doseTime = now + hour;
  const scenario = { id: 'event', name: 'First coffee', doses: [{ id: 'dose', label: 'Coffee', offsetMinutes: 60, mg: 100 }] };
  const { curve } = projectScenario(scenario, [], [], prefs, now, now + 8 * hour, { startMinutes: 60, endMinutes: 120 });
  const earlier = curve.filter(point => point.timestamp < doseTime);
  const before = earlier[earlier.length - 1];
  expect(before.timestamp).toBeGreaterThanOrEqual(doseTime - 1);
  expect(before.mg).toBe(0);
  expect(curve.find(point => point.timestamp === doseTime)?.mg).toBe(100);
});
