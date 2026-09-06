import * as Notifications from 'expo-notifications';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
import { windDownReminders } from '~/services/platform/notificationContent';
import { syncWindDownReminders } from '~/services/platform/notifications';

jest.mock('expo-notifications', () => ({
  getPermissionsAsync: jest.fn(), requestPermissionsAsync: jest.fn(),
  cancelScheduledNotificationAsync: jest.fn(), scheduleNotificationAsync: jest.fn(),
  SchedulableTriggerInputTypes: { DATE: 'date', DAILY: 'daily' },
}));

const now = new Date(2026, 8, 7, 12).getTime();
const pending = new Map<string, number>();
const cancel = jest.mocked(Notifications.cancelScheduledNotificationAsync);
const schedule = jest.mocked(Notifications.scheduleNotificationAsync);
const permissions = jest.mocked(Notifications.getPermissionsAsync);

beforeEach(() => {
  jest.clearAllMocks();
  pending.clear();
  pending.set('unrelated-reminder', 123);
  permissions.mockResolvedValue({ granted: true, canAskAgain: true } as Awaited<ReturnType<typeof Notifications.getPermissionsAsync>>);
  cancel.mockImplementation(async id => { pending.delete(id); });
  schedule.mockImplementation(async request => {
    pending.set(request.identifier!, (request.trigger as { date: Date }).date.getTime());
    return request.identifier!;
  });
});

it('cancels its reminders without requesting permission again after denial', async () => {
  pending.set('wind-down:0', now + 1000);
  permissions.mockResolvedValue({ granted: false, canAskAgain: false } as Awaited<ReturnType<typeof Notifications.getPermissionsAsync>>);
  const routines = defaultSleepRoutines(8);
  routines.windDown.enabled = true;
  expect(await syncWindDownReminders(routines, now)).toBe(false);
  expect(Notifications.requestPermissionsAsync).not.toHaveBeenCalled();
  expect([...pending.keys()]).toEqual(['unrelated-reminder']);
});

it('leaves the latest schedule after rapid replacements and preserves unrelated reminders', async () => {
  const first = defaultSleepRoutines(8), second = defaultSleepRoutines(8);
  first.windDown = { enabled: true, leadMinutes: 30 };
  second.windDown = { enabled: true, leadMinutes: 60 };
  await Promise.all([syncWindDownReminders(first, now), syncWindDownReminders(second, now)]);
  for (const reminder of windDownReminders(second, now)) expect(pending.get(reminder.id)).toBe(reminder.date);
  expect(pending.size).toBe(windDownReminders(second, now).length + 1);
  expect(pending.get('unrelated-reminder')).toBe(123);
});

it('cleans partial scheduling after a native failure', async () => {
  let count = 0;
  schedule.mockImplementation(async request => {
    if (++count === 3) throw new Error('Native scheduling failed');
    pending.set(request.identifier!, (request.trigger as { date: Date }).date.getTime());
    return request.identifier!;
  });
  const routines = defaultSleepRoutines(8);
  routines.windDown.enabled = true;
  await expect(syncWindDownReminders(routines, now)).rejects.toThrow('Native scheduling failed');
  expect([...pending.keys()]).toEqual(['unrelated-reminder']);
});
