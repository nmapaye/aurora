import React from 'react';
import { Pressable, Text, View, useColorScheme } from 'react-native';

import { SectionCard, SectionTitle, StepperField } from '~/components/ui';
import { getAppPalette } from '~/theme/colors';

type Props = {
  targetSleep: number;
  onChange: (value: number) => void;
};

export default function StepSleepTarget({ targetSleep, onChange }: Props) {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const presets = [7, 8, 9];

  return (
    <View style={{ gap: 16 }}>
      <View style={{ gap: 8 }}>
        <Text
          style={{
            fontSize: 30,
            lineHeight: 36,
            fontWeight: '700',
            letterSpacing: 0,
            color: palette.textPrimary,
          }}
        >
          Sleep target
        </Text>
        <Text
          style={{
            fontSize: 16,
            lineHeight: 22,
            color: palette.textSecondary,
          }}
        >
          Choose the nightly target Aurora should protect.
        </Text>
      </View>

      <StepperField
        label="Target sleep"
        value={targetSleep}
        step={0.5}
        min={5}
        max={10}
        formatValue={(value) => `${value.toFixed(1)} h`}
        footer="You can change this later in Settings."
        onChange={(value) => onChange(Math.round(value * 2) / 2)}
      />

      <SectionCard>
        <SectionTitle>Common targets</SectionTitle>
        <View style={{ flexDirection: 'row', gap: 10 }}>
          {presets.map((preset) => {
            const selected = preset === Math.round(targetSleep);
            return (
              <Pressable
                key={preset}
                accessibilityRole="button"
                accessibilityState={{ selected }}
                onPress={() => onChange(preset)}
                style={({ pressed }) => ({
                  flex: 1,
                  borderRadius: 16,
                  borderWidth: 1,
                  borderColor: selected ? palette.tint : palette.cardBorder,
                  backgroundColor: selected
                    ? palette.cardMuted
                    : pressed
                    ? palette.pressed
                    : palette.card,
                  paddingHorizontal: 14,
                  paddingVertical: 16,
                })}
              >
                <Text
                  style={{
                    fontSize: 17,
                    lineHeight: 22,
                    fontWeight: '600',
                    color: palette.textPrimary,
                    textAlign: 'center',
                  }}
                >
                  {preset}h
                </Text>
              </Pressable>
            );
          })}
        </View>
      </SectionCard>
    </View>
  );
}
