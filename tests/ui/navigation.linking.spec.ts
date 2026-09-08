import { Linking as RNLinking } from 'react-native';

import linking, { getLinkingPrefixes } from '~/navigation/linking';
import { useStore } from '~/state/store';

jest.mock('expo-constants', () => ({
  __esModule: true,
  default: { linkingUri: 'exp://127.0.0.1:8081/--/' },
}));

function leafRouteName(state: ReturnType<NonNullable<typeof linking.getStateFromPath>>) {
  let current = state;
  let name: string | undefined;
  while (current?.routes.length) {
    const route = current.routes[current.index ?? current.routes.length - 1];
    name = route?.name;
    current = route?.state;
  }
  return name;
}

describe('navigation deep linking', () => {
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

  it('registers the custom app scheme and an Expo development-client prefix', () => {
    expect(linking.prefixes).toContain('aurora://');
    expect(linking.prefixes?.some((prefix) => prefix.startsWith('exp://'))).toBe(true);
  });

  it('falls back to only the custom scheme when no Expo development URI exists', () => {
    expect(getLinkingPrefixes(undefined)).toEqual(['aurora://']);
    expect(getLinkingPrefixes('')).toEqual(['aurora://']);
  });

  it.each(['sleep/history?bad=%E0%A4%A', 'sleep/history#details'])('ignores unsupported suffixes in %s', (path) => {
    expect(leafRouteName(linking.getStateFromPath?.(path, linking.config))).toBe('SleepHistory');
  });

  it('handles a cold-start link to the existing Sleep History path', async () => {
    jest.spyOn(RNLinking, 'getInitialURL').mockResolvedValue('aurora://sleep/history');

    await expect(linking.getInitialURL?.()).resolves.toBe('aurora://sleep/history');
    expect(leafRouteName(linking.getStateFromPath?.('sleep/history', linking.config))).toBe(
      'SleepHistory',
    );
  });

  it('handles a warm link to the new Caffeine History path', () => {
    let receiveURL: ((event: { url: string }) => void) | undefined;
    const remove = jest.fn();
    jest.spyOn(RNLinking, 'addEventListener').mockImplementation((_event, listener) => {
      receiveURL = listener;
      return { remove } as unknown as ReturnType<typeof RNLinking.addEventListener>;
    });
    const listener = jest.fn();

    const unsubscribe = linking.subscribe?.(listener);
    receiveURL?.({ url: 'aurora://caffeine/history' });

    expect(listener).toHaveBeenCalledWith('aurora://caffeine/history');
    expect(leafRouteName(linking.getStateFromPath?.('caffeine/history', linking.config))).toBe(
      'CaffeineHistory',
    );
    unsubscribe?.();
    expect(remove).toHaveBeenCalledTimes(1);
  });

  it('redirects every non-owner link to the persisted walkthrough tab', () => {
    useStore.setState({
      onboarding: {
        ...useStore.getState().onboarding,
        appWalkthroughCompleted: false,
        appWalkthroughStep: 6,
      },
    });

    const state = linking.getStateFromPath?.('sleep/history', linking.config);

    expect(leafRouteName(state)).toBe('Log');
    expect(state?.routes.map((route) => route.name)).toEqual(['Tabs']);
  });
});
