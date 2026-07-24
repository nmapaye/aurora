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
    default: () => <Text>Summary screen</Text>,
  };
});
jest.mock('~/screens/SleepScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: () => <Text>Sleep screen</Text>,
  };
});
jest.mock('~/screens/LogIntakeScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: () => <Text>Log screen</Text>,
  };
});
jest.mock('~/screens/InsightsScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    default: () => <Text>Insights screen</Text>,
  };
});
jest.mock('~/components/AppIcon', () => {
  const { Text } = jest.requireActual('react-native');
  return {
    __esModule: true,
    appIcons: {
      summary: 'summary',
      summarySelected: 'summary-selected',
      sleep: 'sleep',
      sleepSelected: 'sleep-selected',
      log: 'log',
      logSelected: 'log-selected',
      insights: 'insights',
      insightsSelected: 'insights-selected',
      fallback: 'fallback',
    },
    default: ({ name }: { name: string }) => <Text>{name}</Text>,
  };
});
jest.mock('react-native-safe-area-context', () => ({
  ...jest.requireActual('react-native-safe-area-context'),
  useSafeAreaInsets: () => ({
    top: 0,
    right: 0,
    bottom: 0,
    left: 0,
  }),
}));
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

  it('disables every tab button until completion is persisted', async () => {
    await render(
      <NavigationContainer>
        <RootTabs />
      </NavigationContainer>,
    );

    expect(
      screen.getByRole('button', {
        name: 'Summary, tab, 1 of 4',
      }),
    ).toBeDisabled();
    expect(
      screen.getByRole('button', {
        name: 'Sleep, tab, 2 of 4',
      }),
    ).toBeDisabled();
    expect(
      screen.getByRole('button', {
        name: 'Log, tab, 3 of 4',
      }),
    ).toBeDisabled();
    expect(
      screen.getByRole('button', {
        name: 'Insights, tab, 4 of 4',
      }),
    ).toBeDisabled();

    await act(async () => {
      useStore.getState().completeAppWalkthrough();
    });

    expect(
      screen.getByRole('button', {
        name: 'Sleep, tab, 2 of 4',
      }),
    ).toBeEnabled();
  });
});
