import 'react-native-gesture-handler';
import 'react-native-reanimated';

import React, { useEffect, useMemo } from 'react';
import { ActivityIndicator, StatusBar, Text, View, useColorScheme, LogBox } from 'react-native';
import { NavigationContainer, DefaultTheme, DarkTheme, Theme, LinkingOptions } from '@react-navigation/native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { Linking as RNLinking } from 'react-native';

import { navigationRef } from '~/navigation';
import RootTabs from '~/navigation/RootTabs';
import { useAppInit } from '~/hooks/useAppInit';
import type { RootTabParamList } from '~/navigation/types';
import * as perf from '~/instrumentation/perf';

// Enable react-native-screens if available (perf/memory). Use dynamic require to avoid runtime errors if missing.
try {
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  require('react-native-screens').enableScreens?.(true);
} catch {}

// Optional: quiet common noisy dev warnings
LogBox.ignoreLogs([
  'Non-serializable values were found in the navigation state',
]);

// Error boundary to prevent hard black screens from render-time throws
class RootErrorBoundary extends React.Component<{ children: React.ReactNode }, { error?: Error }> {
  state: { error?: Error } = {};
  static getDerivedStateFromError(error: Error) {
    return { error };
  }
  componentDidCatch(error: Error, info: any) {
    try {
      (perf as any).mark?.('app:error');
    } catch {}
    console.error('[root]', error, info);
  }
  render() {
    if (this.state.error) {
      return (
        <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center', padding: 16 }}>
          <Text style={{ fontSize: 18, marginBottom: 8 }}>Something went wrong.</Text>
          <Text selectable numberOfLines={5} style={{ opacity: 0.7, textAlign: 'center' }}>
            {this.state.error.message}
          </Text>
        </View>
      );
    }
    return this.props.children;
  }
}

// Navigation themes
const LightNavTheme: Theme = {
  ...DefaultTheme,
  colors: { ...DefaultTheme.colors, background: '#FFFFFF', card: '#FFFFFF', text: '#0A0A0A', border: '#E6E6E6' },
};
const DarkNavTheme: Theme = {
  ...DarkTheme,
  colors: { ...DarkTheme.colors, background: '#000000', card: '#0B0B0B', text: '#FFFFFF', border: '#1F1F1F' },
};

// Deep linking config for tabs using React Native Linking (no expo-linking dependency)
const linking: LinkingOptions<RootTabParamList> = {
  prefixes: [] as string[],
  config: {
    initialRouteName: 'Home' as keyof RootTabParamList,
    screens: {
      Home: 'home',
      Log: 'log',
      Sleep: 'sleep',
      Insights: 'insights',
      Settings: 'settings',
    } as const,
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

function BootGate() {
  return (
    <View style={{ flex: 1, alignItems: 'center', justifyContent: 'center' }}>
      <ActivityIndicator />
      <Text style={{ marginTop: 8 }}>Loading…</Text>
    </View>
  );
}

export default function App() {
  const ready = useAppInit();
  const scheme = useColorScheme();
  const theme = useMemo<Theme>(() => (scheme === 'dark' ? DarkNavTheme : LightNavTheme), [scheme]);

  useEffect(() => {
    try {
      (perf as any).mark?.('app:start');
    } catch {}
  }, []);

  useEffect(() => {
    if (ready) {
      try {
        (perf as any).mark?.('app:ready');
        (perf as any).measure?.('app:boot', 'app:start', 'app:ready');
        (perf as any).enableFPSMonitor?.(false);
      } catch {}
    }
  }, [ready]);

  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <SafeAreaProvider>
        <SafeAreaView style={{ flex: 1, backgroundColor: theme.colors.background }} edges={['top']}>
          <StatusBar barStyle={scheme === 'dark' ? 'light-content' : 'dark-content'} />
          <RootErrorBoundary>
            {ready ? (
              <NavigationContainer<RootTabParamList>
                ref={navigationRef}
                theme={theme}
                linking={linking}
                onReady={() => {
                  try {
                    (perf as any).mark?.('nav:ready');
                  } catch {}
                }}
              >
                <RootTabs />
              </NavigationContainer>
            ) : (
              <BootGate />
            )}
          </RootErrorBoundary>
        </SafeAreaView>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}