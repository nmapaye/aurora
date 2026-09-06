import {
  defaultSleepRoutines,
  normalizeSleepRoutines,
  scheduledSleep,
  nextScheduledSleep,
  overlapPairs,
  sleepHistory,
  sleepTrends,
} from '~/features/sleep/upgrades';
const time = (s: string) => new Date(s).getTime();
describe('sleep routines', () => {
  it('uses weekday and dated exceptions without changing the weekly plan', () => {
    const state = defaultSleepRoutines(8);
    state.weekly[1] = { bedtime: 23 * 60, wake: 7 * 60 };
    state.exceptions['2026-09-07'] = { bedtime: 21 * 60, wake: 5 * 60 };
    expect(scheduledSleep(state, '2026-09-07')).toEqual({
      bedtime: time('2026-09-07T21:00:00'),
      wake: time('2026-09-08T05:00:00'),
    });
    expect(state.weekly[1].bedtime).toBe(1380);
    expect(nextScheduledSleep(state, time('2026-09-07T21:01:00')).bedtime).toBe(
      time('2026-09-08T22:30:00'),
    );
  });
  it('normalizes malformed state and preserves a running timer and journal', () => {
    const state = normalizeSleepRoutines(
      {
        weekly: [],
        exceptions: { invalid: {} },
        timer: { start: 100, end: 200 },
        annotations: { health: { quality: 4, note: 'rested' } },
        windDown: { enabled: true, leadMinutes: 45 },
      },
      7,
    );
    expect(state.weekly[0]).toEqual({ bedtime: 1350, wake: 330 });
    expect(state.exceptions).toEqual({});
    expect(state.timer).toEqual({ start: 100, end: 200 });
    expect(state.annotations.health).toEqual({ quality: 4, note: 'rested' });
    expect(state.windDown).toEqual({ enabled: true, leadMinutes: 45 });
  });
  it('finds overlaps, filters journal notes and does not count overlapping samples twice', () => {
    const sessions = [
      {
        id: 'manual:sleep:a',
        start: time('2026-09-06T22:30:00'),
        end: time('2026-09-07T06:30:00'),
        type: 'sleep' as const,
      },
      {
        id: 'healthkit:sleep:b',
        start: time('2026-09-07T01:00:00'),
        end: time('2026-09-07T05:00:00'),
        type: 'sleep' as const,
      },
      {
        id: 'demo:sleep:c',
        start: time('2026-09-05T22:00:00'),
        end: time('2026-09-06T06:00:00'),
        type: 'sleep' as const,
      },
    ];
    expect(overlapPairs(sessions)).toHaveLength(1);
    expect(
      sleepHistory(
        sessions,
        { query: 'rested', source: 'Health', type: 'all' },
        { 'healthkit:sleep:b': { quality: 4, note: 'Rested' } },
        time('2026-09-07T12:00:00'),
      ),
    ).toEqual([sessions[1]]);
    const trends = sleepTrends(
      sessions,
      defaultSleepRoutines(8),
      8,
      time('2026-09-07T12:00:00'),
      7,
    );
    expect(trends.filter((d) => d.durationMs !== null)).toHaveLength(1);
    expect(trends[6]).toMatchObject({
      durationMs: 8 * 3600000,
      deficitMs: 0,
      bedtimeVariationMin: 0,
      wakeVariationMin: 0,
    });
  });
});
