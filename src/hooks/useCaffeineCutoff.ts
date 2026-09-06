import { useMemo } from 'react';
import useNow from './useNow';
import { nextScheduledSleep } from '~/features/sleep/upgrades';
import { useStore } from '~/state/store';
import { mgActive } from '~/domain/algorithm/caffeine';

export type CaffeineCutoff = {
  cutoffHour: number; // Local hour-of-day for cutoff (0-23)
  nextCutoff: number; // ms epoch for the next cutoff boundary
  isAfterCutoff: boolean; // true if now is past today's cutoff
  mgAtNextCutoff: number; // projected active mg at nextCutoff
  nextBedtime: number; // ms epoch for the next bedtime checkpoint
  mgAtNextBedtime: number; // projected active mg at nextBedtime
  shouldWarn: boolean; // simple policy flag for UI notifications
};

export default function useCaffeineCutoff(): CaffeineCutoff {
  const { doses, prefs, sleepRoutines } = useStore();
  const now = useNow();

  return useMemo(() => {
    const cutoffHour = Math.max(0, Math.min(23, prefs.cutoffHour ?? 16));

    // Build today's cutoff in local time
    const today = new Date(now);
    const cutoff = new Date(today);
    cutoff.setHours(cutoffHour, 0, 0, 0);
    let nextCutoff = cutoff.getTime();
    const isAfterCutoff = now >= nextCutoff;
    if (isAfterCutoff) {
      const t = new Date(cutoff);
      t.setDate(t.getDate() + 1);
      nextCutoff = t.getTime();
    }

    const nextBedtime = nextScheduledSleep(sleepRoutines, now).bedtime;

    const mgAtNextCutoff = mgActive(nextCutoff, doses, prefs.halfLife);
    const mgAtNextBedtime = mgActive(nextBedtime, doses, prefs.halfLife);

    // Basic warn policy: after cutoff and still >40 mg near bedtime
    const shouldWarn = isAfterCutoff && mgAtNextBedtime > 40;

    return {
      cutoffHour,
      nextCutoff,
      isAfterCutoff,
      mgAtNextCutoff,
      nextBedtime,
      mgAtNextBedtime,
      shouldWarn,
    };
  }, [doses, prefs.halfLife, prefs.cutoffHour, sleepRoutines, now]);
}
