import React, { createRef } from 'react';
import {
  render,
  screen,
} from '@testing-library/react-native';
import type {
  Text as TextInstance,
} from 'react-native';

import {
  SUMMARY_WALKTHROUGH_STEPS,
  useSummaryWalkthrough,
} from '~/features/summaryWalkthrough';
import DashboardScreen from '~/screens/DashboardScreen';
import { useStore } from '~/state/store';

jest.mock('~/hooks/useAlertnessSeries', () => ({
  useAlertnessSeries: () => ({
    nowScore: 0,
    mgActiveNow: 0,
  }),
}));
jest.mock('~/hooks/useCaffeineCutoff', () => ({
  __esModule: true,
  default: () => ({
    nextCutoff: 1_800_000_000_000,
  }),
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
  useSafeAreaInsets: () => ({
    top: 0,
    right: 0,
    bottom: 20,
    left: 0,
  }),
}));
jest.mock(
  '~/features/summaryWalkthrough/useSummaryWalkthrough',
  () => ({
    __esModule: true,
    default: jest.fn(),
  }),
);

const mockUseSummaryWalkthrough = jest.mocked(
  useSummaryWalkthrough,
);

describe('DashboardScreen summary walkthrough composition', () => {
  const onCoachLayout = jest.fn();

  beforeEach(() => {
    useStore.setState({
      doses: [],
      sleeps: [],
      vigilanceSessions: [],
      demoMode: false,
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'unsupported',
        summaryWalkthroughCompleted: false,
      },
    });
    onCoachLayout.mockClear();
    mockUseSummaryWalkthrough.mockReturnValue({
      active: true,
      locked: false,
      reduceMotion: true,
      step: SUMMARY_WALKTHROUGH_STEPS[0],
      coachVisible: true,
      coachHeadingRef: createRef<TextInstance>(),
      isRevealed: () => true,
      measureAnchor: jest.fn(),
      onCoachLayout,
      onViewportLayout: jest.fn(),
      onScroll: jest.fn(),
      onSkip: jest.fn(),
      onPrimary: jest.fn(),
    });
  });

  it('composes the active coach around the real empty Summary', async () => {
    await render(<DashboardScreen />);

    expect(
      screen.getByRole('header', {
        name: 'Your day at a glance',
      }),
    ).toBeOnTheScreen();
    expect(screen.getByText('Pinned')).toBeOnTheScreen();
    expect(
      screen.container.queryAll(
        (node) => node.props.onLayout === onCoachLayout,
      ),
    ).toHaveLength(1);
  });

  it('locks the underlying real Summary while the coach stays active', async () => {
    await render(<DashboardScreen />);

    expect(screen.getByTestId('app-screen-content')).toHaveProp(
      'pointerEvents',
      'none',
    );
  });
});
