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

jest.mock('~/hooks/useAlertnessSeries', () => ({
  useAlertnessSeries: () => ({ mgActiveNow: 0 }),
}));
jest.mock('~/hooks/useCaffeineCutoff', () => ({
  __esModule: true,
  default: () => ({ nextCutoff: 1_800_000_000_000 }),
}));
jest.mock('~/hooks/useSleepGuidance', () => ({
  __esModule: true,
  default: () => ({
    bedtime: 1_800_010_000_000,
    wake: 1_800_040_000_000,
  }),
}));
jest.mock('~/components/CaffeineTodayGraph', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: () => <Text>Caffeine graph</Text>,
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
    expect(
      screen.getByText('Alertness needs recent sleep'),
    ).toBeOnTheScreen();
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
    expect(
      screen.getByText(/^Estimated alertness \d+$/),
    ).toBeOnTheScreen();
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
