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
