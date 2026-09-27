import type { Dose } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import {
  DEFAULT_INSIGHTS_RANGE,
  describeInsightsChartDay,
  getInsightsPresentation,
  getInsightsRangeDays,
  getTrendMinimumDays,
  reactionInsightSignal,
} from '~/features/insights/presentation';
import { describeSignal } from '~/features/signals/model';

const now = new Date(2026, 6, 24, 12, 0, 0, 0).getTime();
const day = (daysAgo: number, hour = 9) =>
  new Date(2026, 6, 24 - daysAgo, hour, 0, 0, 0).getTime();

const dose = (
  id: string,
  daysAgo: number,
  mg: number,
  source?: string,
  hour = 9,
): Dose => ({ id, timestamp: day(daysAgo, hour), mg, source });

const session = (id: string, daysAgo: number, score: number): VigilanceSession => ({
  id,
  startedAt: day(daysAgo, 9),
  completedAt: day(daysAgo, 9) + 60_000,
  durationMs: 60_000,
  trialCount: 10,
  validReactionCount: 9,
  falseStartCount: 0,
  lapseCount: 1,
  medianReactionMs: 300,
  meanReactionMs: 300,
  fastestReactionMs: 240,
  reactionStdDevMs: 60,
  score,
  rating: 'Steady',
});

// One entry per day for each listed daysAgo.
const daily = (prefix: string, daysAgo: readonly number[], mg: number) =>
  daysAgo.map((ago) => dose(`${prefix}-${ago}`, ago, mg, 'Drip'));

describe('insights presentation', () => {
  it('maps W, 2W, and M ranges to 7, 14, and 30 days with 2W as the default', () => {
    expect(DEFAULT_INSIGHTS_RANGE).toBe('14');
    expect(getInsightsRangeDays('7')).toBe(7);
    expect(getInsightsRangeDays('14')).toBe(14);
    expect(getInsightsRangeDays('30')).toBe(30);
  });

  it('uses local calendar day buckets and keeps days without entries as null, not zero', () => {
    const presentation = getInsightsPresentation(
      [
        dose('current-a', 0, 100, 'Espresso', 0),
        dose('current-b', 6, 50, 'Tea', 23),
        dose('previous', 7, 80, 'Drip'),
      ],
      [],
      '7',
      now,
    );

    expect(presentation.points).toHaveLength(7);
    expect(presentation.points.map((point) => point.mg)).toEqual([50, null, null, null, null, null, 100]);
    expect(presentation.recordedDays).toBe(2);
    expect(presentation.missingDays).toBe(5);
    expect(presentation.previous.totalMg).toBe(80);
    expect(presentation.current.totalMg).toBe(150);
  });

  it('averages over recorded days only, and says so in the period line', () => {
    const presentation = getInsightsPresentation(
      [dose('a', 1, 90, 'Espresso'), dose('b', 3, 150, 'Drip'), dose('b2', 3, 60, 'Tea')],
      [],
      '14',
      now,
    );

    // (90 + 210) / 2 recorded days, not / 14 calendar days.
    expect(presentation.headline).toBe('150 mg');
    expect(presentation.period).toMatch(/^Average of 2 recorded days · 14 days · /);
    expect(presentation.source).toBe('Manual');
    expect(presentation.accessibilitySummary).toContain('150 mg average per recorded day across 2 recorded days');
    expect(presentation.accessibilitySummary).toContain('12 days with no record');
  });

  it('reports an honest empty range: no headline number and no fabricated points', () => {
    const presentation = getInsightsPresentation([], [], '30', now);

    expect(presentation.isEmpty).toBe(true);
    expect(presentation.headline).toBeUndefined();
    expect(presentation.points).toHaveLength(30);
    expect(presentation.points.every((point) => point.mg === null && point.entries === 0)).toBe(true);
    expect(presentation.accessibilitySummary).toContain('No caffeine recorded in this range');
    expect(presentation.trend.status).toBe('insufficient');
  });

  it('reads a missing chart day as "No record" and a recorded day with its entries and source', () => {
    const presentation = getInsightsPresentation(
      [dose('a', 0, 95, 'Drip'), dose('demo:dose:1', 0, 60, 'Tea')],
      [],
      '7',
      now,
    );
    const missing = describeInsightsChartDay(presentation.points[0]);
    const today = describeInsightsChartDay(presentation.points[6]);

    expect(missing.value).toBe('No record');
    expect(missing.value).not.toMatch(/0 mg/);
    expect(today.value).toBe('155 mg · 2 entries · Manual and Sample Data');
    expect(presentation.latestRecordedIndex).toBe(6);
  });

  it('points the default readout at the latest recorded day rather than an empty today', () => {
    const presentation = getInsightsPresentation([dose('a', 2, 95)], [], '7', now);

    expect(presentation.latestRecordedIndex).toBe(4);
  });

  it('labels a range of only Sample Data as Sample Data', () => {
    const presentation = getInsightsPresentation([dose('demo:dose:1', 1, 95)], [], '7', now);

    expect(presentation.source).toBe('Sample Data');
    expect(presentation.points[5].source).toBe('Sample Data');
  });

  describe('trend', () => {
    it('does not compare from one sparse day in each period', () => {
      const presentation = getInsightsPresentation(
        [dose('current', 1, 300), dose('previous', 8, 100)],
        [],
        '7',
        now,
      );

      expect(presentation.trend).toMatchObject({
        status: 'insufficient',
        requiredDays: 4,
        currentDays: 1,
        previousDays: 1,
      });
      expect(presentation.trend.text).not.toMatch(/%/);
      expect(presentation.trend.text).toContain('once each period has 4 recorded days');
    });

    it('does not compare when only the current period has enough recorded days', () => {
      const presentation = getInsightsPresentation(
        [...daily('cur', [0, 1, 2, 3, 4], 200), dose('prev', 9, 100)],
        [],
        '7',
        now,
      );

      expect(presentation.trend.status).toBe('insufficient');
    });

    it('requires half the range and at least four days in each period', () => {
      expect(getTrendMinimumDays(7)).toBe(4);
      expect(getTrendMinimumDays(14)).toBe(7);
      expect(getTrendMinimumDays(30)).toBe(15);
    });

    it('describes a comparison from recorded-day averages once both periods qualify', () => {
      const presentation = getInsightsPresentation(
        [...daily('cur', [0, 1, 2, 3], 200), ...daily('prev', [7, 8, 9, 10], 100)],
        [],
        '7',
        now,
      );

      expect(presentation.trend).toMatchObject({
        status: 'compared',
        direction: 'higher',
        text: 'About 100% higher than the previous 7 days',
        detail: '200 mg vs 100 mg per recorded day · 4 and 4 recorded days',
      });
    });

    it('calls a small difference about the same', () => {
      const presentation = getInsightsPresentation(
        [...daily('cur', [0, 1, 2, 3], 105), ...daily('prev', [7, 8, 9, 10], 100)],
        [],
        '7',
        now,
      );

      expect(presentation.trend).toMatchObject({ status: 'compared', direction: 'similar', text: 'About the same as the previous 7 days' });
    });

    it('includes the final hour of a daylight-saving fallback day in the previous local window', () => {
      const originalZone = process.env.TZ;
      process.env.TZ = 'America/New_York';
      try {
        const fallbackNow = new Date(2026, 10, 8, 12, 0, 0, 0).getTime();
        const fallbackDose = new Date(2026, 10, 1, 23, 30, 0, 0).getTime();
        const presentation = getInsightsPresentation(
          [{ id: 'fallback-hour', timestamp: fallbackDose, mg: 70 }],
          [],
          '7',
          fallbackNow,
        );

        expect(presentation.previous.totalMg).toBe(70);
      } finally {
        process.env.TZ = originalZone;
      }
    });
  });

  it('keeps time-of-day and drink breakdowns to the selected range', () => {
    const doses = [
      dose('recent', 1, 80, 'Matcha', 12),
      dose('older', 10, 220, 'Energy Drink', 19),
    ];
    const week = getInsightsPresentation(doses, [], '7', now);
    const fortnight = getInsightsPresentation(doses, [], '14', now);

    expect(week.dayparts).toEqual([
      { label: 'Morning', mg: 0, entries: 0 },
      { label: 'Midday', mg: 80, entries: 1 },
      { label: 'Evening', mg: 0, entries: 0 },
      { label: 'Late', mg: 0, entries: 0 },
    ]);
    expect(fortnight.drinkMix).toEqual([
      { label: 'Energy', mg: 220, pct: 73 },
      { label: 'Tea', mg: 80, pct: 27 },
    ]);
  });

  it('exposes no limit, adherence, streak, or sleep schedule', () => {
    const presentation = getInsightsPresentation([dose('a', 0, 500)], [session('s', 0, 70)], '7', now);
    const keys = Object.keys(presentation).join(' ');

    expect(keys).not.toMatch(/adherence|limit|streak|bedtime|wake|guidance/i);
    expect(JSON.stringify(presentation)).not.toMatch(/adherence|limit|streak|bedtime|suggested/i);
  });

  describe('reaction test signal', () => {
    it('is an empty row with an action when there is no test', () => {
      const signal = reactionInsightSignal([], now);

      expect(signal).toMatchObject({ status: 'empty', baseline: 'none', destination: 'Take Reaction Test' });
      expect(signal.value).toBeUndefined();
    });

    it('shows one test as the latest result, with date and source, and no baseline', () => {
      const signal = reactionInsightSignal([session('s1', 1, 72)], now);

      expect(signal).toMatchObject({
        status: 'observed',
        value: '72',
        period: 'Yesterday',
        source: 'Recorded',
        baseline: 'building',
        recentTests: 1,
      });
      expect(signal.context).toContain('1 of 3 tests toward a baseline');
      expect(signal.context).not.toMatch(/Baseline \d/);
      expect(describeSignal(signal)).toContain('Yesterday · Recorded');
    });

    it('still withholds a baseline at two tests', () => {
      const signal = reactionInsightSignal([session('s1', 3, 60), session('s2', 1, 80)], now);

      expect(signal.baseline).toBe('building');
      expect(signal.context).toContain('2 of 3 tests');
    });

    it('states a median baseline once three tests fall in the last 30 days', () => {
      const signal = reactionInsightSignal(
        [session('s1', 5, 60), session('s2', 3, 90), session('s3', 1, 70)],
        now,
      );

      expect(signal).toMatchObject({ baseline: 'established', value: '70', recentTests: 3 });
      expect(signal.context).toContain('Baseline 70, median of 3 tests in the last 30 days');
    });

    it('does not count tests older than 30 days toward a baseline', () => {
      const signal = reactionInsightSignal(
        [session('old1', 40, 60), session('old2', 35, 60), session('s3', 1, 70)],
        now,
      );

      expect(signal.baseline).toBe('building');
      expect(signal.context).toContain('1 of 3 tests');
    });

    it('labels a sample test as Sample Data', () => {
      const signal = reactionInsightSignal([session('demo:vigilance:1', 0, 70)], now);

      expect(signal).toMatchObject({ status: 'sample', source: 'Sample Data', period: 'Today' });
    });
  });
});
