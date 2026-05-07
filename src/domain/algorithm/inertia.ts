import type { SleepSessionInput } from '../models';

export function minutesSinceLastWake(nowMs: number, sleeps: SleepSessionInput[]){
  const past = sleeps.filter(s => s.end <= nowMs).sort((a,b)=>b.end-a.end)[0];
  if(!past) return Infinity;
  return (nowMs - past.end)/60000;
}
export function inertia(nowMs: number, sleeps: SleepSessionInput[]){
  const m = minutesSinceLastWake(nowMs, sleeps);
  if(m <= 90) return 0.15 * Math.exp(-m/45);
  return 0;
}
