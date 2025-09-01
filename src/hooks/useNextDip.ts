import { useMemo } from 'react';
import { useStore } from '~/state/store';
import { alertnessScore } from '~/domain/algorithm/alertness';

export type NextDipInfo = {
  nextDipAt: number | null;     // ms epoch of the next local minimum (or overall min fallback)
  nextDipScore: number | null;  // score at that time
  series: { t: number; score: number }[]; // projected series for visualization
};

/**
 * Finds the next alertness dip using a discrete projection of the model.
 * - Samples every 15 minutes over the next 12 hours
 * - Picks the first local minimum at least 30 minutes in the future
 * - Falls back to the global minimum in the horizon if no local minimum exists
 */
export default function useNextDip(): NextDipInfo {
  const { doses, sleeps, prefs } = useStore();

  return useMemo(() => {
    const now = Date.now();
    const step = 15 * 60 * 1000;     // 15 min
    const horizon = 12 * 60 * 60 * 1000; // 12 h

    const series: { t: number; score: number }[] = [];
    for (let t = now; t <= now + horizon; t += step) {
      series.push({ t, score: alertnessScore(t, doses, sleeps, prefs) });
    }

    // Prefer the first local minimum beyond a 30-minute buffer
    const minStart = now + 30 * 60 * 1000;
    let dipIndex: number | null = null;
    for (let i = 1; i < series.length - 1; i++) {
      const a = series[i - 1].score;
      const b = series[i].score;
      const c = series[i + 1].score;
      if (series[i].t >= minStart && a > b && c > b) {
        dipIndex = i;
        break;
      }
    }

    // Fallback: overall minimum after buffer
    if (dipIndex === null) {
      let bestIdx = -1;
      let bestScore = Infinity;
      for (let i = 0; i < series.length; i++) {
        if (series[i].t < minStart) continue;
        if (series[i].score < bestScore) {
          bestScore = series[i].score;
          bestIdx = i;
        }
      }
      dipIndex = bestIdx >= 0 ? bestIdx : null;
    }

    const nextDipAt = dipIndex !== null ? series[dipIndex].t : null;
    const nextDipScore = dipIndex !== null ? series[dipIndex].score : null;

    return { nextDipAt, nextDipScore, series };
  }, [doses, sleeps, prefs]);
}