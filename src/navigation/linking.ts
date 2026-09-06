import {
  getStateFromPath as getNavigationStateFromPath,
  type LinkingOptions,
} from '@react-navigation/native';
import type { RootStackParamList } from './types';
import { Linking as RNLinking } from 'react-native';
import Constants from 'expo-constants';
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

const CUSTOM_SCHEME_PREFIX = 'aurora://';

export function getLinkingPrefixes(linkingUri: string | null | undefined) {
  const developmentPrefix = linkingUri?.trim();
  return developmentPrefix && developmentPrefix !== CUSTOM_SCHEME_PREFIX
    ? [CUSTOM_SCHEME_PREFIX, developmentPrefix]
    : [CUSTOM_SCHEME_PREFIX];
}

const linking: LinkingOptions<RootStackParamList> = {
  prefixes: getLinkingPrefixes(Constants.linkingUri),
  config,
  getStateFromPath(path) {
    const onboarding = useStore.getState().onboarding;
    const resolvedPath = isAppWalkthroughPending(onboarding)
      ? walkthroughRoutePaths[
          getAppWalkthroughRoute(onboarding.appWalkthroughStep)
        ]
      : path;
    return getNavigationStateFromPath<RootStackParamList>(resolvedPath, config);
  },
  async getInitialURL() {
    const url = await RNLinking.getInitialURL();
    return url?.startsWith('aurora://native/') ? undefined : (url ?? undefined);
  },
  subscribe(listener: (url: string) => void) {
    const sub = RNLinking.addEventListener('url', ({ url }) => {
      if (!url.startsWith('aurora://native/')) listener(url);
    });
    return () => sub.remove();
  },
};

export default linking;
