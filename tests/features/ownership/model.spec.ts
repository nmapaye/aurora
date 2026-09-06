import {
  defaultOwnership,
  visibleSummaryCards,
  reminderPlan,
} from '~/features/ownership/model';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
test('walkthrough restores all required cards despite customization', () => {
  const state = defaultOwnership();
  state.summary.hidden = ['caffeine'];
  state.summary.order.reverse();
  expect(visibleSummaryCards(state, true)).toEqual(
    defaultOwnership().summary.order,
  );
  expect(visibleSummaryCards(state, false)).not.toContain('caffeine');
});
test('quiet overnight hours suppress reminders without moving them to another day', () => {
  const state = defaultOwnership();
  state.reminders.checkIn.enabled = true;
  state.reminders.checkIn.minute = 60;
  state.reminders.quiet = { enabled: true, start: 1320, end: 420 };
  const now = new Date(2026, 8, 7, 0).getTime();
  expect(
    reminderPlan(
      state,
      defaultSleepRoutines(8),
      { notifyCutoff: false, cutoffHour: 16 },
      now,
    ),
  ).toEqual([]);
  state.reminders.checkIn.minute = 600;
  state.reminders.checkIn.weekdays = [1];
  const plan = reminderPlan(
    state,
    defaultSleepRoutines(8),
    { notifyCutoff: false, cutoffHour: 16 },
    now,
  );
  expect(plan).toHaveLength(2);
  expect(plan.every((x) => new Date(x.at).getDay() === 1)).toBe(true);
});
