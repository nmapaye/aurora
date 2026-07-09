import React from 'react';
import { Text, View } from 'react-native';

import { HealthOptionCard, HealthSectionHeader, StepperField } from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';

type Props = {
  targetSleep: number;
  onChange: (value: number) => void;
};

export default function StepSleepTarget({ targetSleep, onChange }: Props) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const presets = [7, 8, 9];

  return (
    <View style={{ gap: 16 }}>
      <HealthSectionHeader title="Sleep Target" />

      <StepperField
        label="Target sleep"
        value={targetSleep}
        step={0.5}
        min={5}
        max={10}
        formatValue={(value) => `${value.toFixed(1)} h`}
        onChange={(value) => onChange(Math.round(value * 2) / 2)}
      />

      <View style={{ gap: 10 }}>
        <Text
          style={{
            fontSize: 13,
            lineHeight: 18,
            color: palette.textSecondary,
            fontWeight: '600',
          }}
        >
          Common Targets
        </Text>
        <View style={{ gap: 10 }}>
          {presets.map((preset) => {
            const selected = preset === Math.round(targetSleep);
            return (
              <HealthOptionCard
                key={preset}
                onPress={() => onChange(preset)}
                selected={selected}
                icon="bed"
                title={`${preset} hours`}
                subtitle={preset === 7 ? 'Light target' : preset === 8 ? 'Standard target' : 'Extended target'}
                color="#7D7AFF"
              />
            );
          })}
        </View>
      </View>
    </View>
  );
}
