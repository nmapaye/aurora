import React from 'react';
import {
  Pressable,
  ScrollView,
  StyleProp,
  Text,
  View,
  ViewStyle,
} from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';

import AppIcon, { appIcons } from '~/components/AppIcon';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import { navigate } from '~/navigation';
import { getAppPalette } from '~/theme/colors';
import {
  fontScaling,
  iconSizes,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';

type Props = {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  trailing?: React.ReactNode;
  contentStyle?: StyleProp<ViewStyle>;
  centered?: boolean;
  showsVerticalScrollIndicator?: boolean;
  topInset?: number;
};

export default function AppScreen({
  title,
  subtitle,
  children,
  trailing,
  contentStyle,
  centered = false,
  showsVerticalScrollIndicator = false,
  topInset = spacing.xs,
}: Props) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const insets = useSafeAreaInsets();
  const layout = useAdaptiveLayout();

  return (
    <ScrollView
      contentInsetAdjustmentBehavior="automatic"
      showsVerticalScrollIndicator={showsVerticalScrollIndicator}
      style={{ flex: 1, backgroundColor: palette.groupedBackground }}
      contentContainerStyle={[
        {
          paddingTop: topInset + layout.topChromeBuffer,
          paddingBottom: spacing.xxl + insets.bottom,
          paddingHorizontal: layout.horizontalPadding,
          alignItems: centered || layout.isWideLayout ? 'center' : undefined,
        },
        contentStyle,
      ]}
    >
      <View
        style={{
          width: '100%',
          maxWidth: layout.contentMaxWidth,
          gap: spacing.md,
        }}
      >
        <View style={{ gap: spacing.sm }}>
          <View
            style={{
              flexDirection: 'row',
              alignItems: 'flex-start',
              gap: spacing.sm,
            }}
          >
            <View style={{ flex: 1, gap: spacing.xxs }}>
              <Text
                maxFontSizeMultiplier={fontScaling.body}
                style={{
                  ...typeRamp.largeTitle,
                  letterSpacing: 0,
                  color: palette.textPrimary,
                }}
              >
                {title}
              </Text>
              {subtitle ? (
                <Text
                  maxFontSizeMultiplier={fontScaling.body}
                  style={{
                    ...typeRamp.subheadline,
                    color: palette.textSecondary,
                  }}
                >
                  {subtitle}
                </Text>
              ) : null}
            </View>

            {trailing ?? (
              <Pressable
                accessibilityRole="button"
                accessibilityLabel="Open settings"
                onPress={() => navigate('Settings')}
                style={({ pressed }) => ({
                  minWidth: 44,
                  minHeight: 44,
                  borderRadius: radii.capsule,
                  alignItems: 'center',
                  justifyContent: 'center',
                  backgroundColor: pressed
                    ? palette.pressed
                    : palette.cardMuted,
                  borderWidth: 1,
                  borderColor: palette.cardBorder,
                })}
              >
                <AppIcon
                  name={appIcons.settings}
                  size={iconSizes.button}
                  color={palette.textPrimary}
                />
              </Pressable>
            )}
          </View>
        </View>
        {children}
      </View>
    </ScrollView>
  );
}
