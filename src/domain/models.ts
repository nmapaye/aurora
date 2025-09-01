export type Dose = { id: string; timestamp: number; mg: number; source?: string; note?: string };
export type SleepSession = { id: string; start: number; end: number; type: 'sleep'|'nap' };
export type UserPrefs = { halfLife: number; targetSleep: number; cutoffHour?: number; tz?: string };
  