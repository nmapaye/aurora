import { useMemo } from 'react';
import { useStore } from '~/state/store';
import { mgActive } from '~/domain/algorithm/caffeine';

export type SleepGuidance = {
  bedtime: number;      // suggested bedtime (ms epoch)
  wake: number;         // suggested wake time (ms epoch)
  mgAtBed: number;      // projected active mg at bedtime
};

/**
 * Suggest bedtime based on caffeine decay (half-life) and a baseline 22:30 target,
 * and suggest a wake time aligned to 90-minute cycles, preferring 6–7am.
 */
export default function useSleepGuidance(): SleepGuidance {
  const doses = useStore((s) => s.doses);
  const halfLife = useStore((s) => s.prefs.halfLife);

  return useMemo(() => {
    const now = Date.now();

    // Baseline bedtime 22:30 local tonight (or tomorrow if already past)
    const base = new Date();
    base.setHours(22, 30, 0, 0);
    const baseBed = base.getTime() <= now ? (() => { const d = new Date(base); d.setDate(d.getDate() + 1); return d.getTime(); })() : base.getTime();

    // Find earliest time when mgActive falls below threshold
    const threshold = 40; // mg deemed low enough near bedtime
    const step = 15 * 60 * 1000; // 15 min
    let t = now;
    let safeAt = baseBed; // default to baseline if already low before then
    for (let i = 0; i < (48 * 60) / 15; i++) { // up to 48h scan
      const mg = mgActive(t, doses, halfLife);
      if (mg <= threshold) { safeAt = t; break; }
      t += step;
    }

    const bedtime = Math.max(baseBed, safeAt);
    const mgAtBed = Math.round(mgActive(bedtime, doses, halfLife));

    // 90-minute cycles; prefer wake between 06:00–07:00 local next morning
    const windowDay = new Date(bedtime);
    // Wake window is the morning after bedtime
    const targetStart = new Date(windowDay);
    targetStart.setDate(targetStart.getDate() + 1);
    targetStart.setHours(6, 0, 0, 0);
    const targetEnd = new Date(targetStart); targetEnd.setHours(7, 0, 0, 0);
    const targetMid = new Date((targetStart.getTime() + targetEnd.getTime()) / 2);

    const cycleMs = 90 * 60 * 1000;
    const wakes: number[] = [];
    for (let k = 3; k <= 8; k++) { // 4.5h to 12h after bedtime
      wakes.push(bedtime + k * cycleMs);
    }
    const inWindow = wakes.filter((w) => w >= targetStart.getTime() && w <= targetEnd.getTime());
    const pickNearest = (arr: number[]) => arr.reduce((best, x) => (Math.abs(x - targetMid.getTime()) < Math.abs(best - targetMid.getTime()) ? x : best), arr[0]);
    const wake = (inWindow.length ? pickNearest(inWindow) : pickNearest(wakes));

    return { bedtime, wake, mgAtBed };
  }, [doses, halfLife]);
}

