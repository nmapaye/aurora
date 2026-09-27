import React from 'react';
import { render, screen, fireEvent, waitFor } from '@testing-library/react-native';
import { Alert } from 'react-native';
import SettingsScreen from '~/screens/SettingsScreen';
import { formatClockHour } from '~/utils/format';
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

describe('about and data controls', () => {
  it('shows the app version and no internal release notes', async () => {
    sync.mockResolvedValue(true);
    await render(<SettingsScreen />);
    expect(screen.getByText('Version')).toBeOnTheScreen();
    expect(screen.queryByText('Current release focus')).toBeNull();
  });

  it('shows the cutoff reminder time in the device locale', async () => {
    sync.mockResolvedValue(true);
    useStore.getState().setPrefs({ cutoffHour: 16 });
    await render(<SettingsScreen />);
    expect(screen.queryByText(/16:00/)).toBeNull();
    expect(screen.getAllByText(new RegExp(formatClockHour(16))).length).toBeGreaterThan(0);
  });

  it('confirms before deleting all data', async () => {
    sync.mockResolvedValue(true);
    const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
    const deleteAllData = jest.spyOn(useStore.getState(), 'deleteAllData');
    useStore.setState({ doses: [{ id: 'd1', timestamp: 1, mg: 60 }] });
    await render(<SettingsScreen />);
    await fireEvent.press(screen.getByRole('button', { name: /Delete All Data/ }));
    expect(alert).toHaveBeenCalled();
    expect(useStore.getState().doses).toHaveLength(1);
    const buttons = alert.mock.calls[0][2] as { text: string; onPress?: () => void }[];
    buttons.find((b) => b.text === 'Delete')?.onPress?.();
    expect(useStore.getState().doses).toEqual([]);
    deleteAllData.mockRestore();
  });
});

it('toggles the cutoff reminder with a switch', async () => {
  sync.mockResolvedValue(true);
  useStore.getState().setPrefs({ notifyCutoff: false });
  await render(<SettingsScreen />);
  const toggle = screen.getByRole('switch', { name: 'Cutoff reminder' });
  expect(toggle).not.toBeChecked();
  await fireEvent.press(toggle);
  expect(useStore.getState().prefs.notifyCutoff).toBe(true);
});
