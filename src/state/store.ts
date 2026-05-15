import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { DEFAULT_HALFLIFE_H, DEFAULT_TARGET_SLEEP_H } from '~/domain/constants';
import type { Dose, SleepSession } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import { createDemoSnapshot } from '~/dev/mockData';
import { jsonStringStorage } from '~/services/storage';

type Prefs = { halfLife: number; targetSleep: number; tz?: string; dailyLimitMg: number; cutoffHour: number };
export type OnboardingSource = 'healthkit' | 'manual';
export type HealthPermissionStatus = 'idle' | 'granted' | 'denied' | 'unsupported';
type HealthSync = {
  lastSyncedAt?: number;
  lastMessage?: string;
  importedCount: number;
};
type Onboarding = {
  completed: boolean;
  source: OnboardingSource;
  permissionStatus: HealthPermissionStatus;
  completedAt?: number;
};

type State = {
  doses: Dose[];
  sleeps: SleepSession[];
  vigilanceSessions: VigilanceSession[];
  prefs: Prefs;
  onboarding: Onboarding;
  healthSync: HealthSync;
  demoMode: boolean;
  addDose: (d: Dose) => void;
  updateDose: (id: string, patch: Partial<Omit<Dose, 'id'>>) => void;
  removeDose: (id: string) => void;
  addSleep: (s: SleepSession) => void;
  upsertSleepSessions: (items: SleepSession[]) => void;
  addVigilanceSession: (session: VigilanceSession) => void;
  setPrefs: (p: Partial<Prefs>) => void;
  setOnboarding: (p: Partial<Onboarding>) => void;
  setHealthSync: (p: Partial<HealthSync>) => void;
  loadDemoData: () => void;
  clearDemoData: () => void;
  completeOnboarding: (p?: Partial<Onboarding>) => void;
};

// Storage adapter for zustand persist (MMKV if available, else in-memory fallback)
type PersistedState = Pick<
  State,
  'doses' | 'sleeps' | 'vigilanceSessions' | 'prefs' | 'onboarding' | 'healthSync' | 'demoMode'
>;
const mmkvStorage = createJSONStorage<PersistedState>(() => jsonStringStorage as any);
const defaultPrefs: Prefs = {
  halfLife: DEFAULT_HALFLIFE_H,
  targetSleep: DEFAULT_TARGET_SLEEP_H,
  dailyLimitMg: 400,
  cutoffHour: 16,
};
const defaultOnboarding: Onboarding = {
  completed: false,
  source: 'healthkit',
  permissionStatus: 'idle',
};
const defaultHealthSync: HealthSync = { importedCount: 0 };
const demoIdPrefix = 'demo:';

function withoutDemoId<T extends { id: string }>(items: T[]) {
  return items.filter((item) => !item.id.startsWith(demoIdPrefix));
}

function normalizePersistedState(persistedState?: Partial<PersistedState>): PersistedState {
  return {
    doses: persistedState?.doses ?? [],
    sleeps: persistedState?.sleeps ?? [],
    vigilanceSessions: persistedState?.vigilanceSessions ?? [],
    prefs: { ...defaultPrefs, ...persistedState?.prefs },
    onboarding: { ...defaultOnboarding, ...persistedState?.onboarding },
    healthSync: { ...defaultHealthSync, ...persistedState?.healthSync },
    demoMode: persistedState?.demoMode ?? false,
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
    }),
    {
      name: 'aurora/state',
      version: 3,
      storage: mmkvStorage,
      partialize: (s) => ({
        doses: s.doses,
        sleeps: s.sleeps,
        vigilanceSessions: s.vigilanceSessions,
        prefs: s.prefs,
        onboarding: s.onboarding,
        healthSync: s.healthSync,
        demoMode: s.demoMode,
      }),
      migrate: (persistedState, version) => {
        const nextState = (persistedState ?? {}) as Partial<PersistedState>;
        if (version < 2) {
          return normalizePersistedState({ ...nextState, vigilanceSessions: [] });
        }
        return normalizePersistedState(nextState);
      },
      merge: (persistedState, currentState) => ({
        ...currentState,
        ...normalizePersistedState((persistedState ?? {}) as Partial<PersistedState>),
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
