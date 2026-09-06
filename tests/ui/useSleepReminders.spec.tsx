import { act, renderHook, waitFor } from '@testing-library/react-native';
import { AppState, type AppStateStatus } from 'react-native';
import { useStore } from '~/state/store';
import useSleepReminders from '~/hooks/useSleepReminders';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
import {
  syncWindDownReminders,
  syncCutoffReminder,
} from '~/services/platform/notifications';
jest.mock('~/services/platform/notifications', () => ({
  syncWindDownReminders: jest.fn().mockResolvedValue(true),
  syncCutoffReminder: jest.fn().mockResolvedValue(true),
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
it('reflects notification denial by turning the preference off', async () => {
  jest.mocked(syncWindDownReminders).mockResolvedValue(false);
  await renderHook(() => useSleepReminders(true));
  await waitFor(() =>
    expect(useStore.getState().sleepRoutines.windDown.enabled).toBe(false),
  );
});
it('refreshes the dated schedule on foreground after a calendar change', async () => {
  jest.mocked(syncWindDownReminders).mockResolvedValue(true);
  let listener: ((state: AppStateStatus) => void) | undefined;
  jest
    .spyOn(AppState, 'addEventListener')
    .mockImplementation((_event, callback) => {
      listener = callback;
      return { remove: jest.fn() };
    });
  await renderHook(() => useSleepReminders(true));
  await waitFor(() => expect(syncWindDownReminders).toHaveBeenCalledTimes(1));
  jest.setSystemTime(new Date('2026-09-09T08:00:00'));
  await act(() => listener?.('active'));
  expect(syncWindDownReminders).toHaveBeenCalledTimes(2);
  expect(syncCutoffReminder).toHaveBeenCalledTimes(2);
});
it('waits for hydration and walkthrough completion before touching reminders', async () => {
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
  expect(syncWindDownReminders).not.toHaveBeenCalled();
});
it('rechecks permission when returning on the same day', async () => {
  jest.mocked(syncWindDownReminders).mockResolvedValue(true);
  const listeners: Array<(state: AppStateStatus) => void> = [];
  jest
    .spyOn(AppState, 'addEventListener')
    .mockImplementation((_event, callback) => {
      listeners.push(callback);
      return { remove: jest.fn() };
    });
  await renderHook(() => useSleepReminders(true));
  await waitFor(() => expect(syncWindDownReminders).toHaveBeenCalledTimes(1));
  jest.mocked(syncWindDownReminders).mockResolvedValue(false);
  await act(() => listeners.forEach((listener) => listener('active')));
  await waitFor(() =>
    expect(useStore.getState().sleepRoutines.windDown.enabled).toBe(false),
  );
});
