import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import DashboardScreen from '~/screens/DashboardScreen';
import LogIntakeScreen from '~/screens/LogIntakeScreen';
import SleepScreen from '~/screens/SleepScreen';
import InsightsScreen from '~/screens/InsightsScreen';
import SettingsScreen from '~/screens/SettingsScreen';

const Tab = createBottomTabNavigator();

export default function RootTabs(){
  return (
    <Tab.Navigator screenOptions={{ headerShown:false }}>
      <Tab.Screen name="Home" component={DashboardScreen}/>
      <Tab.Screen name="Log" component={LogIntakeScreen}/>
      <Tab.Screen name="Sleep" component={SleepScreen}/>
      <Tab.Screen name="Insights" component={InsightsScreen}/>
      <Tab.Screen name="Settings" component={SettingsScreen}/>
    </Tab.Navigator>
  );
}