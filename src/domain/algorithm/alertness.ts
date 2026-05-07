import { circadianC } from './circadian';
import { sleepDebt } from './sleepDebt';
import { inertia } from './inertia';
import { mgActiveEffect } from './caffeine';
import type { CaffeineDoseInput, SleepSessionInput, UserPrefs } from '../models';

export function alertnessScore(
  nowMs: number,
  doses: CaffeineDoseInput[],
  sleeps: SleepSessionInput[],
  params: Pick<UserPrefs, 'halfLife' | 'targetSleep' | 'tz'>,
){
  const E = mgActiveEffect(nowMs, doses, params.halfLife);
  const C = circadianC(nowMs, params.tz);
  const S = sleepDebt(nowMs, sleeps, params.targetSleep);
  const I = inertia(nowMs, sleeps);
  const score = Math.max(0, Math.min(100, 30 + 50*C + 40*E - 40*S - 100*I));
  return score;
}
