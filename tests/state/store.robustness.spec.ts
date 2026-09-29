import { jsonStringStorage, kv, readJSONStringOrBackup } from '~/services/storage';
import { useStore } from '~/state/store';
import { HEALTH_SLEEP_RETENTION_DAYS } from '~/state/validate';

const NOW = 1_800_000_000_000;
const DAY = 24 * 3_600_000;
const health = (start: number, end: number) => ({
  id: `healthkit:sleep:${start}:${end}`,
  start,
  end,
  type: 'sleep' as const,
});

beforeEach(() => {
  jest.spyOn(Date, 'now').mockReturnValue(NOW);
  useStore.setState({ doses: [], sleeps: [], vigilanceSessions: [] });
});
afterEach(() => jest.restoreAllMocks());

describe('persisted state validation', () => {
  it('drops malformed items and non-array collections instead of crashing', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          doses: [
            { id: 'ok', timestamp: NOW, mg: 95 },
            { id: 'bad-mg', timestamp: NOW, mg: 'lots' },
            null,
          ],
          sleeps: { not: 'an array' },
          vigilanceSessions: [{ id: 'partial' }],
          prefs: { halfLife: 'x', cutoffHour: 15 },
        },
        version: 6,
      }),
    );

    await useStore.persist.rehydrate();

    const state = useStore.getState();
    expect(state.doses.map((dose) => dose.id)).toEqual(['ok']);
    expect(state.sleeps).toEqual([]);
    expect(state.vigilanceSessions).toEqual([]);
    expect(state.prefs.cutoffHour).toBe(15);
    expect(Number.isFinite(state.prefs.halfLife)).toBe(true);
  });

  it('relabels stored "Fatigued" reaction results with the softer rating', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          vigilanceSessions: [
            { id: 'v1', startedAt: NOW - 60_000, completedAt: NOW, score: 30, rating: 'Fatigued' },
          ],
        },
        version: 6,
      }),
    );

    await useStore.persist.rehydrate();

    expect(useStore.getState().vigilanceSessions[0].rating).toBe('Sluggish');
  });

  it('keeps a backup of a blob that no longer parses', () => {
    kv.set('aurora/test', '{"state": broken');

    expect(readJSONStringOrBackup('aurora/test', 42)).toBeNull();
    expect(kv.getString('aurora/test.corrupt.42')).toBe('{"state": broken');
  });
});

describe('Health sleep retention', () => {
  it(`trims Health sleep older than ${HEALTH_SLEEP_RETENTION_DAYS} days but keeps manual sleep`, () => {
    const old = NOW - (HEALTH_SLEEP_RETENTION_DAYS + 1) * DAY;
    const oldManual = { id: 'manual:sleep:1:a', start: old - 8 * 3_600_000, end: old, type: 'sleep' as const };

    useStore.setState({ sleeps: [oldManual] });
    useStore.getState().upsertSleepSessions([
      health(old - 8 * 3_600_000, old),
      health(NOW - DAY, NOW - DAY + 8 * 3_600_000),
    ]);

    expect(useStore.getState().sleeps.map((sleep) => sleep.id)).toEqual([
      `healthkit:sleep:${NOW - DAY}:${NOW - DAY + 8 * 3_600_000}`,
      oldManual.id,
    ]);
  });
});

describe('replaceHealthSleepWindow', () => {
  it('removes Health samples deleted in Health and keeps manual and out-of-window data', () => {
    const windowStart = NOW - 30 * DAY;
    const deleted = health(NOW - 2 * DAY, NOW - 2 * DAY + 7 * 3_600_000);
    const kept = health(NOW - DAY, NOW - DAY + 7 * 3_600_000);
    const beforeWindow = health(windowStart - 5 * DAY, windowStart - 5 * DAY + 7 * 3_600_000);
    const manual = { id: 'manual:sleep:2:b', start: NOW - 3 * DAY, end: NOW - 3 * DAY + 3_600_000, type: 'nap' as const };
    useStore.setState({ sleeps: [deleted, kept, beforeWindow, manual] });

    useStore.getState().replaceHealthSleepWindow([kept], windowStart, NOW);

    expect(useStore.getState().sleeps.map((sleep) => sleep.id).sort()).toEqual(
      [kept.id, beforeWindow.id, manual.id].sort(),
    );
  });
});
