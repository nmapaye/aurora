import { useMemo } from 'react';
import { useStore } from '~/state/store';
import { mgActive } from '~/domain/algorithm/caffeine';

export type CaffeineCutoff = {
  cutoffHour: number;          // Local hour-of-day for cutoff (0-23)
  nextCutoff: number;          // ms epoch for the next cutoff boundary
  isAfterCutoff: boolean;      // true if now is past today's cutoff
  mgAtNextCutoff: number;      // projected active mg at nextCutoff
  nextBedtime: number;         // ms epoch for the next bedtime checkpoint
  mgAtNextBedtime: number;     // projected active mg at nextBedtime
  shouldWarn: boolean;         // simple policy flag for UI notifications
};

/**
 * Computes a simple caffeine cutoff policy and projections.
 * - Default cutoff hour: 16:00 local
 * - Default bedtime checkpoint: 23:00 local (same day if before cutoff, else next day)
 * - Projections use current doses and prefs.halfLife
 *
 * This avoids timezone math by using the device local clock.
 * If you later add a user preference for cutoffHour, wire it here.
 */
export default function useCaffeineCutoff(): CaffeineCutoff {
  const { doses, prefs } = useStore();

  return useMemo(() => {
    const now = Date.now();
    const cutoffHour = Math.max(0, Math.min(23, prefs.cutoffHour ?? 16));
    const bedtimeHour = 23;  // heuristic checkpoint for sleep
    
    // Build today's cutoff in local time
    const today = new Date();
    const cutoff = new Date(today);
    cutoff.setHours(cutoffHour, 0, 0, 0);
    let nextCutoff = cutoff.getTime();
    const isAfterCutoff = now >= nextCutoff;
    if (isAfterCutoff) {
      const t = new Date(cutoff);
      t.setDate(t.getDate() + 1);
      nextCutoff = t.getTime();
    }

    // Bedtime checkpoint (same day if before cutoff; else next day)
    const bedtime = new Date(today);
    if (isAfterCutoff) bedtime.setDate(bedtime.getDate() + 1);
    bedtime.setHours(bedtimeHour, 0, 0, 0);
    const nextBedtime = bedtime.getTime();

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
  }, [doses, prefs.halfLife]);
}
