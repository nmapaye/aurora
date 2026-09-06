import { useStore } from '~/state/store';
import { mgActive } from '~/domain/algorithm/caffeine';
import type { Dose } from '~/domain/models';
import {
  defaultSleepRoutines,
  nextScheduledSleep,
  type SleepRoutines,
} from '~/features/sleep/upgrades';
import useNow from './useNow';
export type SleepGuidance = { bedtime: number; wake: number; mgAtBed: number };
export function getSleepGuidance(
  doses: readonly Dose[],
  halfLife: number,
  now = Date.now(),
  routines: SleepRoutines = defaultSleepRoutines(8),
): SleepGuidance {
  const planned = nextScheduledSleep(routines, now);
  return {
    ...planned,
    mgAtBed: Math.round(mgActive(planned.bedtime, [...doses], halfLife)),
  };
}
export default function useSleepGuidance(
  selectedDoses?: readonly Dose[],
): SleepGuidance {
  const stored = useStore((s) => s.doses),
    halfLife = useStore((s) => s.prefs.halfLife),
    routines = useStore((s) => s.sleepRoutines);
  return getSleepGuidance(
    selectedDoses ?? stored,
    halfLife,
    useNow(),
    routines,
  );
}
