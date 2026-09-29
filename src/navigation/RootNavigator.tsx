import React from 'react';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import RootTabs from './RootTabs';
import type { RootStackParamList } from './types';
import VigilanceTestScreen from '~/screens/VigilanceTestScreen';
import SettingsScreen from '~/screens/SettingsScreen';
import SleepHistoryScreen from '~/screens/SleepHistoryScreen';
import CaffeineHistoryScreen from '~/screens/CaffeineHistoryScreen';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function RootNavigator() {
  const palette = getAppPalette(useAppScheme());
  // History pages get the native bar: back button labelled with the previous
  // screen, swipe back, no title (the large title is in content).
  const historyOptions = {
    headerShown: true,
    title: '',
    headerShadowVisible: false,
    headerStyle: { backgroundColor: palette.groupedBackground },
    headerTintColor: palette.tint,
    presentation: 'card' as const,
    animation: 'slide_from_right' as const,
  };
  return (
    <Stack.Navigator screenOptions={{ headerShown: false }}>
      <Stack.Screen name="Tabs" component={RootTabs} />
      <Stack.Screen
        name="VigilanceTest"
        component={VigilanceTestScreen}
        options={{ presentation: 'card', animation: 'slide_from_right' }}
      />
      <Stack.Screen
        name="Settings"
        component={SettingsScreen}
        options={{ presentation: 'modal', animation: 'slide_from_bottom' }}
      />
      <Stack.Screen
        name="SleepHistory"
        component={SleepHistoryScreen}
        options={historyOptions}
      />
      <Stack.Screen
        name="CaffeineHistory"
        component={CaffeineHistoryScreen}
        options={historyOptions}
      />
    </Stack.Navigator>
  );
}
