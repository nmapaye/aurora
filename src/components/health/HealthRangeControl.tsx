import React from 'react';
import { Pressable, Text, View } from 'react-native';

import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { controlSizes, radii, spacing, typeRamp } from '~/theme/tokens';

type Option<T extends string> = {
  value: T;
  label: string;
};

type Props<T extends string> = {
  options: readonly Option<T>[];
  value: T;
  onChange: (value: T) => void;
  accessibilityLabel?: string;
};

export function HealthRangeControl<T extends string>({
  options,
  value,
  onChange,
  accessibilityLabel,
}: Props<T>) {
  const palette = getAppPalette(useAppScheme());

  return (
    <View
      accessibilityLabel={accessibilityLabel}
      style={{
        alignSelf: 'flex-start',
        flexDirection: 'row',
        padding: spacing.xxs,
        borderRadius: radii.control,
        backgroundColor: palette.cardMuted,
        borderWidth: 1,
        borderColor: palette.cardBorder,
      }}
    >
      {options.map((option) => {
        const selected = option.value === value;
        return (
          <Pressable
            key={option.value}
            accessibilityRole="button"
            accessibilityLabel={option.label}
            accessibilityState={{ selected }}
            onPress={() => onChange(option.value)}
            style={({ pressed }) => ({
              minWidth: controlSizes.minimumTouchTarget,
              minHeight: controlSizes.minimumTouchTarget,
              alignItems: 'center',
              justifyContent: 'center',
              borderRadius: radii.control,
              paddingHorizontal: spacing.sm,
              backgroundColor: selected
                ? palette.card
                : pressed
                  ? palette.pressed
                  : 'transparent',
            })}
          >
            <Text
              style={{
                ...typeRamp.subheadline,
                fontWeight: selected ? '600' : '500',
                color: palette.textPrimary,
              }}
            >
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}
