import React, { createRef } from 'react';
import type { ReactNode } from 'react';
import {
  render,
  screen,
} from '@testing-library/react-native';
import type {
  Text as TextInstance,
} from 'react-native';
import type { TestInstance } from 'test-renderer';

import {
  SUMMARY_WALKTHROUGH_STEPS,
  useSummaryWalkthrough,
} from '~/features/summaryWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
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
  default: jest.fn(),
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
jest.mock(
  '~/features/summaryWalkthrough/WalkthroughReveal',
  () => {
    const { View } = jest.requireActual('react-native');
    return {
      __esModule: true,
      default: ({
        children,
        staggerIndex = 0,
      }: {
        children: ReactNode;
        staggerIndex?: number;
      }) => (
        <View
          {...({
            testID: 'walkthrough-reveal-probe',
            walkthroughStaggerIndex: staggerIndex,
          } as Record<string, unknown>)}
        >
          {children}
        </View>
      ),
    };
  },
);

const mockUseAdaptiveLayout = jest.mocked(useAdaptiveLayout);
const mockUseSummaryWalkthrough = jest.mocked(
  useSummaryWalkthrough,
);

function layoutFor(isWideLayout: boolean) {
  return {
    width: isWideLayout ? 1180 : 390,
    height: isWideLayout ? 820 : 844,
    isPad: isWideLayout,
    isWideLayout,
    isIpadWindowed: false,
    contentMaxWidth: isWideLayout ? 1220 : 600,
    topChromeBuffer: 0,
    horizontalPadding: isWideLayout ? 20 : 16,
    leftColumnWidth: isWideLayout ? 600 : 358,
    rightColumnWidth: isWideLayout ? 536 : 358,
  };
}

function findRevealProbe(node: TestInstance) {
  let ancestor = node.parent;
  while (ancestor) {
    if (ancestor.props.testID === 'walkthrough-reveal-probe') {
      return ancestor;
    }
    ancestor = ancestor.parent;
  }
  throw new Error('Expected a WalkthroughReveal probe ancestor');
}

function staggerForText(text: string) {
  return findRevealProbe(
    screen.getByText(text, {
      includeHiddenElements: true,
    }),
  ).props.walkthroughStaggerIndex;
}

describe.each([
  ['compact', false],
  ['wide', true],
] as const)(
  'DashboardScreen walkthrough wiring in %s layout',
  (_layoutName, isWideLayout) => {
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
          appWalkthroughCompleted: false,
          appWalkthroughStep: 0,
        },
      });
      mockUseAdaptiveLayout.mockReturnValue(
        layoutFor(isWideLayout),
      );
      mockUseSummaryWalkthrough.mockReturnValue({
        active: true,
        locked: false,
        reduceMotion: true,
        step: SUMMARY_WALKTHROUGH_STEPS[0],
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
    });

    it('stages the optional alert after the header', async () => {
      await render(<DashboardScreen />);

      expect(staggerForText('Summary')).toBe(0);
      expect(staggerForText('No data yet.')).toBe(1);
    });

    it('stages Recent Activity after the complete logging cascade', async () => {
      await render(<DashboardScreen />);

      expect(staggerForText('Log')).toBe(0);
      expect(
        [
          'Espresso 60mg',
          'Drip 95mg',
          'Matcha 70mg',
          'Energy 160mg',
          'Custom Entry',
          'Recent Activity',
        ].map(staggerForText),
      ).toEqual([2, 3, 4, 5, 6, 7]);

      const firstQuickAddProbe = findRevealProbe(
        screen.getByText('Espresso 60mg', {
          includeHiddenElements: true,
        }),
      );
      expect(
        findRevealProbe(firstQuickAddProbe).props
          .walkthroughStaggerIndex,
      ).toBe(1);

      if (isWideLayout) {
        expect(
          screen.getByText('Caffeine graph', {
            includeHiddenElements: true,
          }),
        ).toBeOnTheScreen();
      } else {
        expect(
          screen.queryByText('Caffeine graph', {
            includeHiddenElements: true,
          }),
        ).not.toBeOnTheScreen();
      }
    });
  },
);
