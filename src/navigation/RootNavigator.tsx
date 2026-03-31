import React from 'react';
import { createNativeStackNavigator } from '@react-navigation/native-stack';

import RootTabs from './RootTabs';
import type { RootStackParamList } from './types';
import VigilanceTestScreen from '~/screens/VigilanceTestScreen';

const Stack = createNativeStackNavigator<RootStackParamList>();

export default function RootNavigator() {
  return (
    <Stack.Navigator screenOptions={{ headerShown: false }}>
      <Stack.Screen name="Tabs" component={RootTabs} />
      <Stack.Screen
        name="VigilanceTest"
        component={VigilanceTestScreen}
        options={{ presentation: 'card', animation: 'slide_from_right' }}
      />
    </Stack.Navigator>
  );
}
