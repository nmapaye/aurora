import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react-native';
import DataControlsScreen from '~/screens/DataControlsScreen';
import { createBackup } from '~/features/ownership/backup';
import { pickBackupFile } from '~/services/storage/backupFiles';
import { cancelAuroraReminders } from '~/services/platform/reminderCenter';
import { useStore } from '~/state/store';
jest.mock('~/navigation', () => ({ goBack: jest.fn() }));
jest.mock('~/services/storage/backupFiles', () => ({
  pickBackupFile: jest.fn(),
  shareBackupFile: jest.fn(),
}));
jest.mock('~/services/platform/reminderCenter', () => ({
  cancelAuroraReminders: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
beforeEach(() => {
  jest.clearAllMocks();
  useStore.setState({
    doses: [{ id: 'existing', timestamp: 1800000000000, mg: 95 }],
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
});
it('leaves local records intact when the system picker is canceled', async () => {
  jest.mocked(pickBackupFile).mockResolvedValue(null);
  await render(<DataControlsScreen />);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Import Aurora backup' }),
  );
  expect(
    screen.queryByRole('button', { name: 'Replace local Aurora data' }),
  ).toBeNull();
  expect(useStore.getState().doses[0].id).toBe('existing');
  expect(cancelAuroraReminders).not.toHaveBeenCalled();
});
it('shows replacement preview and changes records only after explicit confirmation', async () => {
  const backup = createBackup(
    {
      ...useStore.getState(),
      doses: [{ id: 'restored', timestamp: 1800000000000, mg: 60 }],
    },
    1800000000000,
  );
  jest.mocked(pickBackupFile).mockResolvedValue(backup);
  await render(<DataControlsScreen />);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Import Aurora backup' }),
  );
  expect(
    screen.getByText(/This replaces every local record/),
  ).toBeOnTheScreen();
  expect(useStore.getState().doses[0].id).toBe('existing');
  await fireEvent.press(
    screen.getByRole('button', { name: 'Replace local Aurora data' }),
  );
  expect(cancelAuroraReminders).toHaveBeenCalledTimes(1);
  expect(useStore.getState().doses[0].id).toBe('restored');
});
it('supports canceling deletion and requires a second explicit delete action', async () => {
  await render(<DataControlsScreen />);
  await fireEvent.press(
    screen.getByRole('button', {
      name: 'Select: Caffeine entries, caffeine-free days and draft',
    }),
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Delete selected local data' }),
  );
  expect(useStore.getState().doses).toHaveLength(1);
  await fireEvent.press(screen.getByRole('button', { name: 'Cancel' }));
  expect(useStore.getState().doses).toHaveLength(1);
  await fireEvent.press(
    screen.getByRole('button', { name: 'Delete selected local data' }),
  );
  await fireEvent.press(
    screen.getByRole('button', { name: 'Delete local data' }),
  );
  expect(useStore.getState().doses).toEqual([]);
  expect(screen.getByText(/Selected local data deleted/)).toBeOnTheScreen();
});
