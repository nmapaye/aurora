import type { SleepSession } from '~/domain/models';
import {
  getSleepPresentation,
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
});
