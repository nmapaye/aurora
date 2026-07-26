import {
  getStateFromPath as getNavigationStateFromPath,
  type LinkingOptions,
} from '@react-navigation/native';
import type { RootStackParamList } from './types';
import { Linking as RNLinking } from 'react-native';
import * as ExpoLinking from 'expo-linking';
import {
  getAppWalkthroughRoute,
  isAppWalkthroughPending,
} from '~/features/appWalkthrough/model';
import { useStore } from '~/state/store';

const config: NonNullable<LinkingOptions<RootStackParamList>['config']> = {
  initialRouteName: 'Tabs',
  screens: {
    Tabs: {
      screens: {
        Summary: 'summary',
        Log: 'log',
        Sleep: 'sleep',
        Insights: 'insights',
      },
    },
    VigilanceTest: 'vigilance',
    Settings: 'settings',
    SleepHistory: 'sleep/history',
    CaffeineHistory: 'caffeine/history',
  },
};

const walkthroughRoutePaths = {
  Summary: 'summary',
  Sleep: 'sleep',
  Log: 'log',
  Insights: 'insights',
} as const;

const linking: LinkingOptions<RootStackParamList> = {
  prefixes: ['aurora://', ExpoLinking.createURL('/')],
  config,
  getStateFromPath(path) {
    const onboarding = useStore.getState().onboarding;
    const resolvedPath = isAppWalkthroughPending(onboarding)
      ? walkthroughRoutePaths[getAppWalkthroughRoute(onboarding.appWalkthroughStep)]
      : path;
    return getNavigationStateFromPath<RootStackParamList>(
      resolvedPath,
      config,
    );
  },
  async getInitialURL() {
    const url = await RNLinking.getInitialURL();
    return url ?? undefined;
  },
  subscribe(listener: (url: string) => void) {
    const sub = RNLinking.addEventListener('url', ({ url }) => listener(url));
    return () => sub.remove();
  },
};

export default linking;
