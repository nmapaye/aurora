import type { SleepSession } from '~/domain/models';
import {
  getCaffeineImpact,
  getSleepPresentation,
  getLocalCalendarDayStarts,
  sleepSourceLabel,
} from '~/features/sleep/presentation';

const now = Date.parse('2026-07-24T12:00:00.000Z');
const hour = 60 * 60 * 1000;
const sleep = (id: string, daysAgo: number, durationHours = 8): SleepSession => ({
  id,
  start: now - daysAgo * 24 * hour - durationHours * hour,
  end: now - daysAgo * 24 * hour,
  type: 'sleep',
});

describe('sleep presentation', () => {
  it('labels manual and imported sessions without relying on user-entered copy', () => {
    expect(sleepSourceLabel('manual:sleep:1')).toBe('Manual');
    expect(sleepSourceLabel('healthkit:sleep:1')).toBe('Health');
    expect(sleepSourceLabel('demo:sleep:1')).toBe('Sample Data');
  });

  it('uses a seven-day week window and does not fabricate missing data', () => {
    const presentation = getSleepPresentation(
      [sleep('manual:sleep:recent', 1), sleep('manual:sleep:old', 8)],
      8,
      'week',
      now,
    );

    expect(presentation.days).toBe(7);
    expect(presentation.points).toHaveLength(7);
    expect(presentation.points.filter((point) => point.durationMs !== null)).toEqual([
      expect.objectContaining({ durationMs: 8 * hour }),
    ]);
    expect(presentation.accessibilitySummary).toContain('7 days');
    expect(presentation.accessibilitySummary).toContain('1 night recorded');
  });

  it('uses a 30-day month window and reports an honest empty state', () => {
    const presentation = getSleepPresentation([], 8, 'month', now);

    expect(presentation.days).toBe(30);
    expect(presentation.points).toHaveLength(30);
    expect(presentation.points.every((point) => point.durationMs === null)).toBe(true);
    expect(presentation.headline).toBe('No Data');
    expect(presentation.accessibilitySummary).toContain('No sleep data');
  });

  it('summarizes last night with wake time and target difference', () => {
    const presentation = getSleepPresentation([sleep('manual:sleep:last', 1, 7.5)], 8, 'week', now);

    expect(presentation.lastNight).toEqual(
      expect.objectContaining({
        durationMs: 7.5 * hour,
        targetDifferenceMs: -0.5 * hour,
      }),
    );
    expect(presentation.headline).toBe('7h 30m');
  });

  it('does not borrow the headline or highlights from outside the selected range', () => {
    const presentation = getSleepPresentation([sleep('manual:sleep:old', 8, 9)], 8, 'week', now);

    expect(presentation.headline).toBe('No Data');
    expect(presentation.lastNight).toBeNull();
  });

  it('builds calendar days safely across a daylight-saving transition', () => {
    const previousZone = process.env.TZ;
    process.env.TZ = 'America/New_York';
    const starts = getLocalCalendarDayStarts(Date.parse('2026-03-09T12:00:00-04:00'), 3);
    process.env.TZ = previousZone;

    expect(starts.map((timestamp) => new Date(timestamp).getDate())).toEqual([7, 8, 9]);
    expect(starts.map((timestamp) => new Date(timestamp).getHours())).toEqual([0, 0, 0]);
  });

  it('derives caffeine impact from one qualifying dose-to-sleep pair per local night', () => {
    const sessions: SleepSession[] = [
      sleep('manual:sleep:first', 1, 8),
      { ...sleep('manual:sleep:first-duplicate', 1, 1), start: now - 25 * hour, end: now - 24 * hour },
      sleep('manual:sleep:second', 2, 7),
    ];
    const impact = getCaffeineImpact(
      sessions,
      [
        { id: 'dose:1', timestamp: now - 1 * 24 * hour - 11 * hour, mg: 80 },
        { id: 'dose:2', timestamp: now - 2 * 24 * hour - 11 * hour, mg: 95 },
      ],
      'week',
      now,
    );

    expect(impact).toMatchObject({
      qualifyingNights: 2,
      medianDeltaMin: 240,
      p10: 180,
      p90: 240,
      medianSleepMin: 480,
      showCorrelation: false,
    });
  });

  it('withholds pattern language until 14 distinct qualifying local nights', () => {
    const sessions = Array.from({ length: 14 }, (_, index) => sleep(`manual:sleep:${index}`, index + 1));
    const doses = sessions.map((session, index) => ({
      id: `dose:${index}`,
      timestamp: session.start - 3 * hour,
      mg: 80,
    }));

    expect(getCaffeineImpact(sessions, doses, 'month', now)).toMatchObject({
      qualifyingNights: 14,
      showCorrelation: true,
      medianDeltaMin: 180,
    });
  });
});
