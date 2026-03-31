import React from 'react';
import { Pressable, Text, View, useColorScheme } from 'react-native';

import type { OnboardingSource } from '~/state/store';
import { getAppPalette } from '~/theme/colors';

type Props = {
  selectedSource: OnboardingSource;
  onSelect: (value: OnboardingSource) => void;
};

export default function StepSources({ selectedSource, onSelect }: Props) {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const options: { key: OnboardingSource; title: string; body: string }[] = [
    {
      key: 'healthkit',
      title: 'Health app import',
      body: 'Recommended on iPhone. Aurora reads recent sleep so Home, Sleep, and Insights reflect real recovery data.',
    },
    {
      key: 'manual',
      title: 'Manual logging only',
      body: 'Skip health import for now and rely on dose logging. You can connect Health later from the Sleep screen.',
    },
  ];

  return (
    <View style={{ gap: 16 }}>
      <View style={{ gap: 8 }}>
        <Text
          style={{
            fontSize: 30,
            lineHeight: 36,
            fontWeight: '700',
            letterSpacing: -0.4,
            color: palette.textPrimary,
          }}
        >
          Choose your data source
        </Text>
        <Text
          style={{
            fontSize: 16,
            lineHeight: 22,
            color: palette.textSecondary,
          }}
        >
          Aurora is shipping with HealthKit support first. Android sync stays out of scope for this release.
        </Text>
      </View>

      <View style={{ gap: 12 }}>
        {options.map((option) => {
          const selected = option.key === selectedSource;
          return (
            <Pressable
              key={option.key}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              onPress={() => onSelect(option.key)}
              style={({ pressed }) => ({
                gap: 8,
                padding: 18,
                borderRadius: 20,
                borderWidth: 1,
                borderColor: selected ? palette.tint : palette.cardBorder,
                backgroundColor: selected
                  ? palette.cardMuted
                  : pressed
                  ? palette.pressed
                  : palette.card,
              })}
            >
              <Text
                style={{
                  fontSize: 18,
                  lineHeight: 24,
                  fontWeight: '600',
                  color: palette.textPrimary,
                }}
              >
                {option.title}
              </Text>
              <Text
                style={{
                  fontSize: 15,
                  lineHeight: 20,
                  color: palette.textSecondary,
                }}
              >
                {option.body}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}
