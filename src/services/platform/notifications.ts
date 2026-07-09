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

// Keeps the scheduled reminder in sync with prefs; returns whether a
// reminder is scheduled afterwards.
export async function syncCutoffReminder(
  enabled: boolean,
  cutoffHour: number
): Promise<boolean> {
  await Notifications.cancelScheduledNotificationAsync(CUTOFF_REMINDER_ID);
  if (!enabled) return false;

  const granted = await requestNotificationPermission();
  if (!granted) return false;

  const reminder = cutoffReminder(cutoffHour);
  await Notifications.scheduleNotificationAsync({
    identifier: CUTOFF_REMINDER_ID,
    content: { title: reminder.title, body: reminder.body },
    trigger: {
      type: Notifications.SchedulableTriggerInputTypes.DAILY,
      hour: reminder.hour,
      minute: reminder.minute,
    },
  });
  return true;
}
