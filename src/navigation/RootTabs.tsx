import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Platform, View } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useTheme } from '@react-navigation/native';
import DashboardScreen from '~/screens/DashboardScreen';
import LogIntakeScreen from '~/screens/LogIntakeScreen';
import SleepScreen from '~/screens/SleepScreen';
import InsightsScreen from '~/screens/InsightsScreen';
import SettingsScreen from '~/screens/SettingsScreen';
import HistoryScreen from '~/screens/HistoryScreen';

const Tab = createBottomTabNavigator();

export default function RootTabs(){
  const insets = useSafeAreaInsets();
  const inset = insets.bottom || 0;
  const tabBarHeight = Platform.select({ ios: 44 + Math.floor(inset), default: 48 });
  const tabBarPaddingBottom = Platform.select({ ios: Math.max(2, Math.floor(inset / 4)), default: 3 });
  const { colors } = useTheme();

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
              case 'Insights': return focused ? 'pulse' : 'pulse-outline';
              case 'Settings': return focused ? 'settings' : 'settings-outline';
              case 'History': return focused ? 'time' : 'time-outline';
              default: return 'ellipse-outline';
            }
          })();
          return <Ionicons name={name as any} size={size} color={color} />;
        },
        // Respect device bottom inset so the bar clears the Home indicator
        tabBarStyle: Platform.select({
          ios: { height: tabBarHeight, paddingBottom: tabBarPaddingBottom, paddingTop: 2, backgroundColor: colors.card, borderTopColor: colors.border },
          default: { height: 48, paddingBottom: 3, paddingTop: 2, backgroundColor: colors.card, borderTopColor: colors.border },
        }),
        tabBarBackground: () => <View style={{ flex: 1, backgroundColor: colors.card }} />,
        tabBarHideOnKeyboard: true,
      })}
    >
      <Tab.Screen name="Home" component={DashboardScreen}/>
      <Tab.Screen name="Sleep" component={SleepScreen}/>
      <Tab.Screen name="Log" component={LogIntakeScreen}/>
      <Tab.Screen name="Insights" component={InsightsScreen}/>
      <Tab.Screen
        name="History"
        component={HistoryScreen}
        options={{
          headerShown: false,
          tabBarLabel: 'History',
          tabBarIcon: ({ color, size, focused }) => (
            <Ionicons name={(focused ? 'time' : 'time-outline') as any} size={size} color={color} />
          ),
        }}
      />
      <Tab.Screen name="Settings" component={SettingsScreen}/>
    </Tab.Navigator>
  );
}
