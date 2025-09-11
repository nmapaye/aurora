import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';
import { DEFAULT_HALFLIFE_H, DEFAULT_TARGET_SLEEP_H } from '~/domain/constants';
import { jsonStringStorage } from '~/services/storage';

type Dose = { id: string; timestamp: number; mg: number; source?: string; note?: string };
type Sleep = { id: string; start: number; end: number; type: 'sleep' | 'nap' };
type Prefs = { halfLife: number; targetSleep: number; tz?: string; dailyLimitMg: number; cutoffHour: number };

type State = {
  doses: Dose[];
  sleeps: Sleep[];
  prefs: Prefs;
  addDose: (d: Dose) => void;
  updateDose: (id: string, patch: Partial<Omit<Dose, 'id'>>) => void;
  removeDose: (id: string) => void;
  addSleep: (s: Sleep) => void;
  setPrefs: (p: Partial<Prefs>) => void;
};

// Storage adapter for zustand persist (MMKV if available, else in-memory fallback)
type PersistedState = Pick<State, 'doses' | 'sleeps' | 'prefs'>;
const mmkvStorage = createJSONStorage<PersistedState>(() => jsonStringStorage as any);

export const useStore = create<State>()(
  persist(
    (set) => ({
      doses: [],
      sleeps: [],
      prefs: { halfLife: DEFAULT_HALFLIFE_H, targetSleep: DEFAULT_TARGET_SLEEP_H, dailyLimitMg: 400, cutoffHour: 16 },
      addDose: (d) => set((s) => ({ doses: [...s.doses, d] })),
      updateDose: (id, patch) => set((s) => ({
        doses: s.doses.map((d) => (d.id === id ? { ...d, ...patch, id: d.id } : d)),
      })),
      removeDose: (id) => set((s) => ({ doses: s.doses.filter((d) => d.id !== id) })),
      addSleep: (sl) => set((s) => ({ sleeps: [...s.sleeps, sl] })),
      setPrefs: (p) => set((s) => ({ prefs: { ...s.prefs, ...p } })),
    }),
    {
      name: 'aurora/state',
      version: 1,
      storage: mmkvStorage,
      partialize: (s) => ({ doses: s.doses, sleeps: s.sleeps, prefs: s.prefs }),
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
