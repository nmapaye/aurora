import type { LinkingOptions } from '@react-navigation/native';
import type { RootTabParamList } from './types';
import { Linking as RNLinking } from 'react-native';

const linking: LinkingOptions<RootTabParamList> = {
  prefixes: [] as string[],
  config: {
    initialRouteName: 'Home',
    screens: {
      Home: 'home',
      Log: 'log',
      Sleep: 'sleep',
      Insights: 'insights',
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
