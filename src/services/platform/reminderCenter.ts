import * as Notifications from 'expo-notifications';
import {
  reminderPlan,
  REMINDER_KINDS,
  type OwnershipState,
} from '~/features/ownership/model';
import type { SleepRoutines } from '~/features/sleep/upgrades';
export type ReminderPermission =
  | 'granted'
  | 'denied'
  | 'undetermined'
  | 'unavailable';
export async function notificationPermission(): Promise<ReminderPermission> {
  try {
    const p = await Notifications.getPermissionsAsync();
    return p.granted
      ? 'granted'
      : p.status === 'denied'
        ? 'denied'
        : p.canAskAgain
          ? 'undetermined'
          : 'denied';
  } catch {
    return 'unavailable';
  }
}
const ownedIds = [
  'cutoff-reminder',
  ...Array.from({ length: 14 }, (_, i) => [
    `cutoff-reminder:${i}`,
    `wind-down:${i}`,
    ...REMINDER_KINDS.map((k) => `aurora-reminder:${k}:${i}`),
  ]).flat(),
];
let queue: Promise<unknown> = Promise.resolve();
async function cancelOwned() {
  const results = await Promise.allSettled(
    ownedIds.map((id) => Notifications.cancelScheduledNotificationAsync(id)),
  );
  if (results.some((x) => x.status === 'rejected'))
    throw new Error('Could not clear previous Aurora reminders.');
}
export function syncReminderCenter(
  ownership: OwnershipState,
  routines: SleepRoutines,
  prefs: { notifyCutoff: boolean; cutoffHour: number },
  now: number,
  allowed: boolean,
  requestPermission = false,
): Promise<ReminderPermission> {
  const job = queue
    .catch(() => {})
    .then(async () => {
      await cancelOwned();
      let permission = await notificationPermission();
      const plan = allowed ? reminderPlan(ownership, routines, prefs, now) : [];
      if (allowed && requestPermission && permission === 'undetermined') {
        const result = await Notifications.requestPermissionsAsync();
        permission = result.granted
          ? 'granted'
          : result.status === 'denied'
            ? 'denied'
            : result.canAskAgain
              ? 'undetermined'
              : 'denied';
      }
      if (permission !== 'granted') return permission;
      try {
        for (const item of plan)
          await Notifications.scheduleNotificationAsync({
            identifier: item.id,
            content: { title: item.title, body: item.body },
            trigger: {
              type: Notifications.SchedulableTriggerInputTypes.DATE,
              date: new Date(item.at),
            },
          });
      } catch (error) {
        await cancelOwned();
        throw error;
      }
      return permission;
    });
  queue = job;
  return job;
}
export function cancelAuroraReminders() {
  const job = queue.catch(() => {}).then(cancelOwned);
  queue = job;
  return job;
}
