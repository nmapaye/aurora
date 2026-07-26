import React from 'react';
import { NavigationContainer } from '@react-navigation/native';
import { act, render, screen } from '@testing-library/react-native';
import { Linking as RNLinking } from 'react-native';

import linking from '~/navigation/linking';
import RootNavigator from '~/navigation/RootNavigator';
import { useStore } from '~/state/store';

jest.mock('expo-constants', () => ({
  __esModule: true,
  default: { linkingUri: 'exp://127.0.0.1:8081/--/' },
}));
jest.mock('~/screens/DashboardScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return { __esModule: true, default: () => <Text>Summary screen</Text> };
});
jest.mock('~/screens/SleepScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return { __esModule: true, default: () => <Text>Sleep screen</Text> };
});
jest.mock('~/screens/LogIntakeScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return { __esModule: true, default: () => <Text>Log screen</Text> };
});
jest.mock('~/screens/InsightsScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return { __esModule: true, default: () => <Text>Insights screen</Text> };
});
jest.mock('~/screens/VigilanceTestScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return { __esModule: true, default: () => <Text>Vigilance screen</Text> };
});
jest.mock('~/screens/SettingsScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return { __esModule: true, default: () => <Text>Settings screen</Text> };
});
jest.mock('~/screens/SleepHistoryScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return { __esModule: true, default: () => <Text>Sleep History screen</Text> };
});
jest.mock('~/screens/CaffeineHistoryScreen', () => {
  const { Text } = jest.requireActual('react-native');
  return { __esModule: true, default: () => <Text>Caffeine History screen</Text> };
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
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
}));
jest.mock('~/hooks/useAppScheme', () => ({
  __esModule: true,
  default: () => 'light',
}));

describe('navigation full-URL integration', () => {
  beforeEach(() => {
    useStore.setState({
      onboarding: {
        completed: true,
        source: 'manual',
        permissionStatus: 'unsupported',
        appWalkthroughCompleted: true,
        appWalkthroughStep: 9,
      },
    });
  });

  afterEach(() => jest.restoreAllMocks());

  it('extracts, parses, and dispatches a cold-start custom-scheme URL', async () => {
    jest.spyOn(RNLinking, 'getInitialURL').mockResolvedValue('aurora://sleep/history');

    await render(
      <NavigationContainer linking={linking}>
        <RootNavigator />
      </NavigationContainer>,
    );

    expect(await screen.findByText('Sleep History screen')).toBeOnTheScreen();
  });

  it('extracts, parses, and dispatches a warm custom-scheme URL', async () => {
    let receiveURL: ((event: { url: string }) => void) | undefined;
    jest.spyOn(RNLinking, 'getInitialURL').mockResolvedValue(null);
    jest.spyOn(RNLinking, 'addEventListener').mockImplementation(
      (_event, listener) => {
        receiveURL = listener;
        return { remove: jest.fn() } as unknown as ReturnType<
          typeof RNLinking.addEventListener
        >;
      },
    );

    await render(
      <NavigationContainer linking={linking}>
        <RootNavigator />
      </NavigationContainer>,
    );
    expect(await screen.findByText('Summary screen')).toBeOnTheScreen();

    await act(() => receiveURL?.({ url: 'aurora://caffeine/history' }));

    expect(await screen.findByText('Caffeine History screen')).toBeOnTheScreen();
  });
});
