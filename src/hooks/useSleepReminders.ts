import { AppState } from 'react-native';
import { useEffect, useState } from 'react';
import { useStore } from '~/state/store';
import { syncReminderCenter } from '~/services/platform/reminderCenter';
import { localDateKey } from '~/utils/calendar';
import useNow from './useNow';
/** Replenish 14 calendar days after changes and every foreground. */
export default function useSleepReminders(ready: boolean) {
  const [revision, setRevision] = useState(0);
  useEffect(() => {
    const sub = AppState.addEventListener('change', (state) => {
      if (state === 'active') setRevision((v) => v + 1);
    });
    return () => sub.remove();
  }, []);
  const ownership = useStore((s) => s.ownership),
    routines = useStore((s) => s.sleepRoutines),
    prefs = useStore((s) => s.prefs),
    onboarding = useStore((s) => s.onboarding);
  const now = useNow(),
    day = localDateKey(now),
    offset = new Date(now).getTimezoneOffset();
  useEffect(() => {
    if (!ready) return;
    void syncReminderCenter(
      ownership,
      routines,
      prefs,
      Date.now(),
      onboarding.completed && onboarding.appWalkthroughCompleted,
    ).catch(() => {});
  }, [
    ready,
    revision,
    ownership.reminders,
    routines.weekly,
    routines.exceptions,
    routines.windDown,
    prefs.notifyCutoff,
    prefs.cutoffHour,
    day,
    offset,
    onboarding.completed,
    onboarding.appWalkthroughCompleted,
  ]);
}
