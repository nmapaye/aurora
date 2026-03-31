import { useStore } from '~/state/store';

describe('store onboarding and logging flow', () => {
  beforeEach(() => {
    useStore.setState({
      doses: [],
      sleeps: [],
      vigilanceSessions: [],
      prefs: { halfLife: 5, targetSleep: 8, dailyLimitMg: 400, cutoffHour: 16 },
      onboarding: { completed: false, source: 'healthkit', permissionStatus: 'idle' },
    });
  });

  test('persists onboarding choices and completion state in memory', () => {
    useStore.getState().setPrefs({ targetSleep: 7.5 });
    useStore.getState().setOnboarding({ source: 'manual', permissionStatus: 'unsupported' });
    useStore.getState().completeOnboarding();

    const state = useStore.getState();
    expect(state.prefs.targetSleep).toBe(7.5);
    expect(state.onboarding.completed).toBe(true);
    expect(state.onboarding.source).toBe('manual');
    expect(state.onboarding.permissionStatus).toBe('unsupported');
    expect(typeof state.onboarding.completedAt).toBe('number');
  });

  test('quick dose logging appends doses to the persisted store', () => {
    useStore.getState().addDose({ id: 'dose-1', timestamp: 10, mg: 95, source: 'Drip' });
    useStore.getState().addDose({ id: 'dose-2', timestamp: 20, mg: 60, source: 'Espresso' });

    expect(useStore.getState().doses).toEqual([
      { id: 'dose-1', timestamp: 10, mg: 95, source: 'Drip' },
      { id: 'dose-2', timestamp: 20, mg: 60, source: 'Espresso' },
    ]);
  });

  test('completed vigilance sessions persist separately from dose and sleep state', () => {
    useStore.getState().addVigilanceSession({
      id: 'vig-1',
      startedAt: 1000,
      completedAt: 61000,
      durationMs: 60000,
      trialCount: 12,
      validReactionCount: 10,
      falseStartCount: 1,
      lapseCount: 2,
      medianReactionMs: 280,
      meanReactionMs: 294,
      fastestReactionMs: 240,
      reactionStdDevMs: 41,
      score: 76,
      rating: 'Steady',
    });

    const state = useStore.getState();
    expect(state.vigilanceSessions).toHaveLength(1);
    expect(state.doses).toEqual([]);
    expect(state.sleeps).toEqual([]);
    expect(state.vigilanceSessions[0].rating).toBe('Steady');
  });
});
  
