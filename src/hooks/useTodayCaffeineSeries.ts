import { useMemo } from 'react';
import { useStore } from '~/state/store';
import { mgActive } from '~/domain/algorithm/caffeine';

type Point = { t: number; mg: number; hasDose: boolean };

export function useTodayCaffeineSeries(stepMinutes = 60) {
  const { doses, prefs } = useStore();

  return useMemo(() => {
    const now = Date.now();
    const start = (() => {
      const d = new Date(now);
      d.setHours(0, 0, 0, 0);
      return d.getTime();
    })();
    const end = (() => {
      const d = new Date(start);
      d.setHours(24, 0, 0, 0);
      return d.getTime();
    })();

    const stepMs = Math.max(1, stepMinutes * 60 * 1000);
    const count = Math.max(2, Math.round((end - start) / stepMs) + 1);

    // Track which hourly buckets have at least one dose so we can show dots there
    const bucketsWithDose = new Set<number>();
    doses.forEach((d) => {
      if (d.timestamp >= start && d.timestamp <= end) {
        const bucket = Math.floor((d.timestamp - start) / stepMs);
        bucketsWithDose.add(bucket);
      }
    });

    const series: Point[] = Array.from({ length: count }, (_, i) => {
      const t = start + i * stepMs;
      return { t, mg: mgActive(t, doses, prefs.halfLife), hasDose: bucketsWithDose.has(i) };
    });

    // Ensure we include "now" so the line reflects current intake even if step alignment skips it
    if (now > start && now < end) {
      const bucket = Math.floor((now - start) / stepMs);
      series.push({ t: now, mg: mgActive(now, doses, prefs.halfLife), hasDose: bucketsWithDose.has(bucket) });
      series.sort((a, b) => a.t - b.t);
    }

    return { series, start, end };
  }, [doses, prefs.halfLife, stepMinutes]);
}
