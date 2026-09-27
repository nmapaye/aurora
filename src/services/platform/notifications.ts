import * as Notifications from 'expo-notifications';

import { cutoffReminder } from '~/services/platform/notificationContent';

const CUTOFF_REMINDER_ID = 'cutoff-reminder';

export async function requestNotificationPermission(
  { prompt = true }: { prompt?: boolean } = {},
): Promise<boolean> {
  const current = await Notifications.getPermissionsAsync();
  if (current.granted) return true;
  if (!prompt || !current.canAskAgain) return false;
  const requested = await Notifications.requestPermissionsAsync();
  return requested.granted;
}

// Keeps the scheduled reminder in sync with prefs; returns whether a
// reminder is scheduled afterwards.
async function applyCutoffReminder(
  enabled: boolean,
  cutoffHour: number,
  intent: number,
  prompt: boolean,
): Promise<boolean> {
  await Notifications.cancelScheduledNotificationAsync(CUTOFF_REMINDER_ID);
  if (!enabled || intent !== latestIntent) return false;

  const granted = await requestNotificationPermission({ prompt });
  if (!granted || intent !== latestIntent) return false;

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

// Native cancellation and scheduling must never overlap. A rejected operation
// still releases the queue so the user's next intent can retry.
let reminderQueue: Promise<unknown> = Promise.resolve();
let latestIntent = 0;
// `prompt: false` is for background reconciliation (app foreground), which
// must never raise the system permission dialog.
export function syncCutoffReminder(
  enabled: boolean,
  cutoffHour: number,
  { prompt = true }: { prompt?: boolean } = {},
): Promise<boolean> {
  const intent = ++latestIntent;
  const operation = reminderQueue.then(() =>
    applyCutoffReminder(enabled, cutoffHour, intent, prompt),
  );
  reminderQueue = operation.catch(() => undefined);
  return operation;
}
