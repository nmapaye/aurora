import React, { createRef } from 'react';
import {
  act,
  render,
  screen,
  userEvent,
} from '@testing-library/react-native';
import type { Text as TextInstance } from 'react-native';

import {
  APP_WALKTHROUGH_STEPS,
  useAppWalkthrough,
} from '~/features/appWalkthrough';
import { NOW_TICK_MS } from '~/hooks/useNow';
import { navigate } from '~/navigation';
import DashboardScreen from '~/screens/DashboardScreen';
import { useStore } from '~/state/store';

jest.mock('~/components/CaffeineTodayGraph', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: function MockCaffeineGraphScreen() { return <Text>Caffeine graph</Text>; },
  };
});
jest.mock('~/navigation', () => ({
  navigate: jest.fn(),
}));
jest.mock('~/hooks/useAdaptiveLayout', () => ({
  __esModule: true,
  default: () => ({
    width: 390,
    height: 844,
    isPad: false,
    isWideLayout: false,
    isIpadWindowed: false,
    contentMaxWidth: 600,
    topChromeBuffer: 0,
    horizontalPadding: 16,
    leftColumnWidth: 358,
    rightColumnWidth: 358,
  }),
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 20, left: 0 }),
}));
jest.mock('~/features/appWalkthrough/useAppWalkthrough', () => ({
  __esModule: true,
  default: jest.fn(),
}));

const hour = 60 * 60 * 1000;

describe('DashboardScreen Estimated Alertness hero', () => {
  beforeEach(() => {
    jest.mocked(useAppWalkthrough).mockReturnValue({
      active: false,
      locked: true,
      reduceMotion: true,
      step: APP_WALKTHROUGH_STEPS[0],
      coachVisible: false,
      coachHeadingRef: createRef<TextInstance>(),
      isRevealed: () => true,
      measureAnchor: jest.fn(),
      onCoachLayout: jest.fn(),
      onViewportLayout: jest.fn(),
      onScroll: jest.fn(),
      onSkip: jest.fn(),
      onPrimary: jest.fn(),
    });
    jest.mocked(navigate).mockClear();
    useStore.setState({
      doses: [],
      sleeps: [],
      vigilanceSessions: [],
      demoMode: false,
    });
  });

  it('shows an honest placeholder instead of a score without recent sleep', async () => {
    const user = userEvent.setup();
    await render(<DashboardScreen />);

    expect(screen.getByText('Estimated Alertness')).toBeOnTheScreen();
    expect(screen.getByText('No estimate')).toBeOnTheScreen();
    expect(screen.getByText('No recent sleep')).toBeOnTheScreen();
    expect(
      screen.getByLabelText(/^Estimated alertness unavailable\./),
    ).toBeOnTheScreen();
    expect(screen.queryByText('Estimate')).not.toBeOnTheScreen();
    expect(screen.getByText('Caffeine graph')).toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: 'Open Sleep' }));
    expect(navigate).toHaveBeenCalledWith('Sleep');
  });

  it('labels the model output as an estimate when recent sleep exists', async () => {
    const now = Date.now();
    useStore.setState({
      sleeps: [
        {
          id: 'manual:sleep:1',
          start: now - 10 * hour,
          end: now - 3 * hour,
          type: 'sleep',
        },
      ],
    });
    await render(<DashboardScreen />);

    expect(screen.getByText('Estimate')).toBeOnTheScreen();
    expect(
      screen.getByLabelText(
        /^Estimated alertness \d+ out of 100\..*not a measurement\.$/,
      ),
    ).toBeOnTheScreen();
    expect(
      screen.getByText(/^From \d+h \d+m of sleep$/),
    ).toBeOnTheScreen();
    expect(
      screen.getByText('Plus active caffeine and time of day. Not a measurement.'),
    ).toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Open Sleep' }),
    ).not.toBeOnTheScreen();
  });

  it('keeps empty signals quiet and offers sample data only before anything is recorded', async () => {
    const user = userEvent.setup();
    await render(<DashboardScreen />);

    expect(
      screen.getByRole('button', {
        name: 'Caffeine Logged, No data, Nothing logged yet today.',
      }),
    ).toBeOnTheScreen();
    expect(screen.getByText('Add Sleep')).toBeOnTheScreen();
    expect(screen.getByText('Take Reaction Test')).toBeOnTheScreen();
    expect(screen.queryByText('No Data')).not.toBeOnTheScreen();

    await user.press(screen.getByRole('button', { name: 'Load Sample Data' }));
    expect(useStore.getState().demoMode).toBe(true);
  });

  it('sends the Caffeine Logged signal to Log whether or not today is empty', async () => {
    // Local 9:00 AM keeps both doses on their intended calendar days.
    const now = new Date(2026, 8, 26, 9, 0, 0).getTime();
    jest.useFakeTimers({ now });
    try {
      const user = userEvent.setup({ advanceTimers: jest.advanceTimersByTime });
      // Older history, but nothing today.
      useStore.setState({
        doses: [{ id: 'yesterday', timestamp: now - 24 * hour, mg: 95 }],
      });
      const { rerender } = await render(<DashboardScreen />);

      const empty = screen.getByRole('button', {
        name: 'Caffeine Logged, No data, Nothing logged yet today.',
      });
      expect(empty).toHaveProp('accessibilityHint', 'Log Caffeine.');
      // The signal is Summary's only logging action.
      expect(
        screen.getAllByText('Log Caffeine', { includeHiddenElements: true }),
      ).toHaveLength(1);
      await user.press(empty);
      expect(navigate).toHaveBeenLastCalledWith('Log');

      await act(async () => {
        useStore.setState({
          doses: [
            { id: 'yesterday', timestamp: now - 24 * hour, mg: 95 },
            { id: 'today', timestamp: now - 60_000, mg: 60 },
          ],
        });
      });
      await rerender(<DashboardScreen />);

      const logged = screen.getByRole('button', { name: /^Caffeine Logged, 60 mg/ });
      expect(logged).toHaveProp('accessibilityHint', 'Open Log.');
      expect(
        screen.queryByText('Log Caffeine', { includeHiddenElements: true }),
      ).not.toBeOnTheScreen();
      await user.press(logged);
      expect(navigate).toHaveBeenLastCalledWith('Log');
    } finally {
      jest.useRealTimers();
    }
  });

  it('labels sample data with a compact status line and on each sample signal', async () => {
    // Local 9:00 AM keeps the dose on today's calendar day in any time zone.
    const now = new Date(2026, 8, 26, 9, 0, 0).getTime();
    jest.useFakeTimers({ now });
    try {
      useStore.setState({
        demoMode: true,
        doses: [{ id: 'demo:dose:0', timestamp: now - 60_000, mg: 95 }],
        sleeps: [
          {
            id: 'demo:sleep:0',
            start: now - 10 * hour,
            end: now - 3 * hour,
            type: 'sleep',
          },
        ],
      });
      await render(<DashboardScreen />);

      expect(
        screen.getByText('Showing sample data: example records, not yours.'),
      ).toBeOnTheScreen();
      // No hero-sized alert or generic action above the real signals.
      expect(screen.queryByText('You’re viewing sample data.')).not.toBeOnTheScreen();
      expect(
        screen.queryByRole('button', { name: 'More Details' }),
      ).not.toBeOnTheScreen();
      // The badge stays on the caffeine and sleep signals.
      expect(screen.getAllByText('Sample Data')).toHaveLength(2);
      expect(screen.getByText('95 mg')).toBeOnTheScreen();
      expect(
        screen.queryByRole('button', { name: 'Load Sample Data' }),
      ).not.toBeOnTheScreen();

      await userEvent
        .setup({ advanceTimers: jest.advanceTimersByTime })
        .press(screen.getByRole('button', { name: 'Clear Sample Data' }));
      expect(useStore.getState().demoMode).toBe(false);
    } finally {
      jest.useRealTimers();
    }
  });

  it('refreshes the estimate as the clock moves without new data', async () => {
    const start = new Date(2026, 8, 26, 9, 0, 0).getTime();
    jest.useFakeTimers({ now: start });
    try {
      useStore.setState({
        sleeps: [
          {
            id: 'manual:sleep:1',
            start: start - 10 * hour,
            end: start - 3 * hour,
            type: 'sleep',
          },
        ],
      });
      await render(<DashboardScreen />);
      expect(screen.getByText('Estimate')).toBeOnTheScreen();

      // A day later that sleep has aged out of the model's 24-hour window.
      jest.setSystemTime(start + 22 * hour);
      await act(async () => {
        jest.advanceTimersByTime(NOW_TICK_MS);
      });

      expect(screen.getByText('No estimate')).toBeOnTheScreen();
      expect(screen.getByText('No recent sleep')).toBeOnTheScreen();
    } finally {
      jest.useRealTimers();
    }
  });
});
