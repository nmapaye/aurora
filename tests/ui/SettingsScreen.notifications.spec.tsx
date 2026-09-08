import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react-native';
import SettingsScreen from '~/screens/SettingsScreen';
import { syncCutoffReminder } from '~/services/platform/notifications';
import { useStore } from '~/state/store';
jest.mock('~/services/platform/notifications', () => ({ syncCutoffReminder: jest.fn() }));
jest.mock('~/navigation', () => ({ goBack: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
const sync = jest.mocked(syncCutoffReminder);
beforeEach(() => { jest.resetAllMocks(); useStore.getState().setPrefs({ notifyCutoff: true }); });
it.each([true, false])('shows a failure and retry while preserving the desired preference %s', async enabled => {
  useStore.getState().setPrefs({ notifyCutoff: enabled });
  sync.mockRejectedValueOnce(new Error('native failure')).mockResolvedValue(enabled);
  await render(<SettingsScreen />);
  expect(await screen.findByText(/Reminder status unknown/)).toBeOnTheScreen();
  expect(useStore.getState().prefs.notifyCutoff).toBe(enabled);
  await fireEvent.press(screen.getByRole('button', { name: 'Retry reminder' }));
  await waitFor(() => expect(screen.getByText(enabled ? 'Reminder scheduled.' : 'Reminder off.')).toBeOnTheScreen());
});
it('explains permission denial without discarding the preference', async () => {
  sync.mockResolvedValue(false);
  await render(<SettingsScreen />);
  expect(await screen.findByText(/Notification permission is off/)).toBeOnTheScreen();
  expect(useStore.getState().prefs.notifyCutoff).toBe(true);
  expect(screen.getByRole('button', { name: 'Retry reminder' })).toBeOnTheScreen();
});

jest.mock('@expo/vector-icons', () => ({ Ionicons: () => null }));
