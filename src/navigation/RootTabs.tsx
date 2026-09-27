import React from 'react';
import { createNativeBottomTabNavigator } from '@react-navigation/bottom-tabs/unstable';
import type { SFSymbol } from 'expo-symbols';
import {
  isAppWalkthroughPending,
  isWalkthroughTabDisabled,
  getAppWalkthroughRoute,
} from '~/features/appWalkthrough/model';
import DashboardScreen from '~/screens/DashboardScreen';
import LogIntakeScreen from '~/screens/LogIntakeScreen';
import SleepScreen from '~/screens/SleepScreen';
import InsightsScreen from '~/screens/InsightsScreen';
import useAppScheme from '~/hooks/useAppScheme';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { appIcons, sfSymbolFor } from '~/components/AppIcon';

const Tab = createNativeBottomTabNavigator();

// SF Symbols for each tab: outline when idle, filled when selected, matching
// the in-app icon set.
export const TAB_SYMBOLS = {
  Summary: [appIcons.summary, appIcons.summarySelected],
  Sleep: [appIcons.sleep, appIcons.sleepSelected],
  Log: [appIcons.log, appIcons.logSelected],
  Insights: [appIcons.insights, appIcons.insightsSelected],
} as const;

export function tabSymbol(routeName: string, focused: boolean): SFSymbol {
  const names = TAB_SYMBOLS[routeName as keyof typeof TAB_SYMBOLS];
  const icon = names ? names[focused ? 1 : 0] : appIcons.fallback;
  return sfSymbolFor[icon] ?? 'circle';
}

// The system UITabBarController: Liquid Glass bar, native selection feedback,
// sidebar-adaptable on iPad. Screens keep their in-content large titles
// (headers stay hidden) because the walkthrough reveals and measures them.
export default function RootTabs() {
  const palette = getAppPalette(useAppScheme());
  const walkthroughPending = useStore((state) =>
    isAppWalkthroughPending(state.onboarding),
  );
  const walkthroughStep = useStore(
    (state) => state.onboarding.appWalkthroughStep,
  );

  return (
    <Tab.Navigator
      initialRouteName={
        walkthroughPending
          ? getAppWalkthroughRoute(walkthroughStep)
          : 'Summary'
      }
      screenOptions={({ route }) => ({
        headerShown: false,
        tabBarIcon: ({ focused }) => ({
          type: 'sfSymbol',
          name: tabSymbol(route.name, focused),
        }),
        tabBarActiveTintColor: palette.tint,
        tabBarInactiveTintColor: palette.textTertiary,
        // The walkthrough moves between tabs itself; users can't jump ahead.
        tabBarSelectionEnabled: !isWalkthroughTabDisabled(
          route.name,
          walkthroughPending,
        ),
      })}
    >
      <Tab.Screen name="Summary" component={DashboardScreen} />
      <Tab.Screen name="Sleep" component={SleepScreen} />
      <Tab.Screen name="Log" component={LogIntakeScreen} />
      <Tab.Screen name="Insights" component={InsightsScreen} />
    </Tab.Navigator>
  );
}
