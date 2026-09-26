import type { SleepSessionInput } from '../models';
import { BRIEF_AWAKENING_MS, mergeSleepIntervals } from './sleepIntervals';

export function minutesSinceLastWake(nowMs: number, sleeps: SleepSessionInput[]){
  const started = sleeps.filter(s => s.start <= nowMs);
  // Wake time is the end of a whole sleep episode, not of a stage segment.
  const past = mergeSleepIntervals(started, BRIEF_AWAKENING_MS)
    .filter(s => s.end <= nowMs)
    .sort((a,b)=>b.end-a.end)[0];
  if(!past) return Infinity;
  return (nowMs - past.end)/60000;
}
export function inertia(nowMs: number, sleeps: SleepSessionInput[]){
  const m = minutesSinceLastWake(nowMs, sleeps);
  if(m <= 90) return 0.15 * Math.exp(-m/45);
  return 0;
}
