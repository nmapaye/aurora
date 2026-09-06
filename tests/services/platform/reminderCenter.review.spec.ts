import { notificationPermission, syncReminderCenter } from '~/services/platform/reminderCenter';
import { defaultOwnership } from '~/features/ownership/model';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
const mockPending = new Map<string, any>();
const mockPermission = jest.fn();
const mockRequest = jest.fn();
const mockSchedule = jest.fn();
jest.mock('expo-notifications', () => ({
  SchedulableTriggerInputTypes: { DATE: 'date' },
  getPermissionsAsync: () => mockPermission(),
  requestPermissionsAsync: () => mockRequest(),
  cancelScheduledNotificationAsync: async (id: string) => { mockPending.delete(id); },
  scheduleNotificationAsync: (request: any) => mockSchedule(request),
}));
const now = new Date(2026, 8, 7, 8).getTime();
const prefs = { notifyCutoff: false, cutoffHour: 16 };
beforeEach(() => {
  jest.clearAllMocks(); mockPending.clear();
  mockPending.set('unrelated', { keep: true });
  mockPermission.mockResolvedValue({ status: 'granted', granted: true, canAskAgain: true });
  mockRequest.mockResolvedValue({ status: 'granted', granted: true, canAskAgain: true });
  mockSchedule.mockImplementation(async request => { mockPending.set(request.identifier, request); return request.identifier; });
});
it('honors an explicit permission request with no enabled reminders but never during the walkthrough', async () => {
  mockPermission.mockResolvedValue({ status: 'undetermined', granted: false, canAskAgain: true });
  await syncReminderCenter(defaultOwnership(), defaultSleepRoutines(8), prefs, now, false, true);
  expect(mockRequest).not.toHaveBeenCalled();
  await syncReminderCenter(defaultOwnership(), defaultSleepRoutines(8), prefs, now, true, true);
  expect(mockRequest).toHaveBeenCalledTimes(1);
  expect(mockSchedule).not.toHaveBeenCalled();
});
it('reports denied permission rather than undetermined when the OS says denied', async () => {
  mockPermission.mockResolvedValue({ status: 'denied', granted: false, canAskAgain: true });
  expect(await notificationPermission()).toBe('denied');
});
it('removes a partially created plan after native scheduling fails and retains unrelated reminders', async () => {
  const state = defaultOwnership(); state.reminders.checkIn.enabled = true;
  let calls = 0;
  mockSchedule.mockImplementation(async request => {
    if (++calls === 3) throw new Error('Native scheduling failed');
    mockPending.set(request.identifier, request); return request.identifier;
  });
  await expect(syncReminderCenter(state, defaultSleepRoutines(8), prefs, now, true)).rejects.toThrow('Native scheduling failed');
  expect([...mockPending.keys()]).toEqual(['unrelated']);
});
it('serializes rapid edits and leaves only the latest plan scheduled', async () => {
  const first = defaultOwnership(); first.reminders.checkIn.enabled = true; first.reminders.checkIn.minute = 600;
  const last = defaultOwnership(); last.reminders.checkIn.enabled = true; last.reminders.checkIn.minute = 660;
  await Promise.all([syncReminderCenter(first, defaultSleepRoutines(8), prefs, now, true), syncReminderCenter(last, defaultSleepRoutines(8), prefs, now, true)]);
  const scheduled = [...mockPending.entries()].filter(([id]) => id !== 'unrelated').map(([, request]) => request);
  expect(scheduled).toHaveLength(14);
  expect(scheduled.every(request => request.trigger.date.getHours() === 11)).toBe(true);
});
