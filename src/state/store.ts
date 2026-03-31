import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { DEFAULT_HALFLIFE_H, DEFAULT_TARGET_SLEEP_H } from '~/domain/constants';
import { jsonStringStorage } from '~/services/storage';

type Dose = { id: string; timestamp: number; mg: number; source?: string; note?: string };
type Sleep = { id: string; start: number; end: number; type: 'sleep' | 'nap' };
type Prefs = { halfLife: number; targetSleep: number; tz?: string; dailyLimitMg: number; cutoffHour: number };
export type OnboardingSource = 'healthkit' | 'manual';
export type HealthPermissionStatus = 'idle' | 'granted' | 'denied' | 'unsupported';
type Onboarding = {
  completed: boolean;
  source: OnboardingSource;
  permissionStatus: HealthPermissionStatus;
  completedAt?: number;
};

type State = {
  doses: Dose[];
  sleeps: Sleep[];
  prefs: Prefs;
  onboarding: Onboarding;
  addDose: (d: Dose) => void;
  updateDose: (id: string, patch: Partial<Omit<Dose, 'id'>>) => void;
  removeDose: (id: string) => void;
  addSleep: (s: Sleep) => void;
  upsertSleepSessions: (items: Sleep[]) => void;
  setPrefs: (p: Partial<Prefs>) => void;
  setOnboarding: (p: Partial<Onboarding>) => void;
  completeOnboarding: (p?: Partial<Onboarding>) => void;
};

// Storage adapter for zustand persist (MMKV if available, else in-memory fallback)
type PersistedState = Pick<State, 'doses' | 'sleeps' | 'prefs' | 'onboarding'>;
const mmkvStorage = createJSONStorage<PersistedState>(() => jsonStringStorage as any);

export const useStore = create<State>()(
  persist(
    (set) => ({
      doses: [],
      sleeps: [],
      prefs: { halfLife: DEFAULT_HALFLIFE_H, targetSleep: DEFAULT_TARGET_SLEEP_H, dailyLimitMg: 400, cutoffHour: 16 },
      onboarding: { completed: false, source: 'healthkit', permissionStatus: 'idle' },
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
      setPrefs: (p) => set((s) => ({ prefs: { ...s.prefs, ...p } })),
      setOnboarding: (p) => set((s) => ({ onboarding: { ...s.onboarding, ...p } })),
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
      version: 1,
      storage: mmkvStorage,
      partialize: (s) => ({ doses: s.doses, sleeps: s.sleeps, prefs: s.prefs, onboarding: s.onboarding }),
      // Future migrations can be added here
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
