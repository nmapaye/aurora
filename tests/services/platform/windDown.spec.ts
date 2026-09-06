import { defaultSleepRoutines } from '~/features/sleep/upgrades';
import { windDownReminders } from '~/services/platform/notificationContent';
it('schedules future lead times from weekly and dated sleep plans', () => {
  const state = defaultSleepRoutines(8);
  state.windDown = { enabled: true, leadMinutes: 45 };
  state.exceptions['2026-09-07'] = { bedtime: 1260, wake: 300 };
  const reminders = windDownReminders(
    state,
    new Date('2026-09-07T20:00:00').getTime(),
  );
  expect(reminders[0].date).toBe(new Date('2026-09-07T20:15:00').getTime());
  expect(
    windDownReminders(state, new Date('2026-09-07T20:30:00').getTime())[0].date,
  ).toBe(new Date('2026-09-08T21:45:00').getTime());
  state.windDown.enabled = false;
  expect(windDownReminders(state, Date.now())).toEqual([]);
});
