import React, { createRef } from 'react';
import {
  fireEvent,
  render,
  screen,
  userEvent,
} from '@testing-library/react-native';
import type {
  Text as TextInstance,
} from 'react-native';
import { StyleSheet } from 'react-native';
import type { TestInstance } from 'test-renderer';

import {
  APP_WALKTHROUGH_STEPS,
  useAppWalkthrough,
} from '~/features/appWalkthrough';
import { navigate } from '~/navigation';
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
  '~/features/appWalkthrough/useAppWalkthrough',
  () => ({
    __esModule: true,
    default: jest.fn(),
  }),
);

const mockUseAppWalkthrough = jest.mocked(
  useAppWalkthrough,
);

function findRevealAncestor(node: TestInstance) {
  let ancestor = node.parent;
  while (ancestor) {
    if (
      ancestor.props.accessibilityElementsHidden === false &&
      ancestor.props.importantForAccessibility === 'auto'
    ) {
      return ancestor;
    }
    ancestor = ancestor.parent;
  }
  throw new Error('Expected a real WalkthroughReveal ancestor');
}

function findRoleAncestor(node: TestInstance, role: string) {
  let ancestor: TestInstance | null = node;
  while (ancestor) {
    if (ancestor.props.accessibilityRole === role) {
      return ancestor;
    }
    ancestor = ancestor.parent;
  }
  throw new Error(`Expected a ${role} ancestor`);
}

describe('DashboardScreen summary walkthrough composition', () => {
  const onCoachLayout = jest.fn();

  function setWalkthrough(
    overrides: Partial<ReturnType<typeof useAppWalkthrough>> = {},
  ) {
    mockUseAppWalkthrough.mockReturnValue({
      active: true,
      locked: false,
      reduceMotion: true,
      step: APP_WALKTHROUGH_STEPS[0],
      coachVisible: true,
      coachHeadingRef: createRef<TextInstance>(),
      isRevealed: () => true,
      measureAnchor: jest.fn(),
      onCoachLayout,
      onViewportLayout: jest.fn(),
      onScroll: jest.fn(),
      onSkip: jest.fn(),
      onPrimary: jest.fn(),
      ...overrides,
    });
  }

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
    onCoachLayout.mockClear();
    jest.mocked(navigate).mockClear();
    setWalkthrough();
  });

  it('composes the active coach around the real empty Summary', async () => {
    await render(<DashboardScreen />);

    expect(
      screen.getByRole('header', {
        name: 'Your day at a glance',
      }),
    ).toBeOnTheScreen();
    expect(
      screen.getByText('Pinned', {
        includeHiddenElements: true,
      }),
    ).toBeOnTheScreen();
    expect(
      screen.container.queryAll(
        (node) => node.props.onLayout === onCoachLayout,
      ),
    ).toHaveLength(1);
  });

  it('locks the underlying real Summary while the coach stays active', async () => {
    await render(<DashboardScreen />);

    const content = screen.getByTestId('app-screen-content', {
      includeHiddenElements: true,
    });
    expect(content).toHaveProp('pointerEvents', 'none');
    expect(content).toHaveProp(
      'accessibilityElementsHidden',
      true,
    );
    expect(content).toHaveProp(
      'importantForAccessibility',
      'no-hide-descendants',
    );

    expect(
      screen.getByRole('button', { name: 'Skip' }),
    ).toBeOnTheScreen();
    expect(
      screen.getByRole('button', { name: 'Next' }),
    ).toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Open settings' }),
    ).not.toBeOnTheScreen();
    expect(
      screen.queryByRole('button', { name: 'Espresso 60mg' }),
    ).not.toBeOnTheScreen();
    expect(screen.getAllByRole('button')).toHaveLength(2);
    expect(
      findRoleAncestor(
        screen.getByText('Caffeine', {
          includeHiddenElements: true,
        }),
        'button',
      ),
    ).toBeOnTheScreen();
  });

  it('preserves the real Recent Activity section gap inside its reveal', async () => {
    await render(<DashboardScreen />);

    const recentReveal = findRevealAncestor(
      screen.getByText('Recent Activity', {
        includeHiddenElements: true,
      }),
    );
    expect(StyleSheet.flatten(recentReveal.props.style)).toMatchObject({
      gap: 16,
    });
  });

  it('restores Settings, metric, and quick-add interactions after completion', async () => {
    const user = userEvent.setup();
    const { rerender } = await render(<DashboardScreen />);

    setWalkthrough({
      active: false,
      locked: true,
      coachVisible: false,
    });
    await rerender(<DashboardScreen />);

    const settings = screen.getByRole('button', {
      name: 'Open settings',
    });
    const caffeine = findRoleAncestor(
      screen.getByText('Caffeine'),
      'button',
    );
    const espresso = screen.getByRole('button', {
      name: 'Espresso 60mg',
    });

    await user.press(settings);
    await user.press(caffeine);
    await user.press(espresso);

    expect(navigate).toHaveBeenNthCalledWith(1, 'Settings');
    expect(navigate).toHaveBeenNthCalledWith(2, 'Insights');
    expect(useStore.getState().doses).toHaveLength(1);
    expect(useStore.getState().doses[0]).toMatchObject({
      mg: 60,
      source: 'Espresso',
    });
  });

  it('reserves the current coach height before reveal without a late layout jump', async () => {
    setWalkthrough({ coachVisible: false });
    const { rerender } = await render(<DashboardScreen />);

    const overlay = screen.getByTestId('app-screen-overlay', {
      includeHiddenElements: true,
    });
    const measuredCoachRoots = screen.container.queryAll(
      (node) => node.props.onLayout === onCoachLayout,
    );
    expect(measuredCoachRoots).toHaveLength(1);
    expect(measuredCoachRoots[0]?.parent).toHaveProp(
      'accessibilityElementsHidden',
      true,
    );
    expect(
      screen.queryByRole('header', {
        name: 'Your day at a glance',
      }),
    ).not.toBeOnTheScreen();

    await fireEvent(overlay, 'layout', {
      nativeEvent: {
        layout: { x: 0, y: 0, width: 358, height: 180 },
      },
    });
    expect(
      StyleSheet.flatten(
        screen.getByTestId('app-screen-scroll').props
          .contentContainerStyle,
      ),
    ).toMatchObject({ paddingBottom: 244 });

    setWalkthrough({ coachVisible: true });
    await rerender(<DashboardScreen />);

    expect(
      screen.getByRole('header', {
        name: 'Your day at a glance',
      }),
    ).toBeOnTheScreen();
    expect(
      StyleSheet.flatten(
        screen.getByTestId('app-screen-scroll').props
          .contentContainerStyle,
      ),
    ).toMatchObject({ paddingBottom: 244 });
  });
});
