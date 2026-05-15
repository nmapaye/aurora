import { DEFAULT_HALFLIFE_H, DEFAULT_TARGET_SLEEP_H } from '~/domain/constants';
import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';

function resetStore() {
  useStore.setState({
    doses: [],
    sleeps: [],
    vigilanceSessions: [],
    prefs: {
      halfLife: DEFAULT_HALFLIFE_H,
      targetSleep: DEFAULT_TARGET_SLEEP_H,
      dailyLimitMg: 400,
      cutoffHour: 16,
    },
    onboarding: {
      completed: false,
      source: 'healthkit',
      permissionStatus: 'idle',
    },
    healthSync: { importedCount: 0 },
    demoMode: false,
  });
}

describe('sample data store actions', () => {
  beforeEach(() => {
    resetStore();
  });

  it('loads deterministic demo records and completes onboarding', () => {
    useStore.getState().loadDemoData();

    const state = useStore.getState();
    expect(state.demoMode).toBe(true);
    expect(state.onboarding.completed).toBe(true);
    expect(state.onboarding.source).toBe('manual');
    expect(state.healthSync.importedCount).toBeGreaterThan(0);
    expect(state.doses.every((dose) => dose.id.startsWith('demo:'))).toBe(true);
    expect(state.sleeps.every((sleep) => sleep.id.startsWith('demo:'))).toBe(true);
    expect(
      state.vigilanceSessions.every((session) => session.id.startsWith('demo:'))
    ).toBe(true);
  });

  it('replaces existing sample records when sample data is loaded repeatedly', () => {
    useStore.setState({
      doses: [{ id: 'user:dose', timestamp: Date.now(), mg: 95, source: 'Drip' }],
      sleeps: [
        {
          id: 'user:sleep',
          start: Date.now() - 8 * 3_600_000,
          end: Date.now() - 1 * 3_600_000,
          type: 'sleep',
        },
      ],
      vigilanceSessions: [
        {
          id: 'user:vigilance',
          startedAt: Date.now() - 60_000,
          completedAt: Date.now(),
          durationMs: 60_000,
          trialCount: 1,
          validReactionCount: 1,
          falseStartCount: 0,
          lapseCount: 0,
          medianReactionMs: 250,
          meanReactionMs: 250,
          fastestReactionMs: 250,
          reactionStdDevMs: 0,
          score: 90,
          rating: 'Sharp',
        },
      ],
    });

    useStore.getState().loadDemoData();
    const once = useStore.getState();
    const counts = {
      doses: once.doses.length,
      sleeps: once.sleeps.length,
      vigilanceSessions: once.vigilanceSessions.length,
    };

    useStore.getState().loadDemoData();

    const state = useStore.getState();
    expect(state.doses).toHaveLength(counts.doses);
    expect(state.sleeps).toHaveLength(counts.sleeps);
    expect(state.vigilanceSessions).toHaveLength(counts.vigilanceSessions);
    expect(new Set(state.doses.map((dose) => dose.id)).size).toBe(state.doses.length);
    expect(new Set(state.sleeps.map((sleep) => sleep.id)).size).toBe(state.sleeps.length);
    expect(new Set(state.vigilanceSessions.map((session) => session.id)).size).toBe(
      state.vigilanceSessions.length
    );
    expect(state.doses.filter((dose) => dose.id === 'user:dose')).toHaveLength(1);
    expect(state.sleeps.filter((sleep) => sleep.id === 'user:sleep')).toHaveLength(1);
    expect(state.vigilanceSessions.filter((session) => session.id === 'user:vigilance')).toHaveLength(1);
  });

  it('clears demo records without deleting user records', () => {
    useStore.setState({
      doses: [
        { id: 'user:dose', timestamp: Date.now(), mg: 95, source: 'Drip' },
        { id: 'demo:stale-dose', timestamp: Date.now(), mg: 60, source: 'Old demo' },
      ],
      sleeps: [
        {
          id: 'user:sleep',
          start: Date.now() - 8 * 3_600_000,
          end: Date.now() - 1 * 3_600_000,
          type: 'sleep',
        },
        {
          id: 'demo:stale-sleep',
          start: Date.now() - 9 * 3_600_000,
          end: Date.now() - 2 * 3_600_000,
          type: 'sleep',
        },
      ],
      vigilanceSessions: [
        {
          id: 'user:vigilance',
          startedAt: Date.now() - 60_000,
          completedAt: Date.now(),
          durationMs: 60_000,
          trialCount: 1,
          validReactionCount: 1,
          falseStartCount: 0,
          lapseCount: 0,
          medianReactionMs: 250,
          meanReactionMs: 250,
          fastestReactionMs: 250,
          reactionStdDevMs: 0,
          score: 90,
          rating: 'Sharp',
        },
        {
          id: 'demo:stale-vigilance',
          startedAt: Date.now() - 120_000,
          completedAt: Date.now() - 60_000,
          durationMs: 60_000,
          trialCount: 1,
          validReactionCount: 1,
          falseStartCount: 0,
          lapseCount: 0,
          medianReactionMs: 275,
          meanReactionMs: 275,
          fastestReactionMs: 275,
          reactionStdDevMs: 0,
          score: 70,
          rating: 'Steady',
        },
      ],
    });

    useStore.getState().loadDemoData();
    useStore.getState().clearDemoData();

    const state = useStore.getState();
    expect(state.demoMode).toBe(false);
    expect(state.doses).toHaveLength(1);
    expect(state.doses[0].id).toBe('user:dose');
    expect(state.sleeps).toHaveLength(1);
    expect(state.sleeps[0].id).toBe('user:sleep');
    expect(state.vigilanceSessions).toHaveLength(1);
    expect(state.vigilanceSessions[0].id).toBe('user:vigilance');
  });

  it('hydrates default health sync and demo mode for same-version persisted states missing those fields', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          doses: [{ id: 'user:dose', timestamp: 1, mg: 95, source: 'Drip' }],
          sleeps: [],
          vigilanceSessions: [],
          prefs: { halfLife: 4 },
          onboarding: { completed: true },
        },
        version: 3,
      })
    );

    await useStore.persist.rehydrate();

    const state = useStore.getState();
    expect(state.doses).toHaveLength(1);
    expect(state.healthSync).toEqual({ importedCount: 0 });
    expect(state.demoMode).toBe(false);
    expect(state.prefs).toMatchObject({
      halfLife: 4,
      targetSleep: DEFAULT_TARGET_SLEEP_H,
      dailyLimitMg: 400,
      cutoffHour: 16,
    });
    expect(state.onboarding).toMatchObject({
      completed: true,
      source: 'healthkit',
      permissionStatus: 'idle',
    });
  });

  it('migrates older persisted states with health sync and demo mode fallbacks', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          doses: [{ id: 'user:dose', timestamp: 1, mg: 95, source: 'Drip' }],
          sleeps: [],
          vigilanceSessions: [{ id: 'legacy:vigilance' }],
          prefs: { targetSleep: 7.5 },
        },
        version: 1,
      })
    );

    await useStore.persist.rehydrate();

    const state = useStore.getState();
    expect(state.doses).toHaveLength(1);
    expect(state.vigilanceSessions).toEqual([]);
    expect(state.healthSync).toEqual({ importedCount: 0 });
    expect(state.demoMode).toBe(false);
    expect(state.prefs).toMatchObject({
      halfLife: DEFAULT_HALFLIFE_H,
      targetSleep: 7.5,
      dailyLimitMg: 400,
      cutoffHour: 16,
    });
  });
});
