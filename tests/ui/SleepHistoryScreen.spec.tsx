import React from 'react';
import { Alert } from 'react-native';
import { render, screen, userEvent } from '@testing-library/react-native';

import SleepHistoryScreen from '~/screens/SleepHistoryScreen';
import { useStore } from '~/state/store';

jest.mock('~/navigation', () => ({ goBack: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

describe('SleepHistoryScreen', () => {
  beforeEach(() => {
    useStore.setState({
      sleeps: [
        {
          id: 'manual:sleep:1:abc',
          start: 1_700_000_000_000,
          end: 1_700_028_800_000,
          type: 'sleep',
          note: 'Quiet night',
        },
        {
          id: 'healthkit:sleep:2:3',
          start: 1_699_900_000_000,
          end: 1_699_928_800_000,
          type: 'sleep',
        },
      ],
    });
  });

  it('labels sources and exposes edit/delete only on manual records', async () => {
    await render(<SleepHistoryScreen />);

    expect(screen.getByText('Manual')).toBeOnTheScreen();
    expect(screen.getByText('Health')).toBeOnTheScreen();
    expect(screen.getByText('Quiet night')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Edit manual sleep' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Delete manual sleep' })).toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Edit Health sleep' })).not.toBeOnTheScreen();
  });

  it('edits a manual record after validation', async () => {
    const user = userEvent.setup();
    await render(<SleepHistoryScreen />);
    await user.press(screen.getByRole('button', { name: 'Edit manual sleep' }));
    expect(screen.getByRole('button', { name: 'Start time' })).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'End time' })).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'End time' }));
    expect(screen.getByTestId('history-end-picker')).toBeOnTheScreen();
    await user.clear(screen.getByLabelText('Sleep note'));
    await user.type(screen.getByLabelText('Sleep note'), 'Edited note');
    await user.press(screen.getByRole('button', { name: 'Save changes' }));

    expect(useStore.getState().sleeps[0]?.note).toBe('Edited note');
  });

  it('confirms before deleting a manual record', async () => {
    const alert = jest.spyOn(Alert, 'alert').mockImplementation((_title, _body, buttons) => {
      buttons?.find((button) => button.style === 'destructive')?.onPress?.();
    });
    const user = userEvent.setup();
    await render(<SleepHistoryScreen />);
    await user.press(screen.getByRole('button', { name: 'Delete manual sleep' }));

    expect(alert).toHaveBeenCalled();
    expect(useStore.getState().sleeps.map((item) => item.id)).toEqual(['healthkit:sleep:2:3']);
  });
});
