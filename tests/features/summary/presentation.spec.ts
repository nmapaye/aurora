import { alertnessScore } from '~/domain/algorithm/alertness';
import {
  describeAlertnessEstimate,
  describeCaffeineDay,
  describeInspection,
  estimateAlertness,
  inspectCaffeinePoint,
  nearestIndex,
  nowIndex,
} from '~/features/summary/presentation';

const now = new Date(2026, 8, 26, 14, 0).getTime();
const hour = 60 * 60 * 1000;
const dayStart = new Date(2026, 8, 26, 0, 0).getTime();
const dayEnd = new Date(2026, 8, 27, 0, 0).getTime();
const prefs = { halfLife: 5, targetSleep: 8 };
const nightSleep = { start: now - 14 * hour, end: now - 7 * hour };
const time = (ts: number) => `${new Date(ts).getHours()}h`;

describe('summary presentation', () => {
  it('returns the existing model score, rounded, when recent sleep exists', () => {
    const doses = [{ timestamp: now - 2 * hour, mg: 95 }];
    const estimate = estimateAlertness(now, doses, [nightSleep], prefs);

    expect(estimate).toEqual({
      status: 'estimated',
      score: Math.round(alertnessScore(now, doses, [nightSleep], prefs)),
      sleepHours: 7,
      includesSample: false,
    });
    expect(describeAlertnessEstimate(estimate)).toMatch(
      /^Estimated alertness \d+ out of 100\..*7h 0m.*estimate, not a measurement\.$/,
    );
  });

  it('flags an estimate built partly from Sample Data', () => {
    const estimate = estimateAlertness(
      now,
      [{ id: 'real', timestamp: now - 2 * hour, mg: 95 }],
      [{ id: 'demo:night', ...nightSleep }],
      prefs,
    );

    expect(estimate).toMatchObject({ status: 'estimated', includesSample: true });
    expect(describeAlertnessEstimate(estimate)).toContain('Includes Sample Data.');
    expect(
      estimateAlertness(now, [], [{ id: 'manual:sleep:1:a', ...nightSleep }], prefs),
    ).toMatchObject({ includesSample: false });
  });

  it('returns no score without sleep in the last 24 hours', () => {
    const staleSleep = { start: now - 40 * hour, end: now - 32 * hour };

    expect(estimateAlertness(now, [], [], prefs)).toEqual({
      status: 'needs-sleep',
    });
    expect(estimateAlertness(now, [], [staleSleep], prefs)).toEqual({
      status: 'needs-sleep',
    });
    expect(describeAlertnessEstimate({ status: 'needs-sleep' })).toContain(
      'unavailable',
    );
  });

  it('snaps inspection to the nearest point and defaults to now', () => {
    expect(nearestIndex([0, 10, 20, 30], 14)).toBe(1);
    expect(nearestIndex([0, 10, 20, 30], 16)).toBe(2);
    expect(nearestIndex([0, 10, 20, 30], -50)).toBe(0);
    expect(nearestIndex([0, 10, 20, 30], 500)).toBe(3);
    expect(nearestIndex([], 5)).toBe(-1);
    expect(
      nowIndex([{ t: now - hour }, { t: now }, { t: now + hour }], now),
    ).toBe(1);
  });

  it('separates modeled caffeine from logged records at the inspected time', () => {
    const doses = [
      { timestamp: dayStart - hour, mg: 200 },
      { timestamp: now - 3 * hour, mg: 95 },
      { timestamp: now - hour, mg: 60 },
    ];
    const atNoon = inspectCaffeinePoint({
      point: { t: now - 2 * hour, mg: 120 },
      doses,
      sleeps: [nightSleep],
      prefs,
      dayStart,
      now,
    });

    expect(atNoon).toMatchObject({
      isNow: false,
      isFuture: false,
      activeMg: 120,
      loggedMg: 95,
      loggedCount: 1,
      alertness: { status: 'estimated' },
    });
    expect(describeInspection(atNoon, time)).toBe(
      `12h: modeled active caffeine 120 milligrams, 95 milligrams logged today by then in 1 dose, estimated alertness ${
        (atNoon.alertness as { score: number }).score
      }.`,
    );

    const later = inspectCaffeinePoint({
      point: { t: now + 3 * hour, mg: 40 },
      doses,
      sleeps: [],
      prefs,
      dayStart,
      now,
    });
    expect(later).toMatchObject({
      isFuture: true,
      loggedMg: 155,
      loggedCount: 2,
      alertness: { status: 'needs-sleep' },
    });
    expect(describeInspection(later, time)).toBe(
      '17h: projected active caffeine 40 milligrams, 155 milligrams logged today by then in 2 doses, alertness needs recent sleep.',
    );
  });

  it('summarizes the day for assistive technology without inventing doses', () => {
    expect(
      describeCaffeineDay({
        series: [
          { t: dayStart, mg: 0 },
          { t: dayEnd, mg: 0 },
        ],
        doses: [],
        dayStart,
        dayEnd,
        formatTime: time,
      }),
    ).toBe(
      'Active caffeine today chart. No caffeine logged today. Modeled active caffeine stays at 0 milligrams.',
    );

    expect(
      describeCaffeineDay({
        series: [
          { t: dayStart + 8 * hour, mg: 10 },
          { t: dayStart + 9 * hour, mg: 142.4 },
          { t: dayStart + 12 * hour, mg: 90 },
        ],
        doses: [
          { timestamp: dayStart + 8.5 * hour, mg: 95 },
          { timestamp: dayStart + 9 * hour, mg: 60 },
          { timestamp: dayEnd + hour, mg: 160 },
        ],
        dayStart,
        dayEnd,
        formatTime: time,
      }),
    ).toBe(
      'Active caffeine today chart. 2 doses logged today, 155 milligrams total. Modeled active caffeine peaks at 142 milligrams at 9h.',
    );
  });
});
