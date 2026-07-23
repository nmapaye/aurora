import React from 'react';
import type { BottomTabBarButtonProps } from '@react-navigation/bottom-tabs';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { PlatformPressable } from '@react-navigation/elements';
import { View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import {
  isSummaryWalkthroughPending,
  isWalkthroughTabDisabled,
} from '~/features/summaryWalkthrough';
import DashboardScreen from '~/screens/DashboardScreen';
import LogIntakeScreen from '~/screens/LogIntakeScreen';
import SleepScreen from '~/screens/SleepScreen';
import InsightsScreen from '~/screens/InsightsScreen';
import useAppScheme from '~/hooks/useAppScheme';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import AppIcon, { appIcons, type AppIconName } from '~/components/AppIcon';

const Tab = createBottomTabNavigator();

function WalkthroughTabButton({
  walkthroughDisabled,
  accessibilityState,
  ...props
}: BottomTabBarButtonProps & { walkthroughDisabled: boolean }) {
  return (
    <PlatformPressable
      {...props}
      disabled={walkthroughDisabled}
      accessibilityState={{
        ...accessibilityState,
        disabled: walkthroughDisabled,
      }}
    />
  );
}

export default function RootTabs() {
  const insets = useSafeAreaInsets();
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const walkthroughPending = useStore((state) =>
    isSummaryWalkthroughPending(state.onboarding),
  );
  const inset = insets.bottom || 0;
  const tabBarHeight = 54 + Math.floor(inset);
  const tabBarPaddingBottom = Math.max(6, Math.floor(inset / 3));

  return (
    <Tab.Navigator
      screenOptions={({ route }) => {
        const walkthroughDisabled = isWalkthroughTabDisabled(
          route.name,
          walkthroughPending,
        );

        return {
          headerShown: false,
          tabBarShowLabel: true,
          tabBarIcon: ({ focused, color, size }) => {
            const name: AppIconName = (() => {
              switch (route.name) {
                case 'Summary':
                  return focused
                    ? appIcons.summarySelected
                    : appIcons.summary;
                case 'Log':
                  return focused
                    ? appIcons.logSelected
                    : appIcons.log;
                case 'Sleep':
                  return focused
                    ? appIcons.sleepSelected
                    : appIcons.sleep;
                case 'Insights':
                  return focused
                    ? appIcons.insightsSelected
                    : appIcons.insights;
                default:
                  return appIcons.fallback;
              }
            })();
            return <AppIcon name={name} size={size} color={color} />;
          },
          tabBarButton: (props) => (
            <WalkthroughTabButton
              {...props}
              walkthroughDisabled={walkthroughDisabled}
            />
          ),
          tabBarActiveTintColor: palette.tint,
          tabBarInactiveTintColor: palette.textTertiary,
          // Respect device bottom inset so the bar clears the Home indicator
          tabBarStyle: {
            height: tabBarHeight,
            paddingBottom: tabBarPaddingBottom,
            paddingTop: 8,
            backgroundColor: palette.card,
            borderTopColor: palette.cardBorder,
          },
          tabBarLabelStyle: { fontSize: 11, fontWeight: '500' },
          tabBarBackground: () => (
            <View style={{ flex: 1, backgroundColor: palette.card }} />
          ),
          tabBarHideOnKeyboard: true,
        };
      }}
    >
      <Tab.Screen name="Summary" component={DashboardScreen} />
      <Tab.Screen name="Sleep" component={SleepScreen} />
      <Tab.Screen name="Log" component={LogIntakeScreen} />
      <Tab.Screen name="Insights" component={InsightsScreen} />
    </Tab.Navigator>
  );
}
