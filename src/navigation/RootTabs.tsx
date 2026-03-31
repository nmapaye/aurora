import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Platform, View, useColorScheme } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import DashboardScreen from '~/screens/DashboardScreen';
import LogIntakeScreen from '~/screens/LogIntakeScreen';
import SleepScreen from '~/screens/SleepScreen';
import InsightsScreen from '~/screens/InsightsScreen';
import { getAppPalette } from '~/theme/colors';

const Tab = createBottomTabNavigator();

export default function RootTabs(){
  const insets = useSafeAreaInsets();
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const inset = insets.bottom || 0;
  const tabBarHeight = Platform.select({ ios: 54 + Math.floor(inset), default: 56 });
  const tabBarPaddingBottom = Platform.select({ ios: Math.max(6, Math.floor(inset / 3)), default: 6 });

  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarShowLabel: true,
        tabBarIcon: ({ focused, color, size }) => {
          const name = (() => {
            switch (route.name) {
              case 'Home': return focused ? 'home' : 'home-outline';
              case 'Log': return focused ? 'add-circle' : 'add-circle-outline';
              case 'Sleep': return focused ? 'moon' : 'moon-outline';
              case 'Insights': return focused ? 'stats-chart' : 'stats-chart-outline';
              default: return 'ellipse-outline';
            }
          })();
          return <Ionicons name={name as any} size={size} color={color} />;
        },
        tabBarActiveTintColor: palette.tint,
        tabBarInactiveTintColor: palette.textTertiary,
        // Respect device bottom inset so the bar clears the Home indicator
        tabBarStyle: Platform.select({
          ios: {
            height: tabBarHeight,
            paddingBottom: tabBarPaddingBottom,
            paddingTop: 8,
            backgroundColor: palette.card,
            borderTopColor: palette.cardBorder,
          },
          default: {
            height: 56,
            paddingBottom: 6,
            paddingTop: 8,
            backgroundColor: palette.card,
            borderTopColor: palette.cardBorder,
          },
        }),
        tabBarLabelStyle: { fontSize: 11, fontWeight: '600' },
        tabBarBackground: () => <View style={{ flex: 1, backgroundColor: palette.card }} />,
        tabBarHideOnKeyboard: true,
      })}
    >
      <Tab.Screen name="Home" component={DashboardScreen}/>
      <Tab.Screen name="Sleep" component={SleepScreen}/>
      <Tab.Screen name="Log" component={LogIntakeScreen}/>
      <Tab.Screen name="Insights" component={InsightsScreen}/>
    </Tab.Navigator>
  );
}
