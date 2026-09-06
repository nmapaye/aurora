import PlanningScreen from '~/screens/PlanningScreen';
import PlanningTargetsScreen from '~/screens/PlanningTargetsScreen';
import ExperimentsScreen from '~/screens/ExperimentsScreen';
import SleepRoutinesScreen from '~/screens/SleepRoutinesScreen';
import React from 'react';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import DrinkLibraryScreen from '~/screens/DrinkLibraryScreen';
import RootTabs from './RootTabs';
import type { RootStackParamList } from './types';
import VigilanceTestScreen from '~/screens/VigilanceTestScreen';
import SettingsScreen from '~/screens/SettingsScreen';
import SleepHistoryScreen from '~/screens/SleepHistoryScreen';
import CaffeineHistoryScreen from '~/screens/CaffeineHistoryScreen';

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function RootNavigator() {
  return (
    <Stack.Navigator
      initialRouteName="Tabs"
      screenOptions={{ headerShown: false }}
    >
      <Stack.Screen
        name="DrinkLibrary"
        component={DrinkLibraryScreen}
        options={{ presentation: 'card' }}
      />
      <Stack.Screen name="SleepRoutines" component={SleepRoutinesScreen} />
      <Stack.Screen name="Planning" component={PlanningScreen} />
      <Stack.Screen name="PlanningTargets" component={PlanningTargetsScreen} />
      <Stack.Screen name="Experiments" component={ExperimentsScreen} />
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
        options={{ presentation: 'card', animation: 'slide_from_right' }}
      />
      <Stack.Screen
        name="CaffeineHistory"
        component={CaffeineHistoryScreen}
        options={{ presentation: 'card', animation: 'slide_from_right' }}
      />
    </Stack.Navigator>
  );
}
