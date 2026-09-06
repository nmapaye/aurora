import {
  completeness,
  weekdayPatterns,
  vigilanceComparison,
  checkInPairs,
  bedtimePairs,
  dailyTimeline,
  inspectTime,
  weeklyReview,
  type InsightInput,
} from '~/features/insights/analysis';
import type { VigilanceSession } from '~/domain/vigilance';
const now = new Date(2026, 8, 7, 20).getTime();
const h = 3600000;
const input = (): InsightInput => ({
  doses: [],
  zeroDays: [],
  sleeps: [],
  checkIns: [],
  tests: [],
  prefs: { halfLife: 5, targetSleep: 8, dailyLimitMg: 200 },
  now,
});
const test = (
  id: string,
  completedAt: number,
  medianReactionMs = 300,
): VigilanceSession => ({
  id,
  startedAt: completedAt - 60000,
  completedAt,
  durationMs: 60000,
  trialCount: 10,
  validReactionCount: 10,
  falseStartCount: 0,
  lapseCount: 0,
  medianReactionMs,
  meanReactionMs: medianReactionMs,
  fastestReactionMs: 200,
  reactionStdDevMs: 20,
  score: 70,
  rating: 'Steady',
});
it('keeps missing days absent from recorded averages and counts confirmed zero', () => {
  const i = input();
  i.zeroDays = ['2026-09-07'];
  expect(completeness(i, 2).map((d) => d.caffeineMg)).toEqual([null, 0]);
  expect(weekdayPatterns(i, 7).find((d) => d.weekday === 1)).toMatchObject({
    caffeineCount: 1,
    caffeineMean: 0,
    sleepCount: 0,
    sleepMean: null,
  });
});
it('uses only three prior eligible tests for a median baseline', () => {
  const selected = test('selected', now);
  const previous = [
    test('a', now - h, 200),
    test('b', now - 2 * h, 400),
    test('c', now - 3 * h, 300),
  ];
  expect(
    vigilanceComparison(
      selected,
      [
        ...previous,
        selected,
        test('demo:x', now - h, 100),
        test('equal', now, 100),
        test('future', now + h, 100),
      ],
      now,
    ),
  ).toEqual({ count: 3, medianMs: 300, changeMs: 0 });
  expect(vigilanceComparison(selected, previous.slice(0, 2), now)).toEqual({
    count: 2,
    medianMs: null,
    changeMs: null,
  });
});
it('pairs check-ins by closest completion and gates summaries at five pairs', () => {
  const i = input();
  i.tests = [test('early', now - h / 2), test('late', now)];
  i.checkIns = Array.from({ length: 5 }, (_, n) => ({
    id: String(n),
    timestamp: now - h / 4,
    rating: 4,
    note: '',
  }));
  const result = checkInPairs(i, 7);
  expect(result.pairs).toHaveLength(5);
  expect(result.pairs.every((p) => p.test.id === 'early')).toBe(true);
  expect(result.summary?.count).toBe(5);
  expect(
    checkInPairs({ ...i, checkIns: i.checkIns.slice(0, 4) }, 7).summary,
  ).toBeNull();
});
it('plots only recorded onset caffeine and deduplicated main sleep duration', () => {
  const i = input();
  const start = now - 21 * h,
    end = now - 13 * h;
  i.sleeps = [
    { id: 'm', start, end, type: 'sleep' },
    { id: 'healthkit:sleep:x', start: start + h, end, type: 'sleep' },
    { id: 'n', start, end, type: 'nap' },
  ];
  expect(bedtimePairs(i, 7).points).toHaveLength(0);
  i.doses = [{ id: 'd', timestamp: start - h, mg: 100 }];
  const r = bedtimePairs(i, 7);
  expect(r.points).toHaveLength(1);
  expect(r.points[0].sleepHours).toBe(8);
  expect(r.points[0].caffeineMg).toBeCloseTo(100 * Math.pow(2, -1 / 5));
  expect(r.summary).toBeNull();
});
it('includes an overnight session intersecting a daily timeline and excludes samples', () => {
  const i = input();
  i.sleeps = [
    { id: 'm', start: now - 21 * h, end: now - 13 * h, type: 'sleep' },
  ];
  i.doses = [{ id: 'demo:d', timestamp: now, mg: 100 }];
  expect(dailyTimeline(i, '2026-09-07').map((e) => e.kind)).toEqual(['sleep']);
});
it('time inspection never uses records from after the inspected moment', () => {
  const i = input();
  i.doses = [
    { id: 'a', timestamp: now - h, mg: 100 },
    { id: 'b', timestamp: now, mg: 200 },
  ];
  expect(inspectTime(i, now - h).caffeineMg).toBe(100);
  expect(inspectTime(i, now - h).alertness).toBeGreaterThanOrEqual(0);
});
it('weekly review exposes missing information and uses user targets', () => {
  const i = input();
  i.zeroDays = ['2026-09-07'];
  const r = weeklyReview(i);
  expect(r.current.caffeineCount).toBe(1);
  expect(r.current.missingCaffeineDays).toBe(6);
  expect(r.caffeineChangeMg).toBeNull();
  expect(r.targets.dailyCaffeineMg).toBe(200);
  expect(r.current.caffeineWithinTarget).toBe(1);
});
it('keeps an unavailable nearest test visible rather than substituting a farther test', () => {
  const i = input();
  i.checkIns = [{ id: 'c', timestamp: now - 1000, rating: 3, note: '' }];
  i.tests = [
    {
      ...test('nearest', now - 1000),
      validReactionCount: 0,
      medianReactionMs: null,
    },
    test('farther', now - 60000),
  ];
  const result = checkInPairs(i, 7);
  expect(result.pairs[0].test.id).toBe('nearest');
  expect(result.summary).toBeNull();
});
it('retains old dose residual without claiming the inspected day has an intake record', () => {
  const i = input();
  i.doses = [{ id: 'old', timestamp: now - 30 * h, mg: 100 }];
  const p = inspectTime(i, now);
  expect(p.caffeineMg).toBeGreaterThan(0);
  expect(p.hasCaffeineRecord).toBe(false);
});
