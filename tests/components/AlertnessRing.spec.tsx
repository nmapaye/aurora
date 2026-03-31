import { useStore } from '~/state/store';

describe('store onboarding and logging flow', () => {
  beforeEach(() => {
    useStore.setState({
      doses: [],
      sleeps: [],
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
});
  
