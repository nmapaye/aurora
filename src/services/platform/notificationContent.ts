export type CutoffReminder = {
  title: string;
  body: string;
  hour: number;
  minute: number;
};

// Pure so it can be unit-tested without the expo-notifications native module.
export function cutoffReminder(cutoffHour: number): CutoffReminder {
  const hour = Math.max(0, Math.min(23, Math.round(cutoffHour)));
  return {
    title: 'Last call for caffeine',
    body: `After ${hour}:00, caffeine is likely to affect tonight's sleep.`,
    hour,
    minute: 0,
  };
}

import { scheduledSleep, type SleepRoutines } from '~/features/sleep/upgrades';
import { addCalendarDays, localDateKey } from '~/utils/calendar';
export function windDownReminders(routines: SleepRoutines, now: number) {
  if (!routines.windDown.enabled) return [];
  return Array.from({ length: 14 }, (_, i) => {
    const key = localDateKey(addCalendarDays(now, i));
    const planned = scheduledSleep(routines, key);
    return {
      id: `wind-down:${i}`,
      date: planned.bedtime - routines.windDown.leadMinutes * 60000,
      title: 'Time to wind down',
      body: `Your planned bedtime is ${new Date(planned.bedtime).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}.`,
    };
  }).filter((r) => r.date > now);
}
