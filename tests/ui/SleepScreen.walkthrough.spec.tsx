import React, { createRef } from 'react';
import type { ReactNode } from 'react';
import { fireEvent, render, screen } from '@testing-library/react-native';
import type { Text as TextInstance } from 'react-native';
import type { TestInstance } from 'test-renderer';

import {
  APP_WALKTHROUGH_STEPS,
  useAppWalkthrough,
} from '~/features/appWalkthrough';
import { getRevealedGroups } from '~/features/appWalkthrough/model';
import SleepScreen from '~/screens/SleepScreen';
import { useStore } from '~/state/store';

jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('~/services/platform/health/appleHealth', () => ({
  __esModule: true,
  default: {
    isAvailable: jest.fn().mockResolvedValue(true),
    requestAuthorization: jest.fn(),
    getSleepSamples: jest.fn(),
  },
  makeHealthSleepSessionId: ({ start, end }: { start: number; end: number }) =>
    `healthkit:sleep:${start}:${end}`,
}));
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 20, left: 0 }),
}));
jest.mock('~/features/appWalkthrough/useAppWalkthrough', () => ({
  __esModule: true,
  default: jest.fn(),
}));
jest.mock('~/features/appWalkthrough/WalkthroughReveal', () => {
  const { View } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: ({ children, revealed }: { children: ReactNode; revealed: boolean }) => (
      <View
        {...({
          testID: 'walkthrough-reveal-probe',
          walkthroughRevealed: revealed,
        } as Record<string, unknown>)}
      >
        {children}
      </View>
    ),
  };
});

const mockUseAppWalkthrough = jest.mocked(useAppWalkthrough);
const measureAnchor = jest.fn();

function atStep(stepIndex: number) {
  const revealed = getRevealedGroups(stepIndex);
  mockUseAppWalkthrough.mockReturnValue({
    active: true,
    locked: false,
    reduceMotion: true,
    step: APP_WALKTHROUGH_STEPS[stepIndex],
    coachVisible: false,
    coachHeadingRef: createRef<TextInstance>(),
    isRevealed: (group) => revealed.includes(group),
    measureAnchor,
    onCoachLayout: jest.fn(),
    onViewportLayout: jest.fn(),
    onScroll: jest.fn(),
    onSkip: jest.fn(),
    onPrimary: jest.fn(),
  });
}

function revealedFor(node: TestInstance) {
  let ancestor = node.parent;
  while (ancestor) {
    if (ancestor.props.testID === 'walkthrough-reveal-probe') {
      return ancestor.props.walkthroughRevealed;
    }
    ancestor = ancestor.parent;
  }
  throw new Error('Expected a WalkthroughReveal probe ancestor');
}

describe('SleepScreen walkthrough wiring', () => {
  beforeEach(() => {
    measureAnchor.mockClear();
    useStore.setState({
      doses: [],
      sleeps: [],
      demoMode: false,
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'idle',
        appWalkthroughCompleted: false,
        appWalkthroughStep: 4,
      },
      healthSync: { importedCount: 0, importStatus: 'idle' },
    });
  });

  it('reveals the chart and signals at step 5 but holds Sleep Data for step 6', async () => {
    atStep(4);
    await render(<SleepScreen />);

    expect(revealedFor(screen.getByText('Time Asleep', { includeHiddenElements: true }))).toBe(true);
    expect(revealedFor(screen.getByText('Most Recent Sleep', { includeHiddenElements: true }))).toBe(true);
    expect(revealedFor(screen.getByText('Sleep Data', { includeHiddenElements: true }))).toBe(false);
  });

  it('anchors step 6 on the Sleep Data entry and reveals it', async () => {
    atStep(5);
    await render(<SleepScreen />);

    expect(APP_WALKTHROUGH_STEPS[5]).toMatchObject({ progress: '6 of 10', anchor: 'sleep-data' });
    expect(revealedFor(screen.getByText('Sleep Data', { includeHiddenElements: true }))).toBe(true);

    await fireEvent(screen.getByTestId('sleep-data-anchor', { includeHiddenElements: true }), 'layout', {
      nativeEvent: { layout: { x: 0, y: 600, width: 358, height: 60 } },
    });
    expect(measureAnchor).toHaveBeenCalledWith('sleep-data', expect.anything());
  });
});
