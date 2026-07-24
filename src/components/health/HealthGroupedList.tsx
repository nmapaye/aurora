import React from 'react';
import { Pressable, Text, View } from 'react-native';

import AppSymbol from '~/components/AppSymbol';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { controlSizes, fontScaling, iconSizes, radii, spacing, typeRamp } from '~/theme/tokens';

export type HealthGroupedListRow = {
  title: string;
  subtitle?: string;
  value?: string;
  onPress?: () => void;
  accessibilityLabel?: string;
  accessory?: React.ReactNode;
};

type Props = {
  rows: readonly HealthGroupedListRow[];
};

export function HealthGroupedList({ rows }: Props) {
  const palette = getAppPalette(useAppScheme());

  return (
    <View
      style={{
        overflow: 'hidden',
        backgroundColor: palette.card,
        borderRadius: radii.card,
        borderWidth: 1,
        borderColor: palette.cardBorder,
      }}
    >
      {rows.map((row, index) => {
        const pressable = Boolean(row.onPress);
        const content = (
          <View
            style={{
              minHeight: controlSizes.minimumTouchTarget,
              flexDirection: 'row',
              alignItems: 'center',
              gap: spacing.sm,
              paddingHorizontal: spacing.md,
              paddingVertical: spacing.xs,
              borderTopWidth: index === 0 ? 0 : 1,
              borderColor: palette.separator,
            }}
          >
            <View style={{ flex: 1, gap: spacing.xxs }}>
              <Text
                maxFontSizeMultiplier={fontScaling.body}
                style={{ ...typeRamp.body, color: palette.textPrimary }}
              >
                {row.title}
              </Text>
              {row.subtitle ? (
                <Text
                  maxFontSizeMultiplier={fontScaling.body}
                  style={{ ...typeRamp.footnote, color: palette.textSecondary }}
                >
                  {row.subtitle}
                </Text>
              ) : null}
            </View>
            {row.value ? (
              <Text
                maxFontSizeMultiplier={fontScaling.body}
                style={{ ...typeRamp.subheadline, color: palette.textSecondary }}
              >
                {row.value}
              </Text>
            ) : null}
            {row.accessory ??
              (pressable ? (
                <AppSymbol
                  testID={`health-row-disclosure-${index}`}
                  name="chevron.forward"
                  fallback="chevron-forward"
                  size={iconSizes.inline}
                  tintColor={palette.textTertiary}
                />
              ) : null)}
          </View>
        );

        if (!pressable) return <React.Fragment key={row.title}>{content}</React.Fragment>;

        return (
          <Pressable
            key={row.title}
            accessibilityRole="button"
            accessibilityLabel={row.accessibilityLabel ?? row.title}
            accessibilityHint="Opens details"
            onPress={row.onPress}
            style={({ pressed }) => ({ backgroundColor: pressed ? palette.pressed : 'transparent' })}
          >
            {content}
          </Pressable>
        );
      })}
    </View>
  );
}
