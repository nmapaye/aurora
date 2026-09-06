import { buildVigilanceSession } from '~/domain/vigilance';
import {
  checkInPairs,
  completeness,
  dailyTimeline,
  inspectionPoints,
  inspectTime,
  weeklyReview,
} from '~/features/insights/analysis';
import type { InsightInput } from '~/features/insights/analysis';
import { localDateKey } from '~/utils/calendar';
const hour = 3600000;
function input(now: number): InsightInput {
  return {
    now,
    doses: [],
    sleeps: [],
    tests: [],
    checkIns: [],
    zeroDays: [],
    prefs: { halfLife: 5, targetSleep: 8, dailyLimitMg: 150 },
  };
}
it.each([
  [2, 8, 23],
  [10, 1, 25],
])(
  'keeps calendar days distinct across DST month %s day %s',
  (month, day, length) => {
    const start = new Date(2026, month, day).getTime();
    const next = new Date(2026, month, day + 1).getTime();
    const data = input(next - 1);
    data.doses = [
      { id: 'last', timestamp: next - 1, mg: 100 },
      { id: 'next', timestamp: next, mg: 50 },
    ];
    expect(completeness(data, 3)).toHaveLength(3);
    const points = inspectionPoints(data, localDateKey(start));
    expect(points[0].timestamp).toBe(start);
    expect(points[points.length - 1].timestamp).toBe(next - 1);
    expect(new Set(points.map((p) => p.timestamp)).size).toBe(points.length);
    expect(dailyTimeline(data, localDateKey(start)).map((e) => e.id)).toEqual([
      'last',
    ]);
    if (process.env.TZ === 'America/New_York')
      expect((next - start) / hour).toBe(length);
  },
);
it('compares recorded weekly values while retaining missing days and user targets', () => {
  const now = new Date(2026, 8, 14, 12).getTime(),
    data = input(now);
  data.doses = [
    { id: 'previous', timestamp: new Date(2026, 8, 5, 12).getTime(), mg: 300 },
    { id: 'current', timestamp: now, mg: 100 },
    {
      id: 'demo:sample',
      timestamp: new Date(2026, 8, 13, 12).getTime(),
      mg: 900,
    },
  ];
  data.zeroDays = ['2026-09-13'];
  data.sleeps = [
    {
      id: 'manual:sleep:a',
      start: now - 12 * hour,
      end: now - 4 * hour,
      type: 'sleep',
    },
  ];
  const result = weeklyReview(data);
  expect(result.current).toMatchObject({
    caffeineCount: 2,
    caffeineMeanMg: 50,
    missingCaffeineDays: 5,
    caffeineWithinTarget: 2,
    sleepCount: 1,
    sleepAtTarget: 1,
    missingSleepDays: 6,
  });
  expect(result.previous).toMatchObject({
    caffeineCount: 1,
    caffeineMeanMg: 300,
    caffeineWithinTarget: 0,
  });
  expect(result.caffeineChangeMg).toBe(-250);
  expect(result.sleepChangeHours).toBeNull();
});
it('retains modeled carryover but never injects future records or hypothetical sleep', () => {
  const now = new Date(2026, 8, 14, 12).getTime(),
    data = input(now);
  data.doses = [
    { id: 'recorded', timestamp: now - hour, mg: 100 },
    { id: 'future', timestamp: now + hour, mg: 1000 },
  ];
  data.sleeps = [
    { id: 'future:sleep', start: now, end: now + 8 * hour, type: 'sleep' },
  ];
  const point = inspectTime(data, now + 4 * hour);
  expect(point.caffeineMg).toBeCloseTo(50);
  expect(point.sleepCount).toBe(0);
  expect(point.hasSleepRecord).toBe(false);
  const saved = JSON.stringify(data);
  inspectionPoints(data, localDateKey(now));
  completeness(data, 14);
  expect(JSON.stringify(data)).toBe(saved);
});

it('retains nearest unavailable test without substituting a farther median and counts only usable summary pairs', () => {
  const now = new Date(2026, 8, 14, 12).getTime(),
    data = input(now);
  data.checkIns = Array.from({ length: 6 }, (_, i) => ({
    id: `check:${i}`,
    timestamp: now - i * hour,
    rating: i === 0 ? 1 : 5,
    note: '',
  }));
  data.tests = data.checkIns.map((c, i) =>
    buildVigilanceSession({
      id: `test:${i}`,
      startedAt: c.timestamp - 60000,
      completedAt: c.timestamp,
      trialResults:
        i === 0
          ? [{ outcome: 'lapse', reactionMs: null }]
          : [{ outcome: 'valid', reactionMs: 250 }],
      falseStartCount: 0,
    }),
  );
  data.tests.push(
    buildVigilanceSession({
      id: 'farther',
      startedAt: now - 120000,
      completedAt: now - 60000,
      trialResults: [{ outcome: 'valid', reactionMs: 200 }],
      falseStartCount: 0,
    }),
  );
  const result = checkInPairs(data, 1);
  expect(result.pairs[0].test.id).toBe('test:0');
  expect(result.pairs[0].test.medianReactionMs).toBeNull();
  expect(result.pairs).toHaveLength(6);
  expect(result.summary).toEqual({
    count: 5,
    meanRating: 5,
    medianReactionMs: 250,
  });
  expect(
    checkInPairs({ ...data, checkIns: data.checkIns.slice(0, 5) }, 1).summary,
  ).toBeNull();
});
