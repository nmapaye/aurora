import React from 'react';
import {
  act,
  render,
  screen,
  userEvent,
} from '@testing-library/react-native';
import { Alert, Share } from 'react-native';

import CaffeineHistoryScreen from '~/screens/CaffeineHistoryScreen';
import { useStore } from '~/state/store';

jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
jest.mock('~/navigation', () => ({ goBack: jest.fn(), navigate: jest.fn() }));

describe('CaffeineHistoryScreen', () => {
  beforeEach(() => {
    jest
      .spyOn(Date, 'now')
      .mockReturnValue(Date.parse('2026-07-24T12:00:00.000Z'));
    jest
      .spyOn(Share, 'share')
      .mockResolvedValue({ action: 'sharedAction' });
    useStore.setState({
      doses: [{ id: 'dose:tea', timestamp: Date.parse('2026-07-24T08:00:00.000Z'), mg: 80, source: 'Tea', note: 'Morning' }],
      vigilanceSessions: [],
    });
  });

  it('wraps the existing history behavior with caffeine data selected', async () => {
    const user = userEvent.setup();
    await render(<CaffeineHistoryScreen />);

    expect(screen.getByText('Caffeine History')).toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Vigilance' })).not.toBeOnTheScreen();
    expect(screen.getByText('80 mg • Tea')).toBeOnTheScreen();
    await user.type(screen.getByPlaceholderText('Search amount, source, or note'), 'Morning');
    expect(screen.getByText('80 mg • Tea')).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Edit' }));
    await user.press(screen.getByRole('button', { name: 'Save' }));
    const alert = jest.spyOn(Alert, 'alert').mockImplementation(() => {});
    await user.press(screen.getByRole('button', { name: 'Delete' }));
    // Nothing is removed until the confirmation's destructive action runs.
    expect(useStore.getState().doses).toHaveLength(1);
    const buttons = alert.mock.calls[0][2] as { text: string; onPress?: () => void }[];
    await act(() => buttons.find((button) => button.text === 'Delete')?.onPress?.());
    expect(useStore.getState().doses).toHaveLength(0);
  });

  it('leaves navigation to the native back button', async () => {
    await render(<CaffeineHistoryScreen />);

    expect(screen.queryByRole('button', { name: 'Close' })).not.toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Open settings' })).not.toBeOnTheScreen();
  });

  it('leaves export to Settings → Data', async () => {
    await render(<CaffeineHistoryScreen />);

    expect(screen.queryByRole('button', { name: /Export/ })).not.toBeOnTheScreen();
    expect(Share.share).not.toHaveBeenCalled();
  });

  afterEach(() => jest.restoreAllMocks());
});
