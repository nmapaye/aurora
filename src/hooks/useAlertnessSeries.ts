import { useMemo } from 'react';
import { useStore } from '~/state/store';
import { alertnessScore } from '~/domain/algorithm/alertness';
import { mgActive } from '~/domain/algorithm/caffeine';

export function useAlertnessSeries(){
  const { doses, sleeps, prefs } = useStore();
  const t0 = Date.now();
  const nowScore = useMemo(()=>alertnessScore(t0, doses, sleeps, prefs), [t0,doses,sleeps,prefs]);
  const mgActiveNow = useMemo(()=>mgActive(t0, doses, prefs.halfLife), [t0,doses,prefs.halfLife]);
  const series = useMemo(()=>{
    const step = 15*60*1000; // 15 min
    return Array.from({length: (12*60)/15 + 1}, (_,i)=>{
      const t = t0 + i*step;
      return { t, score: alertnessScore(t, doses, sleeps, prefs) };
    });
  }, [t0,doses,sleeps,prefs]);
  return { nowScore, mgActiveNow, series };
}
  