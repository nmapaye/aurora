import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { DEFAULT_HALFLIFE_H, DEFAULT_TARGET_SLEEP_H } from '~/domain/constants';
import type { Dose, SleepSession } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import { createDemoSnapshot } from '~/dev/mockData';
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
export type HealthPermissionStatus = 'idle' | 'granted' | 'denied' | 'unsupported';
type HealthSync = {
  lastSyncedAt?: number;
  lastMessage?: string;
  importedCount: number;
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
  doses: Dose[];
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
  | 'sleeps'
  | 'vigilanceSessions'
  | 'prefs'
  | 'onboarding'
  | 'healthSync'
  | 'demoMode'
  | 'appearanceMode'
>;
const mmkvStorage = createJSONStorage<PersistedState>(() => jsonStringStorage as any);
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
const defaultHealthSync: HealthSync = { importedCount: 0 };
const demoIdPrefix = 'demo:';

function withoutDemoId<T extends { id: string }>(items: T[]) {
  return items.filter((item) => !item.id.startsWith(demoIdPrefix));
}

type PersistedOnboarding = Partial<Onboarding> & {
  summaryWalkthroughCompleted?: boolean;
};
type MigratingPersistedState = Omit<Partial<PersistedState>, 'onboarding'> & {
  onboarding?: PersistedOnboarding;
};

function clampAppWalkthroughStep(step: unknown) {
  if (typeof step !== 'number' || !Number.isFinite(step)) return 0;
  return Math.max(0, Math.min(9, Math.floor(step)));
}

function normalizePersistedState(persistedState?: MigratingPersistedState): PersistedState {
  const { summaryWalkthroughCompleted: _legacyWalkthrough, ...persistedOnboarding } =
    persistedState?.onboarding ?? {};

  return {
    doses: persistedState?.doses ?? [],
    sleeps: persistedState?.sleeps ?? [],
    vigilanceSessions: persistedState?.vigilanceSessions ?? [],
    prefs: { ...defaultPrefs, ...persistedState?.prefs },
    onboarding: {
      ...defaultOnboarding,
      ...persistedOnboarding,
      appWalkthroughStep: clampAppWalkthroughStep(persistedOnboarding.appWalkthroughStep),
    },
    healthSync: { ...defaultHealthSync, ...persistedState?.healthSync },
    demoMode: persistedState?.demoMode ?? false,
    appearanceMode: persistedState?.appearanceMode ?? 'system',
  };
}

export const useStore = create<State>()(
  persist(
    (set) => ({
      doses: [],
      sleeps: [],
      vigilanceSessions: [],
      prefs: defaultPrefs,
      onboarding: defaultOnboarding,
      healthSync: defaultHealthSync,
      demoMode: false,
      appearanceMode: 'system',
      addDose: (d) => set((s) => ({ doses: [...s.doses, d] })),
      updateDose: (id, patch) => set((s) => ({
        doses: s.doses.map((d) => (d.id === id ? { ...d, ...patch, id: d.id } : d)),
      })),
      removeDose: (id) => set((s) => ({ doses: s.doses.filter((d) => d.id !== id) })),
      addSleep: (sl) => set((s) => ({ sleeps: [...s.sleeps, sl] })),
      upsertSleepSessions: (items) =>
        set((s) => {
          const deduped = new Map(s.sleeps.map((sleep) => [sleep.id, sleep]));
          items.forEach((item) => {
            deduped.set(item.id, item);
          });
          return {
            sleeps: [...deduped.values()].sort((a, b) => b.end - a.end),
          };
        }),
      addVigilanceSession: (session) =>
        set((s) => ({
          vigilanceSessions: [session, ...s.vigilanceSessions].sort(
            (a, b) => b.completedAt - a.completedAt
          ),
        })),
      setPrefs: (p) => set((s) => ({ prefs: { ...s.prefs, ...p } })),
      setOnboarding: (p) => set((s) => ({ onboarding: { ...s.onboarding, ...p } })),
      setHealthSync: (p) => set((s) => ({ healthSync: { ...s.healthSync, ...p } })),
      setAppearanceMode: (mode) => set({ appearanceMode: mode }),
      loadDemoData: () =>
        set((s) => {
          const demo = createDemoSnapshot();
          return {
            doses: [...withoutDemoId(s.doses), ...demo.doses].sort((a, b) => b.timestamp - a.timestamp),
            sleeps: [...withoutDemoId(s.sleeps), ...demo.sleeps].sort((a, b) => b.end - a.end),
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
            appWalkthroughStep: clampAppWalkthroughStep(s.onboarding.appWalkthroughStep + 1),
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
      version: 5,
      storage: mmkvStorage,
      partialize: (s) => ({
        doses: s.doses,
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
              appWalkthroughCompleted: legacyOnboarding?.summaryWalkthroughCompleted === true,
              appWalkthroughStep: 0,
            },
          };
        }
        return normalizePersistedState(nextState);
      },
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...normalizePersistedState((persistedState ?? {}) as MigratingPersistedState),
      }),
    }
  )
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
