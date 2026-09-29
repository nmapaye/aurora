import { useStore } from '~/state/store';

describe('deleteAllData', () => {
  beforeEach(() => {
    useStore.setState({
      doses: [{ id: 'd1', timestamp: 1, mg: 95 }],
      sleeps: [
        { id: 'manual:sleep:1', start: 1, end: 2, type: 'sleep' },
        { id: 'hk:abc', start: 3, end: 4, type: 'sleep' },
      ],
      vigilanceSessions: [{ id: 'v1' } as any],
      demoMode: true,
      healthSync: { importedCount: 12, importStatus: 'success', lastImportAt: 5 } as any,
    });
    useStore.getState().setPrefs({ targetSleep: 7.5 });
  });

  it('removes every logged and imported record but keeps preferences', () => {
    useStore.getState().deleteAllData();
    const state = useStore.getState();
    expect(state.doses).toEqual([]);
    expect(state.sleeps).toEqual([]);
    expect(state.vigilanceSessions).toEqual([]);
    expect(state.demoMode).toBe(false);
    expect(state.healthSync).toEqual({ importedCount: 0, importStatus: 'idle' });
    expect(state.prefs.targetSleep).toBe(7.5);
  });
});
