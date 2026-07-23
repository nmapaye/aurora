import React from 'react';
import { Text, View } from 'react-native';

import { HealthOptionCard, StepperField } from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { spacing, typeRamp } from '~/theme/tokens';

type Props = {
  targetSleep: number;
  onChange: (value: number) => void;
};

export default function StepSleepTarget({ targetSleep, onChange }: Props) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const presets = [7, 8, 9];

  return (
    <View style={{ gap: spacing.md }}>
      <View style={{ gap: spacing.xs }}>
        <Text
          style={{
            ...typeRamp.title1,
            fontWeight: '700',
            letterSpacing: 0,
            color: palette.textPrimary,
          }}
        >
          Sleep target
        </Text>
        <Text
          style={{
            ...typeRamp.body,
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
        onChange={(value) => onChange(Math.round(value * 2) / 2)}
      />

      <View style={{ gap: spacing.sm }}>
        <Text
          style={{
            ...typeRamp.footnote,
            color: palette.textSecondary,
            fontWeight: '600',
          }}
        >
          Common Targets
        </Text>
        <View style={{ gap: spacing.sm }}>
          {presets.map((preset) => {
            const selected = preset === Math.round(targetSleep);
            return (
              <HealthOptionCard
                key={preset}
                onPress={() => onChange(preset)}
                selected={selected}
                icon="bed"
                title={`${preset} hours`}
                subtitle={
                  preset === 7
                    ? 'Light target'
                    : preset === 8
                      ? 'Standard target'
                      : 'Extended target'
                }
                color={palette.sleepAccent}
              />
            );
          })}
        </View>
      </View>
    </View>
  );
}
