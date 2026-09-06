import { defaultOwnership } from '~/features/ownership/model';
import { defaultPlanningState } from '~/features/planning/model';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';

// Every key persisted by partialize. Adding a persisted key to the store
// requires extending this fixture with a NON-DEFAULT value AND extending
// normalizePersistedState in src/state/store.ts — otherwise merge/rehydrate
// silently resets the new key to its default.
const nonDefaultPersistedState = {
  ownership: {
    ...defaultOwnership(),
    native: { showLockValues: true },
    summary: {
      order: ['sleep', 'caffeine', 'active-caffeine', 'vigilance', 'cutoff'],
      hidden: ['vigilance'],
    },
  },
  planning: {
    ...defaultPlanningState(),
    thresholdMg: 40,
    scenarios: [
      {
        id: 'plan',
        name: 'Tea',
        doses: [{ id: 'planned', offsetMinutes: 60, mg: 50, label: 'Tea' }],
      },
    ],
    checkIns: [
      { id: 'check', timestamp: 1700000000000, rating: 4, note: 'Focused' },
    ],
    experiments: [
      {
        id: 'experiment',
        question: 'Earlier tea?',
        baseline: { start: '2026-08-01', end: '2026-08-07' },
        comparison: { start: '2026-08-08', end: '2026-08-14' },
      },
    ],
    reduction: { startDate: '2026-09-07', startMg: 200, endMg: 100, days: 14 },
    budget: {
      targetMg: 150,
      allocations: [{ id: 'tea', label: 'Tea', mg: 50 }],
    },
    focus: { startMinutes: 120, endMinutes: 240 },
    sensitivityHours: [2, 4, 6],
  },
  doses: [
    { id: 'user:dose', timestamp: 1_700_000_000_000, mg: 95, source: 'Drip' },
  ],
  caffeine: {
    drinks: [{ id: 'personal:home', label: 'Home', mg: 90, archived: false }],
    favoriteIds: ['personal:home', 'espresso'],
    draft: {
      mg: '42',
      source: 'Tea',
      note: 'unsaved',
      timestamp: 1700000000000,
    },
    zeroDays: ['2026-09-06'],
  },
  sleepRoutines: {
    ...defaultSleepRoutines(7.25),
    weeklyConfigured: true,
    exceptions: { '2026-09-07': { bedtime: 1260, wake: 300 } },
    annotations: { 'user:sleep': { quality: 4, note: 'Rested' } },
    timer: { start: 1700000000000, end: 1700000600000 },
    windDown: { enabled: true, leadMinutes: 45 },
  },
  sleeps: [
    {
      id: 'user:sleep',
      start: 1_700_000_000_000 - 8 * 3_600_000,
      end: 1_700_000_000_000,
      type: 'sleep' as const,
      note: 'Restful',
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
    source: 'healthkit' as const,
    permissionStatus: 'granted' as const,
    completedAt: 1_700_000_000_000,
    appWalkthroughCompleted: true,
    appWalkthroughStep: 7,
  },
  healthSync: {
    importedCount: 5,
    importStatus: 'failed' as const,
    lastSyncedAt: 1_700_000_000_000,
    lastMessage: 'Health import failed. Database unavailable.',
  },
  demoMode: true,
  appearanceMode: 'dark' as const,
};

describe('store persistence round-trip', () => {
  it('persists exactly the keys covered by this fixture', () => {
    const persisted = useStore.persist.getOptions().partialize!(
      useStore.getState(),
    );
    expect(Object.keys(persisted).sort()).toEqual(
      Object.keys(nonDefaultPersistedState).sort(),
    );
  });

  it('preserves every persisted key through rehydrate (merge + normalize)', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({ state: nonDefaultPersistedState, version: 5 }),
    );

    await useStore.persist.rehydrate();

    const persisted = useStore.persist.getOptions().partialize!(
      useStore.getState(),
    );
    expect(persisted).toEqual(nonDefaultPersistedState);
  });

  it.each([
    [-3, 0],
    [4.9, 4],
    [27, 9],
  ])(
    'normalizes persisted walkthrough cursor %p to %p',
    async (step, expectedStep) => {
      jsonStringStorage.setItem(
        'aurora/state',
        JSON.stringify({
          state: {
            onboarding: {
              completed: true,
              source: 'manual',
              permissionStatus: 'unsupported',
              appWalkthroughCompleted: false,
              appWalkthroughStep: step,
            },
          },
          version: 5,
        }),
      );

      await useStore.persist.rehydrate();

      expect(useStore.getState().onboarding.appWalkthroughStep).toBe(
        expectedStep,
      );
    },
  );

  it('strips a legacy Summary completion field from a version 5 payload', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          onboarding: {
            completed: true,
            source: 'manual',
            permissionStatus: 'unsupported',
            appWalkthroughCompleted: false,
            appWalkthroughStep: 3,
            summaryWalkthroughCompleted: true,
          },
        },
        version: 5,
      }),
    );

    await useStore.persist.rehydrate();

    expect(useStore.getState().onboarding).not.toHaveProperty(
      'summaryWalkthroughCompleted',
    );
  });

  it('migrates and dedupes only boundary-equivalent legacy Health sleep IDs', async () => {
    const start = 1_700_000_000_000;
    const end = start + 8 * 3_600_000;
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          sleeps: [
            { id: `sleep:${start}:${end}`, start, end, type: 'sleep' },
            {
              id: `healthkit:sleep:${start}:${end}`,
              start,
              end,
              type: 'sleep',
            },
            {
              id: `sleep:${start + 1}:${end}`,
              start: start + 1,
              end,
              type: 'sleep',
            },
          ],
        },
        version: 5,
      }),
    );

    await useStore.persist.rehydrate();

    expect(useStore.getState().sleeps).toEqual([
      { id: `healthkit:sleep:${start}:${end}`, start, end, type: 'sleep' },
      {
        id: `healthkit:sleep:${start + 1}:${end}`,
        start: start + 1,
        end,
        type: 'sleep',
      },
    ]);
  });

  it.each([
    [
      'failed message',
      'granted',
      {
        importedCount: 0,
        lastMessage: 'Health import failed. Database unavailable.',
      },
      'failed',
    ],
    [
      'refresh failure message',
      'granted',
      {
        importedCount: 0,
        lastMessage: 'hEaLtH ReFrEsH FaIlEd. Database unavailable.',
      },
      'failed',
    ],
    [
      'successful import message',
      'granted',
      {
        importedCount: 1,
        lastMessage: 'Imported 1 recent sleep sample from Health.',
      },
      'succeeded',
    ],
    ['granted authorization alone', 'granted', { importedCount: 0 }, 'idle'],
    [
      'success copy without authorization',
      'denied',
      {
        importedCount: 1,
        lastMessage: 'Imported 1 recent sleep sample from Health.',
      },
      'idle',
    ],
  ] as const)(
    'migrates a version 5 legacy Health sync with %s',
    async (_case, permissionStatus, healthSync, expectedStatus) => {
      jsonStringStorage.setItem(
        'aurora/state',
        JSON.stringify({
          state: {
            onboarding: {
              completed: false,
              source: 'healthkit',
              permissionStatus,
              appWalkthroughCompleted: false,
              appWalkthroughStep: 0,
            },
            healthSync,
          },
          version: 5,
        }),
      );

      await useStore.persist.rehydrate();

      expect(useStore.getState().healthSync.importStatus).toBe(expectedStatus);
    },
  );

  it('normalizes an unknown persisted import lifecycle to idle', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          onboarding: {
            completed: false,
            source: 'healthkit',
            permissionStatus: 'granted',
            appWalkthroughCompleted: false,
            appWalkthroughStep: 0,
          },
          healthSync: {
            importedCount: 2,
            importStatus: 'complete-ish',
            lastMessage: 'Imported 2 recent sleep samples from Health.',
          },
        },
        version: 6,
      }),
    );

    await useStore.persist.rehydrate();

    expect(useStore.getState().healthSync.importStatus).toBe('idle');
  });

  it('hydrates an interrupted import as idle with neutral retry copy', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          onboarding: {
            completed: false,
            source: 'healthkit',
            permissionStatus: 'granted',
            appWalkthroughCompleted: false,
            appWalkthroughStep: 0,
          },
          healthSync: {
            importedCount: 0,
            importStatus: 'importing',
            lastMessage: 'Importing recent sleep from Health.',
          },
        },
        version: 6,
      }),
    );

    await useStore.persist.rehydrate();

    expect(useStore.getState().onboarding.permissionStatus).toBe('granted');
    expect(useStore.getState().healthSync).toMatchObject({
      importStatus: 'idle',
      lastMessage: 'Health import was interrupted. Try again.',
    });
  });
});
