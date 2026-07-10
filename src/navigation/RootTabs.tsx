import React from 'react';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { Platform, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import DashboardScreen from '~/screens/DashboardScreen';
import LogIntakeScreen from '~/screens/LogIntakeScreen';
import SleepScreen from '~/screens/SleepScreen';
import InsightsScreen from '~/screens/InsightsScreen';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import AppIcon, { appIcons, type AppIconName } from '~/components/AppIcon';

const Tab = createBottomTabNavigator();

export default function RootTabs() {
  const insets = useSafeAreaInsets();
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const inset = insets.bottom || 0;
  const tabBarHeight = Platform.select({
    ios: 54 + Math.floor(inset),
    default: 56,
  });
  const tabBarPaddingBottom = Platform.select({
    ios: Math.max(6, Math.floor(inset / 3)),
    default: 6,
  });

  return (
    <Tab.Navigator
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarShowLabel: true,
        tabBarIcon: ({ focused, color, size }) => {
          const name: AppIconName = (() => {
            switch (route.name) {
              case 'Summary':
                return focused ? appIcons.summarySelected : appIcons.summary;
              case 'Log':
                return focused ? appIcons.logSelected : appIcons.log;
              case 'Sleep':
                return focused ? appIcons.sleepSelected : appIcons.sleep;
              case 'Insights':
                return focused ? appIcons.insightsSelected : appIcons.insights;
              default:
                return appIcons.fallback;
            }
          })();
          return <AppIcon name={name} size={size} color={color} />;
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
        tabBarLabelStyle: { fontSize: 11, fontWeight: '500' },
        tabBarBackground: () => (
          <View style={{ flex: 1, backgroundColor: palette.card }} />
        ),
        tabBarHideOnKeyboard: true,
      })}
    >
      <Tab.Screen name="Summary" component={DashboardScreen} />
      <Tab.Screen name="Sleep" component={SleepScreen} />
      <Tab.Screen name="Log" component={LogIntakeScreen} />
      <Tab.Screen name="Insights" component={InsightsScreen} />
    </Tab.Navigator>
  );
}
