import type { Dose } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import {
  DEFAULT_INSIGHTS_RANGE,
  getInsightsPresentation,
  getInsightsRangeDays,
} from '~/features/insights/presentation';

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

describe('insights presentation', () => {
  it('maps W, 2W, and M ranges to 7, 14, and 30 days with 2W as the default', () => {
    expect(DEFAULT_INSIGHTS_RANGE).toBe('14');
    expect(getInsightsRangeDays('7')).toBe(7);
    expect(getInsightsRangeDays('14')).toBe(14);
    expect(getInsightsRangeDays('30')).toBe(30);
  });

  it('uses local calendar day buckets and an equal previous window', () => {
    const presentation = getInsightsPresentation(
      [
        dose('current-a', 0, 100, 'Espresso', 0),
        dose('current-b', 6, 50, 'Tea', 23),
        dose('previous', 7, 80, 'Drip'),
      ],
      [],
      120,
      '7',
      now,
    );

    expect(presentation.points).toHaveLength(7);
    expect(presentation.points.map((point) => point.mg)).toEqual([50, null, null, null, null, null, 100]);
    expect(presentation.previous.totalMg).toBe(80);
    expect(presentation.current.totalMg).toBe(150);
    expect(presentation.deltaPct).toBe(91);
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
        400,
        '7',
        fallbackNow,
      );

      expect(presentation.previous.totalMg).toBe(70);
    } finally {
      process.env.TZ = originalZone;
    }
  });

  it('changes headline, adherence, mixes, and vigilance inputs with the selected range', () => {
    const doses = [
      dose('recent', 1, 80, 'Matcha', 12),
      dose('older', 10, 220, 'Energy Drink', 19),
    ];
    const sessions = [session('recent-session', 1, 80), session('older-session', 10, 60)];
    const week = getInsightsPresentation(doses, sessions, 100, '7', now);
    const fortnight = getInsightsPresentation(doses, sessions, 100, '14', now);

    expect(week.headline).toBe('11 mg/day');
    expect(fortnight.headline).toBe('21 mg/day');
    expect(week.adherence).toEqual({ pct: 100, streak: 1 });
    expect(fortnight.adherence).toEqual({ pct: 50, streak: 0 });
    expect(week.dayparts).toEqual([
      { label: 'Morning', mg: 0 },
      { label: 'Midday', mg: 80 },
      { label: 'Evening', mg: 0 },
      { label: 'Late', mg: 0 },
    ]);
    expect(fortnight.sourceMix).toEqual([
      { label: 'Energy', mg: 220, pct: 73 },
      { label: 'Tea', mg: 80, pct: 27 },
    ]);
    expect(week.vigilance.trendSessions.map((item) => item.id)).toEqual(['recent-session']);
    expect(fortnight.vigilance.trendSessions.map((item) => item.id)).toEqual(['older-session', 'recent-session']);
  });

  it('reports an honest empty range without fabricating recorded chart points', () => {
    const presentation = getInsightsPresentation([], [], 400, '30', now);

    expect(presentation.isEmpty).toBe(true);
    expect(presentation.headline).toBe('No Data');
    expect(presentation.points).toHaveLength(30);
    expect(presentation.points.every((point) => point.mg === null)).toBe(true);
    expect(presentation.accessibilitySummary).toContain('Caffeine intake');
    expect(presentation.accessibilitySummary).toContain('30 days');
    expect(presentation.accessibilitySummary).toContain('No caffeine data is available');
  });

  it('preserves source normalization, dayparts, adherence streak, and vigilance baseline rules', () => {
    const presentation = getInsightsPresentation(
      [
        dose('coffee', 0, 90, 'Cold brew', 6),
        dose('pills', 1, 50, 'Caffeine pill', 15),
        dose('other', 2, 30, undefined, 22),
        dose('over-limit', 3, 200, 'Energy', 18),
      ],
      [session('one', 0, 80), session('two', 1, 70), session('three', 2, 60)],
      100,
      '7',
      now,
    );

    expect(presentation.sourceMix).toEqual([
      { label: 'Energy', mg: 200, pct: 54 },
      { label: 'Coffee', mg: 90, pct: 24 },
      { label: 'Pills', mg: 50, pct: 14 },
      { label: 'Other', mg: 30, pct: 8 },
    ]);
    expect(presentation.dayparts).toEqual([
      { label: 'Morning', mg: 90 },
      { label: 'Midday', mg: 50 },
      { label: 'Evening', mg: 200 },
      { label: 'Late', mg: 30 },
    ]);
    expect(presentation.adherence).toEqual({ pct: 75, streak: 0 });
    expect(presentation.vigilance).toMatchObject({ averageScore: 70, hasBaseline: true });
  });
});
