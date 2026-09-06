import { act, renderHook, waitFor } from '@testing-library/react-native';
import { AppState, type AppStateStatus } from 'react-native';
import { useStore } from '~/state/store';
import useSleepReminders from '~/hooks/useSleepReminders';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
import { syncReminderCenter } from '~/services/platform/reminderCenter';
jest.mock('~/services/platform/reminderCenter', () => ({
  syncReminderCenter: jest.fn().mockResolvedValue('granted'),
}));
beforeEach(() => {
  jest.clearAllMocks();
  jest.useFakeTimers();
  jest.setSystemTime(new Date('2026-09-07T12:00:00'));
  useStore.setState({
    sleepRoutines: {
      ...defaultSleepRoutines(8),
      windDown: { enabled: true, leadMinutes: 30 },
    },
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
});
afterEach(() => {
  jest.useRealTimers();
  jest.restoreAllMocks();
});
it('preserves reminder intent when OS permission is denied', async () => {
  jest.mocked(syncReminderCenter).mockResolvedValue('denied');
  await renderHook(() => useSleepReminders(true));
  await waitFor(() =>
    expect(useStore.getState().sleepRoutines.windDown.enabled).toBe(true),
  );
});
it('refreshes the dated schedule on foreground after a calendar change', async () => {
  jest.mocked(syncReminderCenter).mockResolvedValue('granted');
  let listener: ((state: AppStateStatus) => void) | undefined;
  jest
    .spyOn(AppState, 'addEventListener')
    .mockImplementation((_event, callback) => {
      listener = callback;
      return { remove: jest.fn() };
    });
  await renderHook(() => useSleepReminders(true));
  await waitFor(() => expect(syncReminderCenter).toHaveBeenCalledTimes(1));
  jest.setSystemTime(new Date('2026-09-09T08:00:00'));
  await act(() => listener?.('active'));
  expect(syncReminderCenter).toHaveBeenCalledTimes(2);
});
it('waits for hydration then clears scheduling during the walkthrough', async () => {
  useStore.setState({
    onboarding: {
      ...useStore.getState().onboarding,
      appWalkthroughCompleted: false,
    },
  });
  let ready = false;
  const { rerender } = await renderHook(() => useSleepReminders(ready));
  ready = true;
  await rerender(undefined);
  expect(syncReminderCenter).toHaveBeenCalledWith(
    expect.anything(),
    expect.anything(),
    expect.anything(),
    expect.any(Number),
    false,
  );
});
it('rechecks permission when returning on the same day', async () => {
  jest.mocked(syncReminderCenter).mockResolvedValue('granted');
  const listeners: Array<(state: AppStateStatus) => void> = [];
  jest
    .spyOn(AppState, 'addEventListener')
    .mockImplementation((_event, callback) => {
      listeners.push(callback);
      return { remove: jest.fn() };
    });
  await renderHook(() => useSleepReminders(true));
  await waitFor(() => expect(syncReminderCenter).toHaveBeenCalledTimes(1));
  jest.mocked(syncReminderCenter).mockResolvedValue('denied');
  await act(() => listeners.forEach((listener) => listener('active')));
  await waitFor(() =>
    expect(useStore.getState().sleepRoutines.windDown.enabled).toBe(true),
  );
});
