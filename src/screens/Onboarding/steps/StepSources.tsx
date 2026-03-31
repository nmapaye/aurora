import React from 'react';
import { Pressable, Text, View, PlatformColor } from 'react-native';

import type { OnboardingSource } from '~/state/store';

type Props = {
  selectedSource: OnboardingSource;
  onSelect: (value: OnboardingSource) => void;
};

export default function StepSources({ selectedSource, onSelect }: Props) {
  const options: { key: OnboardingSource; title: string; body: string }[] = [
    {
      key: 'healthkit',
      title: 'Health app import',
      body: 'Recommended for iPhone. Aurora reads recent sleep so the dashboard and insights reflect real recovery.',
    },
    {
      key: 'manual',
      title: 'Manual logging only',
      body: 'Skip health import for now and rely on caffeine logs. You can connect Health later from the Sleep tab.',
    },
  ];

  return (
    <View style={{ gap: 16 }}>
      <View style={{ gap: 8 }}>
        <Text style={{ fontSize: 28, lineHeight: 34, fontWeight: '700', color: PlatformColor('label') }}>
          Choose your data source
        </Text>
        <Text style={{ fontSize: 16, lineHeight: 22, color: PlatformColor('secondaryLabel') }}>
          Aurora is shipping with iPhone HealthKit support first. Android sync stays out of scope for this release.
        </Text>
      </View>

      <View style={{ gap: 12 }}>
        {options.map((option) => {
          const selected = option.key === selectedSource;
          return (
            <Pressable
              key={option.key}
              onPress={() => onSelect(option.key)}
              accessibilityRole="button"
              accessibilityState={{ selected }}
              style={{
                padding: 18,
                borderRadius: 20,
                backgroundColor: selected ? PlatformColor('secondarySystemFill') : PlatformColor('secondarySystemBackground'),
                borderWidth: 1,
                borderColor: selected ? PlatformColor('tintColor') : PlatformColor('separator'),
                gap: 6,
              }}
            >
              <Text style={{ fontSize: 18, lineHeight: 24, fontWeight: '600', color: PlatformColor('label') }}>
                {option.title}
              </Text>
              <Text style={{ fontSize: 15, lineHeight: 20, color: PlatformColor('secondaryLabel') }}>
                {option.body}
              </Text>
            </Pressable>
          );
        })}
      </View>
    </View>
  );
}
