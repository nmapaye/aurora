import React from 'react';
import { render, screen, userEvent } from '@testing-library/react-native';

import CaffeineHistoryScreen from '~/screens/CaffeineHistoryScreen';
import { useStore } from '~/state/store';

jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
jest.mock('~/navigation', () => ({ navigate: jest.fn() }));

describe('CaffeineHistoryScreen', () => {
  beforeEach(() => {
    useStore.setState({
      doses: [{ id: 'dose:tea', timestamp: Date.parse('2026-07-24T08:00:00.000Z'), mg: 80, source: 'Tea', note: 'Morning' }],
      vigilanceSessions: [],
    });
  });

  it('wraps the existing history behavior with caffeine data selected', async () => {
    const user = userEvent.setup();
    await render(<CaffeineHistoryScreen />);

    expect(screen.getByText('Caffeine History')).toBeOnTheScreen();
    expect(screen.getByText('80 mg • Tea')).toBeOnTheScreen();
    await user.type(screen.getByPlaceholderText('Search amount, source, or note'), 'Morning');
    expect(screen.getByText('80 mg • Tea')).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Edit' }));
    await user.press(screen.getByRole('button', { name: 'Save' }));
    await user.press(screen.getByRole('button', { name: 'Delete' }));
    expect(useStore.getState().doses).toHaveLength(0);
  });
});
