import { useEffect, useState } from 'react';
import { AppState } from 'react-native';

/** Refresh time-sensitive screens without persisting a clock in application state. */
export default function useNow(intervalMs = 60_000): number {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const refresh = () => setNow(Date.now());
    const timer = setInterval(refresh, Math.max(1000, intervalMs));
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') refresh();
    });
    return () => {
      clearInterval(timer);
      subscription.remove();
    };
  }, [intervalMs]);
  return now;
}
