import React from 'react';
import {
  NavigationContainer,
} from '@react-navigation/native';
import {
  act,
  render,
  screen,
} from '@testing-library/react-native';

import RootTabs from '~/navigation/RootTabs';
import { useStore } from '~/state/store';

jest.mock('~/screens/DashboardScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: function MockSummaryScreen() { return <Text>Summary screen</Text>; },
  };
});
jest.mock('~/screens/SleepScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: function MockSleepScreen() { return <Text>Sleep screen</Text>; },
  };
});
jest.mock('~/screens/LogIntakeScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: function MockLogScreen() { return <Text>Log screen</Text>; },
  };
});
jest.mock('~/screens/InsightsScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: function MockInsightsScreen() { return <Text>Insights screen</Text>; },
  };
});
jest.mock('~/hooks/useAppScheme', () => ({
  __esModule: true,
  default: () => 'light',
}));

describe('RootTabs summary walkthrough gating', () => {
  beforeEach(() => {
    useStore.setState({
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'unsupported',
        appWalkthroughCompleted: false,
        appWalkthroughStep: 0,
      },
    });
  });

  type HostNode = { type: string; props: Record<string, unknown>; children?: (HostNode | string)[] | null };
  // The native tab items are host components; read their props from the tree.
  const tabScreens = () => {
    const found: HostNode[] = [];
    const walk = (node: HostNode | string | null | undefined) => {
      if (!node || typeof node === 'string') return;
      if (node.type === 'RNSTabsScreenIOS') found.push(node);
      node.children?.forEach(walk);
    };
    const tree = screen.toJSON() as HostNode | HostNode[] | null;
    (Array.isArray(tree) ? tree : [tree]).forEach(walk);
    return found;
  };

  it('blocks native tab selection until completion is persisted', async () => {
    await render(
      <NavigationContainer>
        <RootTabs />
      </NavigationContainer>,
    );

    const locked = tabScreens();
    expect(locked.map((tab) => tab.props.title)).toEqual(['Summary', 'Sleep', 'Log', 'Insights']);
    expect(locked.every((tab) => tab.props.preventNativeSelection === true)).toBe(true);

    await act(async () => {
      useStore.getState().completeAppWalkthrough();
    });

    expect(tabScreens().every((tab) => tab.props.preventNativeSelection === false)).toBe(true);
  });

  it('uses SF Symbols, filled when selected', async () => {
    await render(
      <NavigationContainer>
        <RootTabs />
      </NavigationContainer>,
    );

    const sleep = tabScreens().find((tab) => tab.props.title === 'Sleep');
    expect(sleep?.props).toMatchObject({
      iconType: 'sfSymbol',
      iconResourceName: 'moon',
      selectedIconResourceName: 'moon.fill',
    });
  });

  it.each([
    [4, 'Sleep screen'],
    [6, 'Log screen'],
    [8, 'Insights screen'],
  ] as const)('selects the owning tab when relaunching at step %i', async (step, screenName) => {
    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        appWalkthroughStep: step,
      },
    });

    await render(
      <NavigationContainer>
        <RootTabs />
      </NavigationContainer>,
    );

    expect(screen.getByText(screenName)).toBeOnTheScreen();
  });
});
