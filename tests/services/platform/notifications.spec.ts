import * as Notifications from 'expo-notifications';
import { syncCutoffReminder } from '~/services/platform/notifications';

jest.mock('expo-notifications', () => ({
  getPermissionsAsync: jest.fn(), requestPermissionsAsync: jest.fn(),
  cancelScheduledNotificationAsync: jest.fn(), scheduleNotificationAsync: jest.fn(),
  SchedulableTriggerInputTypes: { DAILY: 'daily' },
}));
const native = jest.mocked(Notifications);
beforeEach(() => {
  jest.resetAllMocks();
  native.cancelScheduledNotificationAsync.mockResolvedValue();
  native.scheduleNotificationAsync.mockResolvedValue('cutoff-reminder');
  native.getPermissionsAsync.mockResolvedValue({ granted: true } as never);
});
it('does not schedule an older On intent after Off arrives during permission lookup', async () => {
  let resolve!: (value: never) => void;
  native.getPermissionsAsync.mockImplementationOnce(() => new Promise(r => { resolve = r; }));
  const on = syncCutoffReminder(true, 16);
  await Promise.resolve(); await Promise.resolve(); await Promise.resolve();
  const off = syncCutoffReminder(false, 16);
  resolve({ granted: true } as never);
  await Promise.all([on, off]);
  expect(native.scheduleNotificationAsync).not.toHaveBeenCalled();
  expect(native.cancelScheduledNotificationAsync).toHaveBeenLastCalledWith('cutoff-reminder');
});
it.each(['getPermissionsAsync', 'scheduleNotificationAsync', 'cancelScheduledNotificationAsync'] as const)('reports %s failure and allows a later retry', async method => {
  native[method].mockRejectedValueOnce(new Error('native failure'));
  await expect(syncCutoffReminder(true, 16)).rejects.toThrow('native failure');
  await expect(syncCutoffReminder(true, 17)).resolves.toBe(true);
});
it('returns false for denied permission without scheduling', async () => {
  native.getPermissionsAsync.mockResolvedValue({ granted: false, canAskAgain: false } as never);
  await expect(syncCutoffReminder(true, 16)).resolves.toBe(false);
  expect(native.scheduleNotificationAsync).not.toHaveBeenCalled();
});
