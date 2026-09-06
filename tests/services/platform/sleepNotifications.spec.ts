import * as Notifications from 'expo-notifications';
import {
  syncCutoffReminder,
  syncWindDownReminders,
} from '~/services/platform/notifications';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
jest.mock('expo-notifications', () => ({
  cancelScheduledNotificationAsync: jest.fn().mockResolvedValue(undefined),
  getPermissionsAsync: jest.fn().mockResolvedValue({ granted: true }),
  requestPermissionsAsync: jest.fn(),
  scheduleNotificationAsync: jest.fn().mockResolvedValue('id'),
  SchedulableTriggerInputTypes: { DATE: 'date' },
}));
beforeEach(() => jest.clearAllMocks());
it('cancels old wind-down reminders when permission is denied', async () => {
  jest
    .mocked(Notifications.getPermissionsAsync)
    .mockResolvedValueOnce({ granted: false, canAskAgain: false } as any);
  const state = defaultSleepRoutines(8);
  state.windDown.enabled = true;
  expect(await syncWindDownReminders(state, Date.now())).toBe(false);
  expect(Notifications.cancelScheduledNotificationAsync).toHaveBeenCalledTimes(
    14,
  );
  expect(Notifications.scheduleNotificationAsync).not.toHaveBeenCalled();
});
it('respects a date exception in both reminders and removes reminders on disable', async () => {
  const now = new Date('2026-09-07T10:00:00').getTime(),
    state = defaultSleepRoutines(8);
  state.exceptions['2026-09-07'] = { bedtime: 1260, wake: 300 };
  state.windDown.enabled = true;
  await syncCutoffReminder(true, 16, state, now);
  const cutoff = jest.mocked(Notifications.scheduleNotificationAsync).mock
    .calls[0][0];
  expect(cutoff.content?.body).toContain(
    new Date('2026-09-07T21:00:00').toLocaleString([], {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    }),
  );
  await syncWindDownReminders(state, now);
  expect(
    jest.mocked(Notifications.scheduleNotificationAsync).mock.calls[14][0]
      .trigger,
  ).toEqual({ type: 'date', date: new Date('2026-09-07T20:30:00') });
  jest.clearAllMocks();
  state.windDown.enabled = false;
  await syncWindDownReminders(state, now);
  expect(Notifications.scheduleNotificationAsync).not.toHaveBeenCalled();
});
