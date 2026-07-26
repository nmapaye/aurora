import type { SleepSession } from '~/domain/models';
import {
  getCaffeineImpact,
  getSleepPresentation,
  sleepSourceLabel,
} from '~/features/sleep/presentation';

const now = Date.parse('2026-07-24T12:00:00.000Z');
const hour = 60 * 60 * 1000;
const minute = 60 * 1000;
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

  it('buckets pre- and post-midnight fragments into one wake-day episode', () => {
    const firstStart = new Date(2026, 6, 23, 22, 0).getTime();
    const firstEnd = new Date(2026, 6, 23, 23, 30).getTime();
    const secondStart = new Date(2026, 6, 23, 23, 45).getTime();
    const secondEnd = new Date(2026, 6, 24, 6, 0).getTime();
    const sessions: SleepSession[] = [
      { id: 'healthkit:sleep:first', start: firstStart, end: firstEnd, type: 'sleep' },
      { id: 'healthkit:sleep:second', start: secondStart, end: secondEnd, type: 'sleep' },
    ];

    const presentation = getSleepPresentation(sessions, 8, 'week', now);
    const impact = getCaffeineImpact(
      sessions,
      [{ id: 'dose:evening', timestamp: new Date(2026, 6, 23, 20, 0).getTime(), mg: 80 }],
      'week',
      now,
    );

    expect(presentation.lastNight).toMatchObject({
      durationMs: 7.75 * hour,
      sleepStart: firstStart,
      wakeTime: secondEnd,
      targetDifferenceMs: -0.25 * hour,
    });
    expect(presentation.headline).toBe('7h 45m');
    expect(
      presentation.points.filter((point) => point.durationMs !== null),
    ).toHaveLength(1);
    expect(impact).toMatchObject({
      qualifyingNights: 1,
      medianDeltaMin: 120,
      medianSleepMin: 465,
    });
  });

  it('keeps a genuinely separate nap out of the overnight episode', () => {
    const napStart = new Date(2026, 6, 23, 14, 0).getTime();
    const napEnd = new Date(2026, 6, 23, 15, 0).getTime();
    const sleepStart = new Date(2026, 6, 23, 22, 0).getTime();
    const sleepEnd = new Date(2026, 6, 24, 6, 0).getTime();
    const sessions: SleepSession[] = [
      { id: 'manual:sleep:nap', start: napStart, end: napEnd, type: 'nap' },
      { id: 'manual:sleep:overnight', start: sleepStart, end: sleepEnd, type: 'sleep' },
    ];
    const impact = getCaffeineImpact(
      sessions,
      [
        { id: 'dose:nap', timestamp: napStart - 2 * hour, mg: 40 },
        { id: 'dose:overnight', timestamp: sleepStart - 3 * hour, mg: 80 },
      ],
      'week',
      now,
    );

    expect(getSleepPresentation(sessions, 8, 'week', now).lastNight).toMatchObject({
      durationMs: 8 * hour,
      sleepStart,
      wakeTime: sleepEnd,
    });
    expect(impact).toMatchObject({
      qualifyingNights: 1,
      medianDeltaMin: 180,
      medianSleepMin: 480,
    });
  });

  it('keeps a later same-type nap separate from the primary overnight episode', () => {
    const sleepStart = new Date(2026, 6, 23, 22, 0).getTime();
    const sleepEnd = new Date(2026, 6, 24, 6, 0).getTime();
    const napStart = new Date(2026, 6, 24, 7, 30).getTime();
    const napEnd = new Date(2026, 6, 24, 9, 0).getTime();
    const presentationNow = new Date(2026, 6, 24, 12, 0).getTime();
    const sessions: SleepSession[] = [
      { id: 'healthkit:sleep:overnight', start: sleepStart, end: sleepEnd, type: 'sleep' },
      { id: 'healthkit:sleep:later-nap', start: napStart, end: napEnd, type: 'sleep' },
    ];

    const presentation = getSleepPresentation(sessions, 8, 'week', presentationNow);
    const impact = getCaffeineImpact(
      sessions,
      [{ id: 'dose:evening', timestamp: sleepStart - 3 * hour, mg: 80 }],
      'week',
      presentationNow,
    );

    expect(presentation.headline).toBe('8h 0m');
    expect(presentation.lastNight).toMatchObject({
      durationMs: 8 * hour,
      sleepStart,
      wakeTime: sleepEnd,
      targetDifferenceMs: 0,
    });
    expect(
      presentation.points.find((point) => point.date === new Date(2026, 6, 24).getTime()),
    ).toMatchObject({ durationMs: 9.5 * hour });
    expect(impact).toMatchObject({
      qualifyingNights: 1,
      medianDeltaMin: 180,
      medianSleepMin: 480,
    });
  });

  it.each([
    {
      boundary: 'just below',
      gapMs: 90 * minute - 1,
      expectedDurationMs: 7 * hour,
      expectedWake: 'second',
    },
    {
      boundary: 'at',
      gapMs: 90 * minute,
      expectedDurationMs: 4 * hour,
      expectedWake: 'first',
    },
    {
      boundary: 'just above',
      gapMs: 90 * minute + 1,
      expectedDurationMs: 4 * hour,
      expectedWake: 'first',
    },
  ])(
    'uses a strict episode gap cutoff $boundary 90 minutes',
    ({ gapMs, expectedDurationMs, expectedWake }) => {
      const firstStart = new Date(2026, 6, 23, 22, 0).getTime();
      const firstEnd = firstStart + 4 * hour;
      const secondStart = firstEnd + gapMs;
      const secondEnd = secondStart + 3 * hour;
      const presentation = getSleepPresentation([
        { id: 'healthkit:sleep:first', start: firstStart, end: firstEnd, type: 'sleep' },
        { id: 'healthkit:sleep:second', start: secondStart, end: secondEnd, type: 'sleep' },
      ], 8, 'week', now);

      expect(presentation.lastNight).toMatchObject({
        durationMs: expectedDurationMs,
        sleepStart: firstStart,
        wakeTime: expectedWake === 'second' ? secondEnd : firstEnd,
      });
      expect(
        presentation.points.find((point) => point.date === new Date(2026, 6, 24).getTime()),
      ).toMatchObject({ durationMs: 7 * hour });
    },
  );

  it('unions cross-type overlap once in the daily chart', () => {
    const sleepStart = new Date(2026, 6, 23, 22, 0).getTime();
    const sleepEnd = new Date(2026, 6, 24, 6, 0).getTime();
    const napStart = new Date(2026, 6, 24, 5, 0).getTime();
    const napEnd = new Date(2026, 6, 24, 7, 0).getTime();
    const presentation = getSleepPresentation([
      { id: 'manual:sleep:overnight', start: sleepStart, end: sleepEnd, type: 'sleep' },
      { id: 'manual:sleep:nap', start: napStart, end: napEnd, type: 'nap' },
    ], 8, 'week', now);

    expect(presentation.lastNight).toMatchObject({
      durationMs: 8 * hour,
      sleepStart,
      wakeTime: sleepEnd,
    });
    expect(
      presentation.points.find((point) => point.date === new Date(2026, 6, 24).getTime()),
    ).toMatchObject({ durationMs: 9 * hour });
  });

  it('keeps same-type fragments together when another type is interleaved', () => {
    const firstStart = new Date(2026, 6, 23, 22, 0).getTime();
    const firstEnd = new Date(2026, 6, 24, 1, 0).getTime();
    const secondStart = new Date(2026, 6, 24, 1, 30).getTime();
    const secondEnd = new Date(2026, 6, 24, 6, 0).getTime();
    const presentation = getSleepPresentation([
      { id: 'healthkit:sleep:first', start: firstStart, end: firstEnd, type: 'sleep' },
      {
        id: 'manual:sleep:overlapping-nap',
        start: new Date(2026, 6, 24, 0, 0).getTime(),
        end: new Date(2026, 6, 24, 0, 30).getTime(),
        type: 'nap',
      },
      { id: 'healthkit:sleep:second', start: secondStart, end: secondEnd, type: 'sleep' },
    ], 8, 'week', now);

    expect(presentation.lastNight).toMatchObject({
      durationMs: 7.5 * hour,
      sleepStart: firstStart,
      wakeTime: secondEnd,
    });
    expect(
      presentation.points.find((point) => point.date === new Date(2026, 6, 24).getTime()),
    ).toMatchObject({ durationMs: 7.5 * hour });
  });

  it('assigns a cross-midnight episode to its wake day before applying the range edge', () => {
    const earliestWakeDay = new Date(2026, 6, 18, 0, 0).getTime();
    const firstStart = new Date(2026, 6, 17, 22, 0).getTime();
    const firstEnd = new Date(2026, 6, 17, 23, 30).getTime();
    const secondStart = new Date(2026, 6, 17, 23, 45).getTime();
    const secondEnd = new Date(2026, 6, 18, 6, 0).getTime();

    const presentation = getSleepPresentation([
      { id: 'healthkit:sleep:edge-1', start: firstStart, end: firstEnd, type: 'sleep' },
      { id: 'healthkit:sleep:edge-2', start: secondStart, end: secondEnd, type: 'sleep' },
    ], 8, 'week', now);

    expect(
      presentation.points.find((point) => point.date === earliestWakeDay),
    ).toMatchObject({ durationMs: 7.75 * hour });
    expect(presentation.lastNight).toMatchObject({
      sleepStart: firstStart,
      wakeTime: secondEnd,
    });
  });

  it('does not double-count overlapping same-night samples', () => {
    const start = new Date(2026, 6, 23, 22, 0).getTime();
    const end = new Date(2026, 6, 24, 6, 0).getTime();
    const sessions: SleepSession[] = [
      { id: 'healthkit:sleep:first', start, end: new Date(2026, 6, 24, 3, 0).getTime(), type: 'sleep' },
      { id: 'healthkit:sleep:second', start: new Date(2026, 6, 24, 1, 0).getTime(), end, type: 'sleep' },
    ];

    const presentation = getSleepPresentation(sessions, 8, 'week', now);

    expect(presentation.lastNight).toMatchObject({
      durationMs: 8 * hour,
      sleepStart: start,
      wakeTime: end,
      targetDifferenceMs: 0,
    });
  });

  it('does not borrow the headline or highlights from outside the selected range', () => {
    const presentation = getSleepPresentation([sleep('manual:sleep:old', 8, 9)], 8, 'week', now);

    expect(presentation.headline).toBe('No Data');
    expect(presentation.lastNight).toBeNull();
  });

  it('aggregates elapsed intervals across a spring-forward night from absolute instants', () => {
    const dstNow = Date.parse('2026-03-08T12:00:00-04:00');
    const firstStart = Date.parse('2026-03-07T22:00:00-05:00');
    const firstEnd = Date.parse('2026-03-08T01:30:00-05:00');
    const secondStart = Date.parse('2026-03-08T03:00:00-04:00');
    const secondEnd = Date.parse('2026-03-08T06:30:00-04:00');
    const presentation = getSleepPresentation([
      { id: 'healthkit:sleep:dst-1', start: firstStart, end: firstEnd, type: 'sleep' },
      { id: 'healthkit:sleep:dst-2', start: secondStart, end: secondEnd, type: 'sleep' },
    ], 8, 'week', dstNow);

    expect(presentation.lastNight).toMatchObject({
      durationMs: 7 * hour,
      sleepStart: firstStart,
      wakeTime: secondEnd,
      targetDifferenceMs: -hour,
    });
  });

  it('aggregates elapsed intervals across a fall-back night from absolute instants', () => {
    const dstNow = Date.parse('2026-11-01T12:00:00-05:00');
    const firstStart = Date.parse('2026-10-31T22:00:00-04:00');
    const firstEnd = Date.parse('2026-11-01T01:30:00-04:00');
    const secondStart = Date.parse('2026-11-01T01:30:00-05:00');
    const secondEnd = Date.parse('2026-11-01T05:00:00-05:00');
    const presentation = getSleepPresentation([
      { id: 'healthkit:sleep:dst-fall-1', start: firstStart, end: firstEnd, type: 'sleep' },
      { id: 'healthkit:sleep:dst-fall-2', start: secondStart, end: secondEnd, type: 'sleep' },
    ], 8, 'week', dstNow);

    expect(presentation.lastNight).toMatchObject({
      durationMs: 7 * hour,
      sleepStart: firstStart,
      wakeTime: secondEnd,
      targetDifferenceMs: -hour,
    });
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
