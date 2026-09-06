import {
  defaultSleepRoutines,
  nextScheduledSleep,
  normalizeSleepRoutines,
  scheduledSleep,
  sleepHistory,
  sleepTrends,
} from '~/features/sleep/upgrades';
import type { SleepSession } from '~/domain/models';

const hour = 3_600_000;
const now = new Date(2026, 8, 7, 12).getTime();

describe('sleep schedule review', () => {
  it('derives the initial wake time from the existing duration target', () => {
    const schedule = defaultSleepRoutines(7.25);
    expect(scheduledSleep(schedule, '2026-09-07')).toEqual({
      bedtime: new Date(2026, 8, 7, 22, 30).getTime(),
      wake: new Date(2026, 8, 8, 5, 45).getTime(),
    });
  });

  it('applies an exception only to its bedtime date and supports daytime sleep', () => {
    const schedule = defaultSleepRoutines(8);
    schedule.exceptions['2026-09-07'] = { bedtime: 120, wake: 600 };
    expect(scheduledSleep(schedule, '2026-09-07')).toEqual({
      bedtime: new Date(2026, 8, 7, 2).getTime(),
      wake: new Date(2026, 8, 7, 10).getTime(),
    });
    expect(scheduledSleep(schedule, '2026-09-08').bedtime).toBe(
      new Date(2026, 8, 8, 22, 30).getTime(),
    );
    expect(schedule.weekly[1]).toEqual({ bedtime: 1350, wake: 390 });
  });

  it('resolves the next weekday after the current bedtime passes', () => {
    const schedule = defaultSleepRoutines(8);
    schedule.weekly[2] = { bedtime: 1380, wake: 420 };
    expect(
      nextScheduledSleep(schedule, new Date(2026, 8, 7, 23).getTime()),
    ).toEqual({
      bedtime: new Date(2026, 8, 8, 23).getTime(),
      wake: new Date(2026, 8, 9, 7).getTime(),
    });
  });

  it('preserves configured wall times through daylight-saving nights', () => {
    const schedule = defaultSleepRoutines(8);
    const spring = scheduledSleep(schedule, '2026-03-07');
    const fall = scheduledSleep(schedule, '2026-10-31');
    expect(spring.wake).toBe(new Date(2026, 2, 8, 6, 30).getTime());
    expect(fall.wake).toBe(new Date(2026, 10, 1, 6, 30).getTime());
    if (process.env.TZ === 'America/New_York') {
      expect(spring.wake - spring.bedtime).toBe(7 * hour);
      expect(fall.wake - fall.bedtime).toBe(9 * hour);
    }
  });

  (process.env.TZ === 'America/New_York' ? it : it.skip)(
    'keeps a sleep interval positive when its bedtime falls in the spring clock gap',
    () => {
      const schedule = defaultSleepRoutines(8);
      schedule.exceptions['2026-03-08'] = { bedtime: 150, wake: 180 };
      const planned = scheduledSleep(schedule, '2026-03-08');
      expect(planned.bedtime).toBe(new Date(2026, 2, 8, 3, 30).getTime());
      expect(planned.wake).toBe(new Date(2026, 2, 8, 4).getTime());
      expect(planned.wake - planned.bedtime).toBe(30 * 60_000);
    },
  );

  it.each([1e100, -1e100, null, true, '2026-09-07'])(
    'rejects malformed persisted nap start %p',
    (start) => {
      expect(normalizeSleepRoutines({ timer: { start } }, 8).timer).toBeNull();
    },
  );

  it('retains a stopped nap for confirmation through normalization', () => {
    const timer = { start: now - hour, end: now - hour / 2 };
    expect(normalizeSleepRoutines({ timer }, 8).timer).toEqual(timer);
  });
});

describe('personal sleep record review', () => {
  it('keeps missing days unmeasured and sample records out of trends', () => {
    const sample: SleepSession = {
      id: 'demo:sleep:1',
      start: now - 9 * hour,
      end: now - hour,
      type: 'sleep',
    };
    expect(
      sleepTrends([sample], defaultSleepRoutines(8), 8, now, 7).every(
        (day) => day.durationMs === null && day.deficitMs === null,
      ),
    ).toBe(true);
  });

  it('uses episode boundaries when Health imports split a night into segments', () => {
    const sessions: SleepSession[] = [
      {
        id: 'healthkit:sleep:a',
        start: new Date(2026, 8, 6, 22, 30).getTime(),
        end: new Date(2026, 8, 7, 1).getTime(),
        type: 'sleep',
      },
      {
        id: 'healthkit:sleep:b',
        start: new Date(2026, 8, 7, 1, 30).getTime(),
        end: new Date(2026, 8, 7, 6, 30).getTime(),
        type: 'sleep',
      },
    ];
    const day = sleepTrends(sessions, defaultSleepRoutines(8), 8, now, 7).at(
      -1,
    );
    expect(day).toMatchObject({
      durationMs: 7.5 * hour,
      deficitMs: 0.5 * hour,
      bedtimeVariationMin: 0,
      wakeVariationMin: 0,
    });
  });

  it('does not double-count a nap nested in an overnight import on a different wake date', () => {
    const sessions: SleepSession[] = [
      {
        id: 'healthkit:sleep:overnight',
        start: new Date(2026, 8, 6, 20).getTime(),
        end: new Date(2026, 8, 7, 8).getTime(),
        type: 'sleep',
      },
      {
        id: 'manual:sleep:nap',
        start: new Date(2026, 8, 6, 21).getTime(),
        end: new Date(2026, 8, 6, 22).getTime(),
        type: 'nap',
      },
    ];
    const days = sleepTrends(sessions, defaultSleepRoutines(8), 8, now, 7);
    expect(days.reduce((sum, day) => sum + (day.durationMs ?? 0), 0)).toBe(
      12 * hour,
    );
  });

  it('searches a separate Health annotation without modifying imported data', () => {
    const imported: SleepSession = {
      id: 'healthkit:sleep:one',
      start: now - 9 * hour,
      end: now - hour,
      type: 'sleep',
    };
    const annotations = { [imported.id]: { quality: 4, note: 'Quiet room' } };
    expect(
      sleepHistory(
        [imported],
        {
          query: 'quiet',
          source: 'Health',
          type: 'sleep',
          from: '2026-09-07',
          to: '2026-09-07',
        },
        annotations,
        now,
      ),
    ).toEqual([imported]);
    expect(imported.note).toBeUndefined();
  });
});
