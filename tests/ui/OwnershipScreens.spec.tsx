import React from 'react';
import {
  render,
  screen,
  fireEvent,
  waitFor,
  act,
} from '@testing-library/react-native';
import { AppState, type AppStateStatus } from 'react-native';
import SummarySettingsScreen from '~/screens/SummarySettingsScreen';
import ReminderCenterScreen from '~/screens/ReminderCenterScreen';
import { defaultOwnership } from '~/features/ownership/model';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
import { useStore } from '~/state/store';
import { notificationPermission } from '~/services/platform/reminderCenter';
jest.mock('~/navigation', () => ({ goBack: jest.fn(), navigate: jest.fn() }));
jest.mock('~/services/platform/reminderCenter', () => ({
  notificationPermission: jest.fn().mockResolvedValue('undetermined'),
  syncReminderCenter: jest.fn().mockResolvedValue('granted'),
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
beforeEach(() => {
  jest.clearAllMocks();
  useStore.setState({
    ownership: defaultOwnership(),
    sleepRoutines: defaultSleepRoutines(8),
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
});
afterEach(() => jest.restoreAllMocks());
test('Summary hide/reorder persists immediately and restore defaults recovers every card', async () => {
  await render(<SummarySettingsScreen />);
  await fireEvent.press(screen.getByRole('button', { name: 'Hide Caffeine' }));
  await fireEvent.press(screen.getByRole('button', { name: 'Move Sleep up' }));
  expect(useStore.getState().ownership.summary.hidden).toEqual(['caffeine']);
  expect(useStore.getState().ownership.summary.order[1]).toBe('sleep');
  await fireEvent.press(
    screen.getByRole('button', { name: 'Restore default cards' }),
  );
  expect(useStore.getState().ownership).toEqual(defaultOwnership());
});
test('reminder controls expose disabled state in walkthrough', async () => {
  useStore.setState({
    onboarding: {
      ...useStore.getState().onboarding,
      appWalkthroughCompleted: false,
    },
  });
  await render(<ReminderCenterScreen />);
  expect(
    screen.getByRole('button', { name: 'Enable Check-in reminder' }),
  ).toBeDisabled();
  expect(
    screen.getByRole('button', { name: 'Increase Check-in time' }),
  ).toBeDisabled();
});
test('reminder center reads actual permission again on same-day foreground', async () => {
  const listeners: Array<(state: AppStateStatus) => void> = [];
  jest
    .spyOn(AppState, 'addEventListener')
    .mockImplementation((_event, callback) => {
      listeners.push(callback);
      return { remove: jest.fn() };
    });
  jest.mocked(notificationPermission).mockResolvedValue('undetermined');
  await render(<ReminderCenterScreen />);
  await waitFor(() =>
    expect(
      screen.getByText(/Notification permission: undetermined/),
    ).toBeTruthy(),
  );
  jest.mocked(notificationPermission).mockResolvedValue('denied');
  await act(() => listeners.forEach((x) => x('active')));
  await waitFor(() =>
    expect(screen.getByText(/Notification permission: denied/)).toBeTruthy(),
  );
});
