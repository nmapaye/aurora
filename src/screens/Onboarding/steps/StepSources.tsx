import React from 'react';
import { View } from 'react-native';

import { HealthOptionCard, HealthSectionHeader } from '~/components/ui';
import useAppScheme from '~/hooks/useAppScheme';
import type { OnboardingSource } from '~/state/store';
import { getAppPalette } from '~/theme/colors';

type Props = {
  selectedSource: OnboardingSource;
  onSelect: (value: OnboardingSource) => void;
};

export default function StepSources({ selectedSource, onSelect }: Props) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const options: { key: OnboardingSource; title: string; body: string }[] = [
    {
      key: 'healthkit',
      title: 'Health',
      body: 'Read recent sleep from the Health app.',
    },
    {
      key: 'manual',
      title: 'Manual',
      body: 'Skip Health for now. You can connect later.',
    },
  ];

  return (
    <View style={{ gap: 16 }}>
      <HealthSectionHeader title="Data Source" />

      <View style={{ gap: 12 }}>
        {options.map((option) => {
          const selected = option.key === selectedSource;
          return (
            <HealthOptionCard
              key={option.key}
              onPress={() => onSelect(option.key)}
              selected={selected}
              icon={option.key === 'healthkit' ? 'heart' : 'create-outline'}
              title={option.title}
              subtitle={option.body}
              color={
                option.key === 'healthkit' ? palette.healthAccent : palette.tint
              }
            />
          );
        })}
      </View>
    </View>
  );
}
