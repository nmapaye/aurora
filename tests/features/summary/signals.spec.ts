import type { VigilanceSession } from '~/domain/vigilance';
import { describeSignal, signalMetaLine } from '~/features/signals/model';
import {
  caffeineLoggedSignal,
  reactionTestSignal,
  sleepSignal,
} from '~/features/summary/signals';

const at = (day: number, hour: number, minute = 0) =>
  new Date(2026, 8, day, hour, minute).getTime();
const now = at(26, 14);
const time = (ts: number) => `${new Date(ts).getHours()}h`;

function vigilance(
  overrides: Partial<VigilanceSession> & Pick<VigilanceSession, 'id' | 'completedAt'>,
): VigilanceSession {
  return {
    startedAt: overrides.completedAt - 60_000,
    durationMs: 60_000,
    trialCount: 14,
    validReactionCount: 13,
    falseStartCount: 0,
    lapseCount: 0,
    medianReactionMs: 281.4,
    meanReactionMs: 290,
    fastestReactionMs: 220,
    reactionStdDevMs: 40,
    score: 74,
    rating: 'Steady',
    ...overrides,
  };
}

describe('Summary pinned signals', () => {
  describe('Caffeine Logged', () => {
    it('is a quiet empty signal when nothing is logged today', () => {
      const signal = caffeineLoggedSignal(
        [
          { id: 'dose-yesterday', timestamp: at(25, 9), mg: 95 },
          // Entries later today have not happened yet.
          { id: 'dose-later', timestamp: at(26, 18), mg: 60 },
        ],
        now,
      );

      expect(signal).toMatchObject({
        status: 'empty',
        label: 'Caffeine Logged',
        period: 'Today',
        context: 'Nothing logged yet today.',
        destination: 'Log Caffeine',
      });
      // Older history does not change the offer.
      expect(signal.value).toBeUndefined();
      expect(describeSignal(signal)).toBe(
        'Caffeine Logged, No data, Nothing logged yet today.',
      );
    });

    it('offers Log Caffeine when nothing has ever been logged', () => {
      const signal = caffeineLoggedSignal([], now);

      expect(signal).toMatchObject({
        status: 'empty',
        destination: 'Log Caffeine',
      });
    });

    it('offers Open Log once something is logged today', () => {
      const signal = caffeineLoggedSignal(
        [{ id: 'a', timestamp: at(26, 8), mg: 95 }],
        now,
      );

      expect(signal.destination).toBe('Open Log');
    });

    it('totals today’s manual entries with their count and latest time', () => {
      const signal = caffeineLoggedSignal(
        [
          { id: 'a', timestamp: at(26, 8), mg: 95 },
          { id: 'b', timestamp: at(26, 12, 30), mg: 60 },
        ],
        now,
        time,
      );

      expect(signal).toMatchObject({
        status: 'observed',
        value: '155 mg',
        source: 'Manual',
        context: '2 entries · last at 12h',
      });
      expect(signalMetaLine(signal)).toBe('Today · Manual');
    });

    it('labels sample entries as sample data', () => {
      expect(
        caffeineLoggedSignal(
          [{ id: 'demo:dose:0', timestamp: at(26, 8), mg: 95 }],
          now,
          time,
        ),
      ).toMatchObject({
        status: 'sample',
        source: 'Sample Data',
        context: '1 entry · last at 8h',
      });
      expect(
        caffeineLoggedSignal(
          [
            { id: 'demo:dose:0', timestamp: at(26, 8), mg: 95 },
            { id: 'real', timestamp: at(26, 9), mg: 60 },
          ],
          now,
        ),
      ).toMatchObject({ status: 'observed', source: 'Manual and Sample Data' });
    });
  });

  describe('Sleep', () => {
    it('is empty without sleep in the last 7 days, even with older sleep', () => {
      const signal = sleepSignal(
        [
          {
            id: 'manual:sleep:old',
            start: at(10, 23),
            end: at(11, 7),
            type: 'sleep',
          },
        ],
        8,
        now,
      );

      expect(signal).toMatchObject({
        status: 'empty',
        period: 'Last 7 days',
        context: 'None recorded in the last 7 days.',
        destination: 'Add Sleep',
      });
    });

    it('reads fragmented Health samples as one night with its source', () => {
      const signal = sleepSignal(
        [
          {
            id: 'healthkit:sleep:1',
            start: at(25, 23),
            end: at(26, 2),
            type: 'sleep',
          },
          {
            id: 'healthkit:sleep:2',
            start: at(26, 2, 20),
            end: at(26, 6, 30),
            type: 'sleep',
          },
        ],
        8,
        now,
        time,
      );

      expect(signal).toMatchObject({
        status: 'observed',
        period: 'Today',
        source: 'Health',
        value: '7h 10m',
        context: '23h – 6h',
        destination: 'Open Sleep',
      });
    });

    it('says when the latest night is not recent and labels sample and manual sources', () => {
      expect(
        sleepSignal(
          [
            {
              id: 'demo:sleep:3',
              start: at(22, 23),
              end: at(23, 7),
              type: 'sleep',
            },
          ],
          8,
          now,
          time,
        ),
      ).toMatchObject({
        status: 'sample',
        source: 'Sample Data',
        context: 'Latest night recorded · 23h – 7h',
      });
      expect(
        sleepSignal(
          [
            {
              id: 'manual:sleep:1',
              start: at(24, 23),
              end: at(25, 7),
              type: 'sleep',
            },
          ],
          8,
          now,
          time,
        ),
      ).toMatchObject({
        status: 'observed',
        period: 'Yesterday',
        source: 'Manual',
        context: '23h – 7h',
      });
    });
  });

  describe('Reaction Test', () => {
    it('is empty before any test', () => {
      expect(reactionTestSignal([], now)).toMatchObject({
        status: 'empty',
        label: 'Reaction Test',
        destination: 'Take Reaction Test',
      });
    });

    it('shows the latest completed test with rating and median', () => {
      const signal = reactionTestSignal(
        [
          vigilance({ id: 'old', completedAt: at(20, 9), score: 60 }),
          vigilance({ id: 'latest', completedAt: at(25, 9) }),
          // Sample sessions can be timestamped later today.
          vigilance({ id: 'demo:vigilance:0', completedAt: at(26, 15) }),
        ],
        now,
      );

      expect(signal).toMatchObject({
        status: 'observed',
        period: 'Yesterday',
        value: '74',
        context: 'Steady · 281 ms median',
      });
      expect(signal.source).toBeUndefined();
    });

    it('labels a sample session and tolerates a missing median', () => {
      expect(
        reactionTestSignal(
          [
            vigilance({
              id: 'demo:vigilance:1',
              completedAt: at(26, 9),
              medianReactionMs: null,
            }),
          ],
          now,
        ),
      ).toMatchObject({
        status: 'sample',
        source: 'Sample Data',
        period: 'Today',
        context: 'Steady',
      });
    });
  });
});
