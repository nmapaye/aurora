import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';

// Every key persisted by partialize. Adding a persisted key to the store
// requires extending this fixture with a NON-DEFAULT value AND extending
// normalizePersistedState in src/state/store.ts — otherwise merge/rehydrate
// silently resets the new key to its default.
const nonDefaultPersistedState = {
  doses: [{ id: 'user:dose', timestamp: 1_700_000_000_000, mg: 95, source: 'Drip' }],
  sleeps: [
    {
      id: 'user:sleep',
      start: 1_700_000_000_000 - 8 * 3_600_000,
      end: 1_700_000_000_000,
      type: 'sleep' as const,
    },
  ],
  vigilanceSessions: [
    {
      id: 'user:vigilance',
      startedAt: 1_700_000_000_000 - 60_000,
      completedAt: 1_700_000_000_000,
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
      rating: 'Sharp' as const,
    },
  ],
  prefs: {
    halfLife: 6.5,
    targetSleep: 7.25,
    tz: 'America/Los_Angeles',
    dailyLimitMg: 300,
    cutoffHour: 14,
    notifyCutoff: true,
  },
  onboarding: {
    completed: true,
    source: 'manual' as const,
    permissionStatus: 'denied' as const,
    completedAt: 1_700_000_000_000,
  },
  healthSync: { importedCount: 5, lastSyncedAt: 1_700_000_000_000, lastMessage: 'Synced' },
  demoMode: true,
  appearanceMode: 'dark' as const,
};

describe('store persistence round-trip', () => {
  it('persists exactly the keys covered by this fixture', () => {
    const persisted = useStore.persist.getOptions().partialize!(useStore.getState());
    expect(Object.keys(persisted).sort()).toEqual(Object.keys(nonDefaultPersistedState).sort());
  });

  it('preserves every persisted key through rehydrate (merge + normalize)', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({ state: nonDefaultPersistedState, version: 3 })
    );

    await useStore.persist.rehydrate();

    const persisted = useStore.persist.getOptions().partialize!(useStore.getState());
    expect(persisted).toEqual(nonDefaultPersistedState);
  });
});
