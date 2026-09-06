import React from 'react';
import { AccessibilityInfo, Alert } from 'react-native';
import {
  render,
  screen,
  userEvent,
  waitFor,
} from '@testing-library/react-native';

import SleepHistoryScreen from '~/screens/SleepHistoryScreen';
import { useStore } from '~/state/store';

jest.mock('~/navigation', () => ({ goBack: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));

describe('SleepHistoryScreen', () => {
  beforeEach(() => {
    jest
      .spyOn(AccessibilityInfo, 'isReduceMotionEnabled')
      .mockResolvedValue(false);
    jest.spyOn(AccessibilityInfo, 'addEventListener').mockReturnValue({
      remove: jest.fn(),
    } as unknown as ReturnType<typeof AccessibilityInfo.addEventListener>);
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

  it('searches sleep notes and saves a separate Health journal', async () => {
    const user = userEvent.setup();
    await render(<SleepHistoryScreen />);
    await user.type(screen.getByLabelText('Search sleep notes'), 'Quiet');
    expect(screen.queryByText('Health')).not.toBeOnTheScreen();
    await user.clear(screen.getByLabelText('Search sleep notes'));
    await user.press(
      screen.getAllByRole('button', { name: 'Add sleep journal' })[1],
    );
    await user.type(screen.getByLabelText('Journal note'), 'Calm morning');
    await user.press(screen.getByRole('button', { name: 'Save journal' }));
    expect(
      useStore.getState().sleepRoutines.annotations['healthkit:sleep:2:3'].note,
    ).toBe('Calm morning');
    expect(useStore.getState().sleeps[1].note).toBeUndefined();
  });

  it('labels sources and exposes edit/delete only on manual records', async () => {
    await render(<SleepHistoryScreen />);

    expect(screen.getByText('Manual')).toBeOnTheScreen();
    expect(screen.getByText('Health')).toBeOnTheScreen();
    expect(screen.getByText('Quiet night')).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Edit manual sleep' }),
    ).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Delete manual sleep' }),
    ).toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Edit Health sleep' }),
    ).not.toBeOnTheScreen();
  });

  it('labels demo sleep as sample data and keeps it read-only', async () => {
    useStore.setState({
      sleeps: [
        {
          id: 'demo:sleep:sample',
          start: 1_700_000_000_000,
          end: 1_700_028_800_000,
          type: 'sleep',
        },
      ],
    });
    await render(<SleepHistoryScreen />);

    expect(screen.getByText('Sample Data')).toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Edit manual sleep' }),
    ).not.toBeOnTheScreen();
  });

  it('edits a manual record after validation', async () => {
    const user = userEvent.setup();
    await render(<SleepHistoryScreen />);
    await user.press(screen.getByRole('button', { name: 'Edit manual sleep' }));
    expect(
      screen.getByRole('button', { name: 'Start time' }),
    ).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'End time' })).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Start time' }).props
        .accessibilityValue?.text,
    ).toContain('Nov');
    await user.press(screen.getByRole('button', { name: 'End time' }));
    expect(screen.getByTestId('history-end-picker')).toBeOnTheScreen();
    await user.clear(screen.getByLabelText('Sleep note'));
    await user.type(screen.getByLabelText('Sleep note'), 'Edited note');
    await user.press(screen.getByRole('button', { name: 'Save changes' }));

    expect(useStore.getState().sleeps[0]?.note).toBe('Edited note');
  });

  it('does not retain an Edit Sleep picker after cancel or save', async () => {
    const user = userEvent.setup();
    await render(<SleepHistoryScreen />);
    await user.press(screen.getByRole('button', { name: 'Edit manual sleep' }));
    await user.press(screen.getByRole('button', { name: 'End time' }));
    expect(screen.getByTestId('history-end-picker')).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Cancel' }));
    await user.press(screen.getByRole('button', { name: 'Edit manual sleep' }));
    expect(screen.queryByTestId('history-end-picker')).not.toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'End time' }));
    await user.press(screen.getByRole('button', { name: 'Save changes' }));
    await user.press(screen.getByRole('button', { name: 'Edit manual sleep' }));
    expect(screen.queryByTestId('history-end-picker')).not.toBeOnTheScreen();
  });

  it('suppresses Edit Sleep sheet animation when system Reduce Motion is enabled', async () => {
    jest
      .mocked(AccessibilityInfo.isReduceMotionEnabled)
      .mockResolvedValue(true);
    const user = userEvent.setup();
    await render(<SleepHistoryScreen />);
    await waitFor(() =>
      expect(AccessibilityInfo.isReduceMotionEnabled).toHaveBeenCalled(),
    );

    await user.press(screen.getByRole('button', { name: 'Edit manual sleep' }));

    expect(screen.getByTestId('health-form-sheet-modal')).toHaveProp(
      'animationType',
      'none',
    );
  });

  it('confirms before deleting a manual record', async () => {
    const alert = jest
      .spyOn(Alert, 'alert')
      .mockImplementation((_title, _body, buttons) => {
        buttons?.find((button) => button.style === 'destructive')?.onPress?.();
      });
    const user = userEvent.setup();
    await render(<SleepHistoryScreen />);
    await user.press(
      screen.getByRole('button', { name: 'Delete manual sleep' }),
    );

    expect(alert).toHaveBeenCalled();
    expect(useStore.getState().sleeps.map((item) => item.id)).toEqual([
      'healthkit:sleep:2:3',
    ]);
  });

  afterEach(() => jest.restoreAllMocks());
});
it('shows imported interval boundaries and identifies an overlap partner', async () => {
  const start = new Date(2026, 7, 1, 22).getTime(),
    end = new Date(2026, 7, 2, 6).getTime();
  useStore.setState({
    sleeps: [
      { id: 'healthkit:sleep:interval', start, end, type: 'sleep' },
      {
        id: 'manual:sleep:overlap',
        start: start + 3600000,
        end: end - 3600000,
        type: 'sleep',
      },
    ],
  });
  await render(<SleepHistoryScreen />);
  expect(
    screen.getByText(/Aug 1.*10:00.*to Aug 2.*6:00.*8h 0m/),
  ).toBeOnTheScreen();
  expect(
    screen.getByText(
      /Overlaps another session: Health.*Aug 1.*10:00.*to Aug 2.*6:00/,
    ),
  ).toBeOnTheScreen();
  expect(
    screen.queryByRole('button', { name: 'Edit Health sleep' }),
  ).not.toBeOnTheScreen();
});
