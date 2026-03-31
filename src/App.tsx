import 'react-native-gesture-handler';
import 'react-native-reanimated';

import React, { useEffect, useMemo } from 'react';
import { ActivityIndicator, StatusBar, Text, View, useColorScheme, LogBox } from 'react-native';
import { NavigationContainer, DefaultTheme, DarkTheme, Theme } from '@react-navigation/native';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';

import { navigationRef } from '~/navigation';
import { useStore } from '~/state/store';
import RootNavigator from '~/navigation/RootNavigator';
import { useAppInit } from '~/hooks/useAppInit';
import type { RootStackParamList } from '~/navigation/types';
import linking from '~/navigation/linking';
import OnboardingScreen from '~/screens/Onboarding/OnboardingScreen';
import * as perf from '~/instrumentation/perf';
import { getAppPalette } from '~/theme/colors';

// Enable react-native-screens if available (perf/memory). Use dynamic require to avoid runtime errors if missing.
try {
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

// Linking config centralized in navigation/linking

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
  const onboardingComplete = useStore((s) => s.onboarding.completed);
  const theme = useMemo<Theme>(() => {
    const palette = getAppPalette(scheme);
    const base = scheme === 'dark' ? DarkTheme : DefaultTheme;
    return {
      ...base,
      colors: {
        ...base.colors,
        background: palette.groupedBackground,
        card: palette.card,
        text: palette.textPrimary,
        border: palette.cardBorder,
        primary: palette.tint,
        notification: palette.destructive,
      },
    };
  }, [scheme]);

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
              onboardingComplete ? (
                <NavigationContainer<RootStackParamList>
                  ref={navigationRef}
                  theme={theme}
                  linking={linking}
                  onReady={() => {
                    try {
                      (perf as any).mark?.('nav:ready');
                    } catch {}
                  }}
                >
                  <RootNavigator />
                </NavigationContainer>
              ) : (
                <OnboardingScreen />
              )
            ) : (
              <BootGate />
            )}
          </RootErrorBoundary>
        </SafeAreaView>
      </SafeAreaProvider>
    </GestureHandlerRootView>
  );
}
