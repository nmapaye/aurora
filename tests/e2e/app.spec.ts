import { useStore } from '~/state/store';

describe('app boot smoke flow', () => {
  beforeEach(() => {
    useStore.setState({
      doses: [],
      sleeps: [],
      prefs: { halfLife: 5, targetSleep: 8, dailyLimitMg: 400, cutoffHour: 16 },
      onboarding: { completed: false, source: 'healthkit', permissionStatus: 'idle' },
    });
  });

  it('supports onboarding completion, sleep import, and next-launch persistence state', () => {
    const store = useStore.getState();
    store.setPrefs({ targetSleep: 8.5 });
    store.upsertSleepSessions([
      { id: 'sleep:1', start: 1, end: 2, type: 'sleep' },
    ]);
    store.addDose({ id: 'dose-1', timestamp: 3, mg: 80, source: 'Espresso' });
    store.completeOnboarding({ permissionStatus: 'granted' });

    const snapshot = useStore.getState();
    expect(snapshot.onboarding.completed).toBe(true);
    expect(snapshot.sleeps).toHaveLength(1);
    expect(snapshot.doses).toHaveLength(1);
    expect(snapshot.prefs.targetSleep).toBe(8.5);
  });
});
  
