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
  APP_WALKTHROUGH_STEPS,
  useAppWalkthrough,
} from '~/features/appWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
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
  '~/features/appWalkthrough/useAppWalkthrough',
  () => ({
    __esModule: true,
    default: jest.fn(),
  }),
);
jest.mock(
  '~/features/appWalkthrough/WalkthroughReveal',
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

const FIRST_RUN_NOTE =
  'Nothing recorded yet. You can explore with a labeled sample week.';

const mockUseAdaptiveLayout = jest.mocked(useAdaptiveLayout);
const mockUseAppWalkthrough = jest.mocked(
  useAppWalkthrough,
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
      mockUseAppWalkthrough.mockReturnValue({
        active: true,
        locked: false,
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
    });

    it('stages the Today hero, then the optional first-run note, after the header', async () => {
      await render(<DashboardScreen />);

      expect(staggerForText('Summary')).toBe(0);
      expect(staggerForText('Estimated Alertness')).toBe(1);
      expect(staggerForText(FIRST_RUN_NOTE)).toBe(2);
    });

    it('reads the Today hero first, ahead of the note and pinned signals', async () => {
      await render(<DashboardScreen />);

      expect(
        screen
          .getAllByText(
            /^(Estimated Alertness|Nothing recorded yet\..*|Pinned|Log Caffeine)$/,
            { includeHiddenElements: true },
          )
          .map((node) => node.props.children),
      ).toEqual([
        'Estimated Alertness',
        FIRST_RUN_NOTE,
        'Pinned',
        // The empty Caffeine Logged signal's action is the only one.
        'Log Caffeine',
      ]);
    });

    it('stages exactly three pinned signals and no separate log action', async () => {
      await render(<DashboardScreen />);

      expect(staggerForText('Pinned')).toBe(0);
      expect(
        ['Caffeine Logged', 'Sleep', 'Reaction Test'].map(staggerForText),
      ).toEqual([1, 2, 3]);
      expect(
        screen.queryByRole('button', {
          name: 'Log Caffeine',
          includeHiddenElements: true,
        }),
      ).not.toBeOnTheScreen();
      for (const removed of [
        'Active Caffeine',
        'Caffeine Cutoff',
        'Recent Activity',
        'Custom Entry',
        'Espresso 60mg',
        'Edit',
      ]) {
        expect(
          screen.queryByText(removed, { includeHiddenElements: true }),
        ).not.toBeOnTheScreen();
      }

      // The Estimated Alertness hero pairs with the caffeine curve in both
      // layouts.
      expect(
        screen.getByText('Caffeine graph', {
          includeHiddenElements: true,
        }),
      ).toBeOnTheScreen();
    });
  },
);
