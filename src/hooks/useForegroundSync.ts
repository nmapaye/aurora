import { useEffect } from 'react';
import { AppState } from 'react-native';

import { importHealthSleep } from '~/features/sleep/healthImport';
import { syncCutoffReminder } from '~/services/platform/notifications';
import { useStore } from '~/state/store';

export const HEALTH_REFRESH_INTERVAL_MS = 15 * 60 * 1000;
export const HEALTH_REFRESH_DAYS = 30;

/** Whether a quiet background Health refresh is due. */
export function shouldRefreshHealth(now = Date.now()) {
  const { onboarding, healthSync, demoMode } = useStore.getState();
  if (!onboarding.completed || demoMode) return false;
  if (onboarding.permissionStatus !== 'granted') return false;
  if (healthSync.importStatus === 'importing') return false;
  return (
    healthSync.lastSyncedAt === undefined ||
    now - healthSync.lastSyncedAt >= HEALTH_REFRESH_INTERVAL_MS
  );
}

export async function runForegroundSync(now = Date.now()) {
  const { prefs, onboarding } = useStore.getState();
  if (!onboarding.completed) return;
  const tasks: Promise<unknown>[] = [
    // Re-schedules the reminder if it was lost, and drops it when permission
    // was revoked in system Settings. Never prompts.
    syncCutoffReminder(prefs.notifyCutoff, prefs.cutoffHour, { prompt: false }),
  ];
  if (shouldRefreshHealth(now)) {
    tasks.push(importHealthSleep({ days: HEALTH_REFRESH_DAYS, now }));
  }
  await Promise.allSettled(tasks);
}

/** Keeps Health sleep and the cutoff reminder current whenever Aurora becomes active. */
export function useForegroundSync(ready: boolean) {
  useEffect(() => {
    if (!ready) return undefined;
    runForegroundSync();
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') runForegroundSync();
    });
    return () => subscription.remove();
  }, [ready]);
}
