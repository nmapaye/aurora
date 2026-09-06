import React from 'react';
import {
  render,
  screen,
  userEvent,
  waitFor,
  within,
} from '@testing-library/react-native';
import { Share } from 'react-native';

import CaffeineHistoryScreen from '~/screens/CaffeineHistoryScreen';
import { goBack } from '~/navigation';
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
    jest.spyOn(Share, 'share').mockResolvedValue({ action: 'sharedAction' });
    useStore.setState({
      doses: [
        {
          id: 'dose:tea',
          timestamp: Date.parse('2026-07-24T08:00:00.000Z'),
          mg: 80,
          source: 'Tea',
          note: 'Morning',
        },
      ],
      vigilanceSessions: [],
    });
  });

  it('wraps the existing history behavior with caffeine data selected', async () => {
    const user = userEvent.setup();
    await render(<CaffeineHistoryScreen />);

    expect(screen.getByText('Caffeine History')).toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Vigilance' }),
    ).not.toBeOnTheScreen();
    expect(screen.getByText('80 mg • Tea')).toBeOnTheScreen();
    await user.type(
      screen.getByPlaceholderText('Search amount, source, or note'),
      'Morning',
    );
    expect(screen.getByText('80 mg • Tea')).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Export' }));
    await waitFor(() =>
      expect(Share.share).toHaveBeenCalledWith({
        message:
          'id,timestamp,datetime,mg,source,note\n' +
          '"dose:tea","1784880000000","2026-07-24T08:00:00.000Z","80","Tea","Morning"',
      }),
    );
    await user.press(screen.getByRole('button', { name: 'Edit' }));
    await user.press(screen.getByRole('button', { name: 'Save' }));
    await user.press(screen.getByRole('button', { name: 'Delete' }));
    expect(useStore.getState().doses).toHaveLength(0);
    expect(
      within(screen.getByTestId('app-screen-overlay')).getByRole('button', {
        name: 'Undo caffeine change',
      }),
    ).toBeOnTheScreen();
  });

  it('provides an accessible Close action for the hidden-header route', async () => {
    const user = userEvent.setup();
    await render(<CaffeineHistoryScreen />);

    await user.press(screen.getByRole('button', { name: 'Close' }));

    expect(goBack).toHaveBeenCalledTimes(1);
  });

  it('shows an inline export error and clears it after a successful retry', async () => {
    jest
      .mocked(Share.share)
      .mockRejectedValueOnce(new Error('Sharing unavailable'));
    const user = userEvent.setup();
    await render(<CaffeineHistoryScreen />);

    await user.press(screen.getByRole('button', { name: 'Export' }));
    expect(
      await screen.findByRole('alert', {
        name: 'Unable to export caffeine history. Sharing unavailable',
      }),
    ).toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: 'Export' }));
    await waitFor(() =>
      expect(
        screen.queryByText(
          'Unable to export caffeine history. Sharing unavailable',
        ),
      ).not.toBeOnTheScreen(),
    );
  });

  afterEach(() => jest.restoreAllMocks());
});

it('combines filters, resets them, and repeats a history entry into an editable draft', async () => {
  const now = Date.parse('2026-07-24T12:00:00.000Z');
  jest.spyOn(Date, 'now').mockReturnValue(now);
  useStore.setState({
    caffeine: { drinks: [], favoriteIds: [], draft: null, zeroDays: [] },
    doses: [
      {
        id: 'tea',
        timestamp: now - 60000,
        mg: 80,
        source: 'Tea',
        note: 'Morning',
      },
      { id: 'coffee', timestamp: now - 10000, mg: 120, source: 'Coffee' },
    ],
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  });
  const user = userEvent.setup();
  await render(<CaffeineHistoryScreen />);
  await user.type(screen.getByLabelText('Filter source'), 'Tea');
  expect(screen.queryByText('120 mg • Coffee')).not.toBeOnTheScreen();
  await user.type(screen.getByLabelText('Minimum caffeine in mg'), '90');
  expect(screen.queryByText('80 mg • Tea')).not.toBeOnTheScreen();
  await user.press(screen.getByRole('button', { name: 'Reset filters' }));
  expect(screen.getByText('80 mg • Tea')).toBeOnTheScreen();
  await user.type(screen.getByLabelText('Filter source'), 'Tea');
  await user.press(screen.getByRole('button', { name: 'Repeat' }));
  expect(useStore.getState().caffeine.draft).toEqual({
    mg: '80',
    source: 'Tea',
    note: 'Morning',
    timestamp: now,
  });
  expect(useStore.getState().doses).toHaveLength(2);
  jest.restoreAllMocks();
});
