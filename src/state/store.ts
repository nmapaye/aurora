import {
  defaultPlanningState,
  normalizePlanning,
  type PlanningState,
} from '~/features/planning/model';
import {
  createManualSleepId,
  validateManualSleep,
} from '~/features/sleep/manualSleep';
import {
  defaultSleepRoutines,
  sleepEpisodeIds,
  sleepJournalKey,
  normalizeSleepRoutines,
  type SleepRoutines,
} from '~/features/sleep/upgrades';
import { create } from 'zustand';
import {
  applyDoseUndo,
  availableDrinks,
  defaultCaffeineState,
  localDayKey,
  normalizeCaffeine,
  validDrink,
  type CaffeineState,
  type DoseUndo,
  type PersonalDrink,
} from '~/features/caffeine/upgrades';
import type { CustomDoseDraft } from '~/features/caffeine/logging';
import { persist, createJSONStorage } from 'zustand/middleware';
import { DEFAULT_HALFLIFE_H, DEFAULT_TARGET_SLEEP_H } from '~/domain/constants';
import type { Dose, SleepSession } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import { createDemoSnapshot } from '~/dev/mockData';
import { normalizeHealthSleepSessionIdentities } from '~/features/sleep/healthSleep';
import { jsonStringStorage } from '~/services/storage';

type Prefs = {
  halfLife: number;
  targetSleep: number;
  tz?: string;
  dailyLimitMg: number;
  cutoffHour: number;
  notifyCutoff: boolean;
};
export type AppearanceMode = 'system' | 'light' | 'dark';
export type OnboardingSource = 'healthkit' | 'manual';
export type HealthPermissionStatus =
  | 'idle'
  | 'granted'
  | 'denied'
  | 'unsupported';
export type HealthImportStatus = 'idle' | 'importing' | 'succeeded' | 'failed';
export type HealthSync = {
  lastSyncedAt?: number;
  lastMessage?: string;
  importedCount: number;
  importStatus: HealthImportStatus;
};
export type Onboarding = {
  completed: boolean;
  source: OnboardingSource;
  permissionStatus: HealthPermissionStatus;
  completedAt?: number;
  appWalkthroughCompleted: boolean;
  appWalkthroughStep: number;
};

type State = {
  planning: PlanningState;
  setPlanning: (patch: Partial<PlanningState>) => void;
  doses: Dose[];
  caffeine: CaffeineState;
  doseUndo: DoseUndo | null;
  saveDrink: (drink: PersonalDrink) => void;
  setFavoriteDrinks: (ids: string[]) => void;
  setCaffeineDraft: (draft: CustomDoseDraft | null) => void;
  markCaffeineFree: (day: number) => void;
  clearCaffeineFree: (day: number) => void;
  undoDoseChange: (now: number) => void;
  sleepRoutines: SleepRoutines;
  setSleepRoutines: (patch: Partial<SleepRoutines>) => void;
  confirmNap: () => void;
  saveSleepJournal: (id: string, quality: number, note: string) => void;
  sleeps: SleepSession[];
  vigilanceSessions: VigilanceSession[];
  prefs: Prefs;
  onboarding: Onboarding;
  healthSync: HealthSync;
  demoMode: boolean;
  appearanceMode: AppearanceMode;
  addDose: (d: Dose) => void;
  updateDose: (id: string, patch: Partial<Omit<Dose, 'id'>>) => void;
  removeDose: (id: string) => void;
  addSleep: (s: SleepSession) => void;
  upsertSleepSessions: (items: SleepSession[]) => void;
  updateManualSleep: (
    id: string,
    patch: Partial<Pick<SleepSession, 'start' | 'end' | 'note'>>,
  ) => void;
  removeManualSleep: (id: string) => void;
  addVigilanceSession: (session: VigilanceSession) => void;
  setPrefs: (p: Partial<Prefs>) => void;
  setOnboarding: (p: Partial<Onboarding>) => void;
  setHealthSync: (p: Partial<HealthSync>) => void;
  setAppearanceMode: (mode: AppearanceMode) => void;
  loadDemoData: () => void;
  clearDemoData: () => void;
  completeOnboarding: (p?: Partial<Onboarding>) => void;
  advanceAppWalkthrough: () => void;
  completeAppWalkthrough: () => void;
};

// Storage adapter for zustand persist (MMKV if available, else in-memory fallback)
type PersistedState = Pick<
  State,
  | 'doses'
  | 'caffeine'
  | 'planning'
  | 'sleepRoutines'
  | 'sleeps'
  | 'vigilanceSessions'
  | 'prefs'
  | 'onboarding'
  | 'healthSync'
  | 'demoMode'
  | 'appearanceMode'
>;
const mmkvStorage = createJSONStorage<PersistedState>(
  () => jsonStringStorage as any,
);
const defaultPrefs: Prefs = {
  halfLife: DEFAULT_HALFLIFE_H,
  targetSleep: DEFAULT_TARGET_SLEEP_H,
  dailyLimitMg: 400,
  cutoffHour: 16,
  notifyCutoff: false,
};
const defaultOnboarding: Onboarding = {
  completed: false,
  source: 'healthkit',
  permissionStatus: 'idle',
  appWalkthroughCompleted: false,
  appWalkthroughStep: 0,
};
const defaultHealthSync: HealthSync = {
  importedCount: 0,
  importStatus: 'idle',
};
const demoIdPrefix = 'demo:';

function withoutDemoId<T extends { id: string }>(items: T[]) {
  return items.filter((item) => !item.id.startsWith(demoIdPrefix));
}

type PersistedOnboarding = Partial<Onboarding> & {
  summaryWalkthroughCompleted?: boolean;
};
type PersistedHealthSync = Partial<Omit<HealthSync, 'importStatus'>> & {
  importStatus?: unknown;
};
type MigratingPersistedState = Omit<
  Partial<PersistedState>,
  'onboarding' | 'healthSync'
> & {
  onboarding?: PersistedOnboarding;
  healthSync?: PersistedHealthSync;
};

function clampAppWalkthroughStep(step: unknown) {
  if (typeof step !== 'number' || !Number.isFinite(step)) return 0;
  return Math.max(0, Math.min(9, Math.floor(step)));
}

function normalizeHealthImportStatus(
  value: unknown,
  permissionStatus: HealthPermissionStatus,
  lastMessage?: string,
): HealthImportStatus {
  if (permissionStatus !== 'granted') return 'idle';
  if (value !== undefined) {
    return value === 'importing'
      ? 'idle'
      : value === 'idle' || value === 'succeeded' || value === 'failed'
        ? value
        : 'idle';
  }
  const normalizedMessage = lastMessage?.toLowerCase() ?? '';
  if (
    normalizedMessage.startsWith('health import failed.') ||
    normalizedMessage.startsWith('health refresh failed.')
  ) {
    return 'failed';
  }
  if (
    normalizedMessage.startsWith('imported ') ||
    normalizedMessage.startsWith('health connected')
  ) {
    return 'succeeded';
  }
  return 'idle';
}

function normalizePersistedState(
  persistedState?: MigratingPersistedState,
): PersistedState {
  const {
    summaryWalkthroughCompleted: _legacyWalkthrough,
    ...persistedOnboarding
  } = persistedState?.onboarding ?? {};
  const onboarding = {
    ...defaultOnboarding,
    ...persistedOnboarding,
    appWalkthroughStep: clampAppWalkthroughStep(
      persistedOnboarding.appWalkthroughStep,
    ),
  };
  const persistedHealthSync = persistedState?.healthSync;
  const interruptedImport = persistedHealthSync?.importStatus === 'importing';

  return {
    doses: persistedState?.doses ?? [],
    planning: normalizePlanning(persistedState?.planning),
    caffeine: normalizeCaffeine(persistedState?.caffeine),
    sleepRoutines: normalizeSleepRoutines(
      persistedState?.sleepRoutines,
      persistedState?.prefs?.targetSleep ?? defaultPrefs.targetSleep,
    ),
    sleeps: normalizeHealthSleepSessionIdentities(persistedState?.sleeps ?? []),
    vigilanceSessions: persistedState?.vigilanceSessions ?? [],
    prefs: { ...defaultPrefs, ...persistedState?.prefs },
    onboarding,
    healthSync: {
      ...defaultHealthSync,
      ...persistedHealthSync,
      ...(interruptedImport
        ? { lastMessage: 'Health import was interrupted. Try again.' }
        : {}),
      importStatus: normalizeHealthImportStatus(
        persistedHealthSync?.importStatus,
        onboarding.permissionStatus,
        persistedHealthSync?.lastMessage,
      ),
    },
    demoMode: persistedState?.demoMode ?? false,
    appearanceMode: persistedState?.appearanceMode ?? 'system',
  };
}

export const useStore = create<State>()(
  persist(
    (set) => ({
      doses: [],
      planning: defaultPlanningState(),
      setPlanning: (patch) =>
        set((s) => {
          if (s.onboarding.completed && !s.onboarding.appWalkthroughCompleted)
            return {};
          return { planning: normalizePlanning({ ...s.planning, ...patch }) };
        }),
      sleepRoutines: defaultSleepRoutines(defaultPrefs.targetSleep),
      setSleepRoutines: (patch) =>
        set((s) => {
          if (s.onboarding.completed && !s.onboarding.appWalkthroughCompleted)
            return {};
          return {
            sleepRoutines: normalizeSleepRoutines(
              {
                ...s.sleepRoutines,
                ...patch,
                weeklyConfigured: patch.weekly
                  ? true
                  : s.sleepRoutines.weeklyConfigured,
              },
              s.prefs.targetSleep,
            ),
          };
        }),
      saveSleepJournal: (id, quality, note) =>
        set((s) => {
          if (
            (s.onboarding.completed && !s.onboarding.appWalkthroughCompleted) ||
            id.startsWith('demo:') ||
            !s.sleeps.some((sleep) => sleep.id === id)
          )
            return {};
          const annotations = { ...s.sleepRoutines.annotations };
          for (const key of sleepEpisodeIds(id, s.sleeps, Date.now()))
            annotations[key] = { quality, note };
          return {
            sleepRoutines: normalizeSleepRoutines(
              { ...s.sleepRoutines, annotations },
              s.prefs.targetSleep,
            ),
          };
        }),
      confirmNap: () =>
        set((s) => {
          const timer = s.sleepRoutines.timer;
          if (
            (s.onboarding.completed && !s.onboarding.appWalkthroughCompleted) ||
            !timer?.end ||
            !validateManualSleep({ start: timer.start, end: timer.end }).valid
          )
            return {};
          return {
            sleeps: [
              ...s.sleeps,
              {
                id: createManualSleepId(),
                start: timer.start,
                end: timer.end,
                type: 'nap' as const,
              },
            ],
            sleepRoutines: { ...s.sleepRoutines, timer: null },
          };
        }),
      sleeps: [],
      vigilanceSessions: [],
      prefs: defaultPrefs,
      onboarding: defaultOnboarding,
      healthSync: defaultHealthSync,
      demoMode: false,
      appearanceMode: 'system',
      caffeine: normalizeCaffeine(defaultCaffeineState),
      doseUndo: null,
      saveDrink: (drink) => {
        if (!validDrink(drink)) return;
        set((s) => ({
          caffeine: normalizeCaffeine({
            ...s.caffeine,
            drinks: [
              ...s.caffeine.drinks.filter((d) => d.id !== drink.id),
              drink,
            ],
          }),
        }));
      },
      setFavoriteDrinks: (ids) =>
        set((s) => ({
          caffeine: {
            ...s.caffeine,
            favoriteIds: [...new Set(ids)].filter((id) =>
              availableDrinks(s.caffeine).some((d) => d.id === id),
            ),
          },
        })),
      setCaffeineDraft: (draft) =>
        set((s) => ({ caffeine: { ...s.caffeine, draft } })),
      markCaffeineFree: (day) =>
        set((s) => {
          const key = localDayKey(day);
          if (
            !Number.isFinite(day) ||
            day > Date.now() ||
            s.doses.some(
              (d) =>
                !d.id.startsWith('demo:') && localDayKey(d.timestamp) === key,
            )
          )
            return {};
          return {
            caffeine: {
              ...s.caffeine,
              zeroDays: [...new Set([...s.caffeine.zeroDays, key])],
            },
          };
        }),
      clearCaffeineFree: (day) =>
        set((s) => ({
          caffeine: {
            ...s.caffeine,
            zeroDays: s.caffeine.zeroDays.filter(
              (key) => key !== localDayKey(day),
            ),
          },
        })),
      undoDoseChange: (now) =>
        set((s) => {
          const doses = applyDoseUndo(s.doses, s.doseUndo, now);
          const restored =
            doses !== s.doses ? (s.doseUndo?.zeroDays ?? []) : [];
          const zeroDays = [
            ...new Set([...s.caffeine.zeroDays, ...restored]),
          ].filter(
            (key) =>
              !doses.some(
                (d) =>
                  !d.id.startsWith('demo:') && localDayKey(d.timestamp) === key,
              ),
          );
          return {
            doses,
            doseUndo: null,
            caffeine: { ...s.caffeine, zeroDays },
          };
        }),
      addDose: (d) =>
        set((s) => {
          if (s.doses.some((item) => item.id === d.id)) return {};
          return {
            doses: [...s.doses, d],
            doseUndo: {
              after: d,
              expiresAt: Date.now() + 10000,
              zeroDays: s.caffeine.zeroDays.filter(
                (day) => day === localDayKey(d.timestamp),
              ),
            },
            caffeine: {
              ...s.caffeine,
              zeroDays: d.id.startsWith('demo:')
                ? s.caffeine.zeroDays
                : s.caffeine.zeroDays.filter(
                    (day) => day !== localDayKey(d.timestamp),
                  ),
            },
          };
        }),
      updateDose: (id, patch) =>
        set((s) => {
          const before = s.doses.find((d) => d.id === id);
          if (!before || id.startsWith('demo:')) return {};
          const after = { ...before, ...patch, id };
          return {
            doses: s.doses.map((d) => (d.id === id ? after : d)),
            doseUndo: {
              before,
              after,
              expiresAt: Date.now() + 10000,
              zeroDays: s.caffeine.zeroDays.filter(
                (day) => day === localDayKey(after.timestamp),
              ),
            },
            caffeine: {
              ...s.caffeine,
              zeroDays: s.caffeine.zeroDays.filter(
                (day) => day !== localDayKey(after.timestamp),
              ),
            },
          };
        }),
      removeDose: (id) =>
        set((s) => {
          const before = s.doses.find((d) => d.id === id);
          if (!before || id.startsWith('demo:')) return {};
          return {
            doses: s.doses.filter((d) => d.id !== id),
            doseUndo: { before, expiresAt: Date.now() + 10000, zeroDays: [] },
          };
        }),
      addSleep: (sl) => set((s) => ({ sleeps: [...s.sleeps, sl] })),
      upsertSleepSessions: (items) =>
        set((s) => {
          const existing = normalizeHealthSleepSessionIdentities(s.sleeps);
          const incoming = normalizeHealthSleepSessionIdentities(items);
          const deduped = new Map(existing.map((sleep) => [sleep.id, sleep]));
          incoming.forEach((item) => {
            deduped.set(item.id, item);
          });
          return {
            sleeps: [...deduped.values()].sort((a, b) => b.end - a.end),
          };
        }),
      updateManualSleep: (id, patch) => {
        if (!id.startsWith('manual:sleep:')) return;
        set((s) => ({
          sleeps: s.sleeps.map((sleep) =>
            sleep.id === id && sleep.id.startsWith('manual:sleep:')
              ? { ...sleep, ...patch, id: sleep.id, type: sleep.type }
              : sleep,
          ),
        }));
      },
      removeManualSleep: (id) => {
        if (!id.startsWith('manual:sleep:')) return;
        set((s) => {
          const annotations = { ...s.sleepRoutines.annotations };
          const journal =
            annotations[sleepJournalKey(id, s.sleeps, Date.now(), annotations)];
          if (journal)
            for (const key of sleepEpisodeIds(id, s.sleeps, Date.now()))
              if (key !== id) annotations[key] = journal;
          delete annotations[id];
          return {
            sleeps: s.sleeps.filter((sleep) => sleep.id !== id),
            sleepRoutines: { ...s.sleepRoutines, annotations },
          };
        });
      },
      addVigilanceSession: (session) =>
        set((s) => ({
          vigilanceSessions: [session, ...s.vigilanceSessions].sort(
            (a, b) => b.completedAt - a.completedAt,
          ),
        })),
      setPrefs: (p) =>
        set((s) => ({
          prefs: { ...s.prefs, ...p },
          ...(p.targetSleep !== undefined && !s.sleepRoutines.weeklyConfigured
            ? {
                sleepRoutines: {
                  ...s.sleepRoutines,
                  weekly: defaultSleepRoutines(p.targetSleep).weekly,
                },
              }
            : {}),
        })),
      setOnboarding: (p) =>
        set((s) => ({ onboarding: { ...s.onboarding, ...p } })),
      setHealthSync: (p) =>
        set((s) => ({ healthSync: { ...s.healthSync, ...p } })),
      setAppearanceMode: (mode) => set({ appearanceMode: mode }),
      loadDemoData: () =>
        set((s) => {
          const demo = createDemoSnapshot();
          return {
            doses: [...withoutDemoId(s.doses), ...demo.doses].sort(
              (a, b) => b.timestamp - a.timestamp,
            ),
            sleeps: [...withoutDemoId(s.sleeps), ...demo.sleeps].sort(
              (a, b) => b.end - a.end,
            ),
            vigilanceSessions: [
              ...withoutDemoId(s.vigilanceSessions),
              ...demo.vigilanceSessions,
            ].sort((a, b) => b.completedAt - a.completedAt),
            demoMode: true,
            onboarding: {
              ...s.onboarding,
              completed: true,
              source: 'manual',
              permissionStatus: 'unsupported',
              completedAt: s.onboarding.completedAt ?? Date.now(),
            },
            healthSync: {
              importedCount: demo.sleeps.length,
              importStatus: 'idle',
              lastSyncedAt: Date.now(),
              lastMessage: 'Sample data loaded.',
            },
          };
        }),
      clearDemoData: () =>
        set((s) => ({
          doses: withoutDemoId(s.doses),
          sleeps: withoutDemoId(s.sleeps),
          vigilanceSessions: withoutDemoId(s.vigilanceSessions),
          demoMode: false,
          healthSync: {
            ...s.healthSync,
            lastMessage: 'Sample data removed.',
          },
        })),
      completeOnboarding: (p) =>
        set((s) => ({
          onboarding: {
            ...s.onboarding,
            ...p,
            completed: true,
            completedAt: Date.now(),
          },
        })),
      advanceAppWalkthrough: () =>
        set((s) => ({
          onboarding: {
            ...s.onboarding,
            appWalkthroughStep: clampAppWalkthroughStep(
              s.onboarding.appWalkthroughStep + 1,
            ),
          },
        })),
      completeAppWalkthrough: () =>
        set((s) => ({
          onboarding: {
            ...s.onboarding,
            appWalkthroughCompleted: true,
          },
        })),
    }),
    {
      name: 'aurora/state',
      version: 9,
      storage: mmkvStorage,
      partialize: (s) => ({
        doses: s.doses,
        caffeine: s.caffeine,
        planning: s.planning,
        sleepRoutines: s.sleepRoutines,
        sleeps: s.sleeps,
        vigilanceSessions: s.vigilanceSessions,
        prefs: s.prefs,
        onboarding: s.onboarding,
        healthSync: s.healthSync,
        demoMode: s.demoMode,
        appearanceMode: s.appearanceMode,
      }),
      migrate: (persistedState, version) => {
        let nextState = (persistedState ?? {}) as MigratingPersistedState;
        if (version < 2) {
          nextState = { ...nextState, vigilanceSessions: [] };
        }
        if (version < 4) {
          const legacyOnboarding = nextState.onboarding;
          nextState = {
            ...nextState,
            onboarding: {
              ...legacyOnboarding,
              summaryWalkthroughCompleted: legacyOnboarding?.completed === true,
            },
          };
        }
        if (version < 5) {
          const legacyOnboarding = nextState.onboarding;
          nextState = {
            ...nextState,
            onboarding: {
              ...legacyOnboarding,
              appWalkthroughCompleted:
                legacyOnboarding?.summaryWalkthroughCompleted === true,
              appWalkthroughStep: 0,
            },
          };
        }
        if (version < 6) {
          nextState = {
            ...nextState,
            healthSync: {
              ...nextState.healthSync,
              importStatus: normalizeHealthImportStatus(
                undefined,
                nextState.onboarding?.permissionStatus ?? 'idle',
                nextState.healthSync?.lastMessage,
              ),
            },
          };
        }
        return normalizePersistedState(nextState);
      },
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...normalizePersistedState(
          (persistedState ?? {}) as MigratingPersistedState,
        ),
      }),
    },
  ),
);

// Hooks used by useAppInit for boot-time persistence setup
export async function rehydrate() {
  try {
    await (useStore as any).persist?.rehydrate?.();
  } catch (e) {
    console.error('[store] rehydrate failed', e);
  }
}

export async function enablePersistence() {
  // MMKV storage is configured eagerly via persist(). Nothing to do for now.
  return Promise.resolve();
}
