import {
  completeness,
  inspectTime,
  weekdayPatterns,
  bedtimePairs,
  vigilanceComparison,
  checkInPairs,
  type InsightInput,
} from '~/features/insights/analysis';
import { buildVigilanceSession } from '~/domain/vigilance';
import { addCalendarDays, localDateKey } from '~/utils/calendar';

const hour = 3600000;
const now = new Date(2026, 8, 14, 12).getTime();
const empty = (): InsightInput => ({
  doses: [],
  zeroDays: [],
  sleeps: [],
  checkIns: [],
  tests: [],
  prefs: { halfLife: 5, targetSleep: 8 },
  now,
});
function testAt(id: string, completedAt: number, reactionMs = 250) {
  return buildVigilanceSession({
    id,
    startedAt: completedAt - 60000,
    completedAt,
    trialResults: [{ outcome: 'valid', reactionMs }],
    falseStartCount: 0,
  });
}

it('uses only eligible tests strictly before the selected test and requires three', () => {
  const selected = testAt('selected', now - hour, 260);
  const prior = [
    testAt('a', now - 4 * hour, 200),
    testAt('b', now - 3 * hour, 400),
    testAt('c', now - 2 * hour, 300),
  ];
  const ignored = [
    selected,
    testAt('same-time', selected.completedAt, 100),
    testAt('later', now, 100),
    testAt('demo:old', now - 5 * hour, 100),
    {
      ...testAt('invalid', now - 6 * hour),
      validReactionCount: 0,
      medianReactionMs: null,
    },
  ];
  expect(vigilanceComparison(selected, [...prior, ...ignored], now)).toEqual({
    count: 3,
    medianMs: 300,
    changeMs: -40,
  });
  expect(
    vigilanceComparison(selected, [...prior.slice(0, 2), ...ignored], now),
  ).toEqual({ count: 2, medianMs: null, changeMs: null });
});

it('pairs at the thirty-minute boundary with deterministic ties and excludes future/sample tests', () => {
  const input = empty();
  input.checkIns = [
    { id: 'check', timestamp: now - hour, rating: 3, note: '' },
  ];
  input.tests = [
    testAt('z-earlier', now - 1.5 * hour),
    testAt('a-earlier', now - 1.5 * hour),
    testAt('later', now - 0.5 * hour),
    testAt('demo:nearest', now - hour),
  ];
  const result = checkInPairs(input, 1);
  expect(result.pairs).toHaveLength(1);
  expect(result.pairs[0].test.id).toBe('a-earlier');
  expect(result.summary).toBeNull();
  input.tests = [
    testAt('too-far', now - 1.5 * hour - 1),
    testAt('future', now + 1),
  ];
  expect(checkInPairs(input, 1).pairs).toEqual([]);
});

it('gates paired check-in summaries at five observations and keeps scales separate', () => {
  const input = empty();
  input.checkIns = Array.from({ length: 5 }, (_, i) => ({
    id: `c${i}`,
    timestamp: now - (i + 1) * hour,
    rating: i + 1,
    note: '',
  }));
  input.tests = input.checkIns.map((c) =>
    testAt(`test:${c.id}`, c.timestamp, 200 + c.rating * 10),
  );
  const result = checkInPairs(input, 1);
  expect(result.summary).toEqual({
    count: 5,
    meanRating: 3,
    medianReactionMs: 230,
  });
  expect(
    checkInPairs({ ...input, checkIns: input.checkIns.slice(0, 4) }, 1).summary,
  ).toBeNull();
});

it('distinguishes recorded zero and missing Mondays in weekday averages', () => {
  const input = empty();
  input.zeroDays = [localDateKey(addCalendarDays(now, -7))];
  input.doses = [
    { id: 'mine', timestamp: now, mg: 100 },
    { id: 'demo:older', timestamp: addCalendarDays(now, -14), mg: 500 },
  ];
  const monday = weekdayPatterns(input, 15).find((row) => row.weekday === 1)!;
  expect(monday.caffeineCount).toBe(2);
  expect(monday.caffeineMean).toBe(50);
  expect(monday.sleepCount).toBe(0);
  expect(monday.sleepMean).toBeNull();
});

it('counts overlapping main sleep and naps once and leaves absent days missing', () => {
  const input = empty();
  input.sleeps = [
    {
      id: 'health',
      start: now - 12 * hour,
      end: now - 4 * hour,
      type: 'sleep',
    },
    {
      id: 'manual:sleep:nap',
      start: now - 5 * hour,
      end: now - 3 * hour,
      type: 'nap',
    },
  ];
  const rows = completeness(input, 2);
  expect(rows.find((row) => row.date === localDateKey(now))?.sleepHours).toBe(
    9,
  );
  expect(
    rows.find((row) => row.date === localDateKey(addCalendarDays(now, -1)))
      ?.sleepHours,
  ).toBeNull();
  expect(
    rows.every(
      (row) => row.caffeineMg === null && row.caffeineState === 'missing',
    ),
  ).toBe(true);
});

it('requires five eligible bedtime pairs and excludes missing onset-day intake', () => {
  const input = empty();
  input.sleeps = Array.from({ length: 6 }, (_, i) => {
    const end = addCalendarDays(now - 4 * hour, -i);
    return {
      id: `sleep:${i}`,
      start: end - 8 * hour,
      end,
      type: 'sleep' as const,
    };
  });
  input.zeroDays = input.sleeps
    .slice(0, 5)
    .map((sleep) => localDateKey(sleep.start));
  const result = bedtimePairs(input, 7);
  expect(result.points).toHaveLength(5);
  expect(result.summary).toEqual({
    count: 5,
    meanCaffeineMg: 0,
    meanSleepHours: 8,
  });
  input.zeroDays = input.zeroDays.slice(0, 4);
  expect(bedtimePairs(input, 7).summary).toBeNull();
});


it('keeps modeled carryover separate from evidence of intake on the inspected date', () => {
  const input = empty();
  input.doses = [{ id: 'previous', timestamp: now - 24 * hour, mg: 100 }];
  const point = inspectTime(input, now);
  expect(point.caffeineMg).toBeGreaterThan(0);
  expect(point.hasCaffeineRecord).toBe(false);
  input.zeroDays = [localDateKey(now)];
  expect(inspectTime(input, now).hasCaffeineRecord).toBe(true);
});
