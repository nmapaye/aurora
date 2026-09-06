import * as Notifications from 'expo-notifications';

import { cutoffReminder } from '~/services/platform/notificationContent';

const CUTOFF_REMINDER_ID = 'cutoff-reminder';

export async function requestNotificationPermission(): Promise<boolean> {
  const current = await Notifications.getPermissionsAsync();
  if (current.granted) return true;
  if (!current.canAskAgain) return false;
  const requested = await Notifications.requestPermissionsAsync();
  return requested.granted;
}

// Serialize replacements so rapid preference changes leave the newest plan scheduled.
let cutoffQueue: Promise<unknown> = Promise.resolve();
export function syncCutoffReminder(
  enabled: boolean,
  cutoffHour: number,
  routines: SleepRoutines,
  now = Date.now(),
): Promise<boolean> {
  const job = cutoffQueue
    .catch(() => {})
    .then(async () => {
      await Notifications.cancelScheduledNotificationAsync(CUTOFF_REMINDER_ID);
      for (let i = 0; i < 14; i++)
        await Notifications.cancelScheduledNotificationAsync(
          `${CUTOFF_REMINDER_ID}:${i}`,
        );
      if (!enabled || !(await requestNotificationPermission())) return false;
      try {
        const reminder = cutoffReminder(cutoffHour);
        for (let i = 0; i < 14; i++) {
          const at = new Date(now);
          at.setDate(at.getDate() + i);
          at.setHours(reminder.hour, 0, 0, 0);
          if (at.getTime() <= now) continue;
          const bedtime = nextScheduledSleep(routines, at.getTime()).bedtime;
          await Notifications.scheduleNotificationAsync({
            identifier: `${CUTOFF_REMINDER_ID}:${i}`,
            content: {
              title: reminder.title,
              body: `Your caffeine cutoff is ${reminder.hour}:00. Planned bedtime: ${new Date(bedtime).toLocaleString([], { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}.`,
            },
            trigger: {
              type: Notifications.SchedulableTriggerInputTypes.DATE,
              date: at,
            },
          });
        }
      } catch (error) {
        await Promise.allSettled(
          Array.from({ length: 14 }, (_, i) =>
            Notifications.cancelScheduledNotificationAsync(
              `${CUTOFF_REMINDER_ID}:${i}`,
            ),
          ),
        );
        throw error;
      }
      return true;
    });
  cutoffQueue = job;
  return job;
}

import { windDownReminders } from './notificationContent';
import {
  nextScheduledSleep,
  type SleepRoutines,
} from '~/features/sleep/upgrades';
let windDownQueue: Promise<unknown> = Promise.resolve();
export function syncWindDownReminders(
  routines: SleepRoutines,
  now: number,
): Promise<boolean> {
  const job = windDownQueue
    .catch(() => {})
    .then(async () => {
      for (let i = 0; i < 14; i++)
        await Notifications.cancelScheduledNotificationAsync(`wind-down:${i}`);
      if (!routines.windDown.enabled) return false;
      if (!(await requestNotificationPermission())) return false;
      try {
        for (const reminder of windDownReminders(routines, now)) {
          await Notifications.scheduleNotificationAsync({
            identifier: reminder.id,
            content: { title: reminder.title, body: reminder.body },
            trigger: {
              type: Notifications.SchedulableTriggerInputTypes.DATE,
              date: new Date(reminder.date),
            },
          });
        }
      } catch (error) {
        await Promise.allSettled(
          Array.from({ length: 14 }, (_, i) =>
            Notifications.cancelScheduledNotificationAsync(`wind-down:${i}`),
          ),
        );
        throw error;
      }
      return true;
    });
  windDownQueue = job;
  return job;
}
