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
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import InsightsScreen from '~/screens/InsightsScreen';
import { useStore } from '~/state/store';

jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('~/hooks/useAdaptiveLayout', () => ({ __esModule: true, default: jest.fn() }));
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
const now = new Date(2026, 6, 24, 12, 0, 0, 0).getTime();

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

describe('InsightsScreen walkthrough wiring', () => {
  beforeEach(() => {
    measureAnchor.mockClear();
    jest.spyOn(Date, 'now').mockReturnValue(now);
    jest.mocked(useAdaptiveLayout).mockReturnValue({
      width: 390, height: 844, isPad: false, isWideLayout: false,
      isIpadWindowed: false, contentMaxWidth: 600, topChromeBuffer: 0,
      horizontalPadding: 16, leftColumnWidth: 358, rightColumnWidth: 358,
    });
    useStore.setState({
      doses: [{ id: 'dose:a', timestamp: new Date(2026, 6, 23, 9).getTime(), mg: 95, source: 'Drip' }],
      vigilanceSessions: [],
      demoMode: false,
    });
  });

  afterEach(() => jest.restoreAllMocks());

  it('reveals the range and inspectable chart at step 9 but holds the Reaction Test and Details for step 10', async () => {
    atStep(8);
    await render(<InsightsScreen />);

    expect(revealedFor(screen.getByText('Caffeine Intake', { includeHiddenElements: true }))).toBe(true);
    expect(revealedFor(screen.getByTestId('insights-bars-plot', { includeHiddenElements: true }))).toBe(true);
    expect(revealedFor(screen.getByTestId('insights-supporting-column', { includeHiddenElements: true }))).toBe(false);
    expect(revealedFor(screen.getByTestId('insights-details', { includeHiddenElements: true }))).toBe(false);
  });

  it('anchors step 10 on the Reaction Test signal and reveals it with Details', async () => {
    atStep(9);
    await render(<InsightsScreen />);

    expect(APP_WALKTHROUGH_STEPS[9]).toMatchObject({ progress: '10 of 10', anchor: 'insights-reaction', primaryAction: 'Finish' });
    expect(revealedFor(screen.getByText('Reaction Test', { includeHiddenElements: true }))).toBe(true);
    expect(revealedFor(screen.getByTestId('insights-details', { includeHiddenElements: true }))).toBe(true);

    await fireEvent(screen.getByTestId('insights-supporting-column', { includeHiddenElements: true }), 'layout', {
      nativeEvent: { layout: { x: 0, y: 500, width: 358, height: 120 } },
    });
    expect(measureAnchor).toHaveBeenCalledWith('insights-reaction', expect.anything());
  });
});
