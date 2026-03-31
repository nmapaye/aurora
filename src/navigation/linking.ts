import type { LinkingOptions } from '@react-navigation/native';
import type { RootStackParamList } from './types';
import { Linking as RNLinking } from 'react-native';

const linking: LinkingOptions<RootStackParamList> = {
  prefixes: [] as string[],
  config: {
    initialRouteName: 'Tabs',
    screens: {
      Tabs: {
        screens: {
          Home: 'home',
          Log: 'log',
          Sleep: 'sleep',
          Insights: 'insights',
        },
      },
      VigilanceTest: 'vigilance',
      Settings: 'settings',
    },
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
