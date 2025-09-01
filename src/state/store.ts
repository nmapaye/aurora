import { create } from 'zustand';
import { DEFAULT_HALFLIFE_H, DEFAULT_TARGET_SLEEP_H } from '~/domain/constants';

type Dose = { id:string; timestamp:number; mg:number; source?:string };
type Sleep = { id:string; start:number; end:number; type:'sleep'|'nap' };
type Prefs = { halfLife:number; targetSleep:number; tz?:string };

type State = {
  doses: Dose[];
  sleeps: Sleep[];
  prefs: Prefs;
  addDose: (d: Dose)=>void;
  addSleep: (s: Sleep)=>void;
  setPrefs: (p: Partial<Prefs>)=>void;
};

export const useStore = create<State>((set)=>({
  // Seeded mock data (Step 2)
  doses: [],
  sleeps: [],
  prefs: { halfLife: DEFAULT_HALFLIFE_H, targetSleep: DEFAULT_TARGET_SLEEP_H },
  addDose: (d)=> set(s=>({ doses:[...s.doses, d] })),
  addSleep: (sl)=> set(s=>({ sleeps:[...s.sleeps, sl] })),
  setPrefs: (p)=> set(s=>({ prefs:{ ...s.prefs, ...p } }))
}));