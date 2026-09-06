import { AppState } from 'react-native';
import { useEffect, useState } from 'react';
import { useStore } from '~/state/store';
import {
  syncWindDownReminders,
  syncCutoffReminder,
} from '~/services/platform/notifications';
import { localDateKey } from '~/utils/calendar';
import useNow from './useNow';
/** Refresh the next 14 days after a schedule edit, relaunch or calendar change. */
export default function useSleepReminders(ready: boolean) {
  const [foregroundRevision, setForegroundRevision] = useState(0);
  useEffect(() => {
    const subscription = AppState.addEventListener('change', (state) => {
      if (state === 'active') setForegroundRevision((v) => v + 1);
    });
    return () => subscription.remove();
  }, []);
  const routines = useStore((s) => s.sleepRoutines),
    onboarding = useStore((s) => s.onboarding);
  const prefs = useStore((s) => s.prefs);
  const now = useNow(),
    day = localDateKey(now),
    timezoneOffset = new Date(now).getTimezoneOffset();
  useEffect(() => {
    if (!ready || !onboarding.completed || !onboarding.appWalkthroughCompleted)
      return;
    let current = true;
    syncCutoffReminder(prefs.notifyCutoff, prefs.cutoffHour, routines)
      .then((scheduled) => {
        if (current && prefs.notifyCutoff && !scheduled)
          useStore.getState().setPrefs({ notifyCutoff: false });
      })
      .catch(() => {
        if (current && prefs.notifyCutoff)
          useStore.getState().setPrefs({ notifyCutoff: false });
      });
    syncWindDownReminders(routines, Date.now())
      .then((scheduled) => {
        if (current && routines.windDown.enabled && !scheduled) {
          useStore.getState().setSleepRoutines({
            windDown: { ...routines.windDown, enabled: false },
          });
        }
      })
      .catch(() => {
        if (current && routines.windDown.enabled)
          useStore.getState().setSleepRoutines({
            windDown: { ...routines.windDown, enabled: false },
          });
      });
    return () => {
      current = false;
    };
  }, [
    ready,
    foregroundRevision,
    routines.weekly,
    routines.exceptions,
    routines.windDown,
    prefs.notifyCutoff,
    prefs.cutoffHour,
    day,
    timezoneOffset,
    onboarding.completed,
    onboarding.appWalkthroughCompleted,
  ]);
}
