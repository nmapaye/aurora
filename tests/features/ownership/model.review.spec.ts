import { defaultOwnership, normalizeOwnership, reminderPlan, visibleSummaryCards, SUMMARY_CARDS } from '~/features/ownership/model';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';

const prefs = { notifyCutoff: false, cutoffHour: 16 };
it('treats quiet start as included and quiet end as excluded across midnight', () => {
  const state = defaultOwnership();
  state.reminders.checkIn.enabled = true;
  state.reminders.quiet = { enabled: true, start: 1320, end: 420 };
  const now = new Date(2026, 8, 7, 0).getTime();
  for (const minute of [1320, 1439, 0, 419]) {
    state.reminders.checkIn.minute = minute;
    expect(reminderPlan(state, defaultSleepRoutines(8), prefs, now)).toEqual([]);
  }
  state.reminders.checkIn.minute = 420;
  expect(reminderPlan(state, defaultSleepRoutines(8), prefs, now)).toHaveLength(14);
});

it('applies wind-down weekdays to the reminder fire date when bedtime crosses midnight', () => {
  const state = defaultOwnership(), routines = defaultSleepRoutines(8);
  routines.weekly = routines.weekly.map(() => ({ bedtime: 15, wake: 495 }));
  routines.windDown = { enabled: true, leadMinutes: 30 };
  state.reminders.windDown.weekdays = [0];
  const now = new Date(2026, 8, 6, 20).getTime();
  const result = reminderPlan(state, routines, prefs, now);
  expect(result).toHaveLength(2);
  expect(result.every(reminder => new Date(reminder.at).getDay() === 0)).toBe(true);
  expect(result[0].at).toBe(new Date(2026, 8, 6, 23, 45).getTime());
});

it('keeps local reminder wall time across spring and fall calendar transitions', () => {
  for (const now of [new Date(2026, 2, 7, 12).getTime(), new Date(2026, 9, 31, 12).getTime()]) {
    const state = defaultOwnership();
    state.reminders.checkIn = { enabled: true, minute: 840, weekdays: [0, 1, 2, 3, 4, 5, 6] };
    const rows = reminderPlan(state, defaultSleepRoutines(8), prefs, now);
    expect(rows).toHaveLength(14);
    expect(rows.every(row => new Date(row.at).getHours() === 14)).toBe(true);
    if (process.env.TZ === 'America/New_York') {
      expect(rows[1].at - rows[0].at).toBe((new Date(now).getMonth() === 2 ? 23 : 25) * 3600000);
    }
  }
});

it('restores every walkthrough card without losing saved customization', () => {
  const state = normalizeOwnership({ summary: { order: ['sleep', 'sleep', 'bad'], hidden: ['sleep', 'caffeine', 'bad'] } });
  const saved = JSON.stringify(state);
  expect(visibleSummaryCards(state, true)).toEqual([...SUMMARY_CARDS]);
  expect(visibleSummaryCards(state, false)).not.toContain('sleep');
  expect(JSON.stringify(state)).toBe(saved);
  expect(new Set(state.summary.order).size).toBe(SUMMARY_CARDS.length);
});
