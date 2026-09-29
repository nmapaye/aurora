import React from 'react';
import { View } from 'react-native';

import { HealthOptionCard } from '~/components/ui';
import { describeSleepSource } from '~/features/onboarding/presentation';
import useAppScheme from '~/hooks/useAppScheme';
import type { OnboardingSource } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { spacing } from '~/theme/tokens';

type Props = {
  selectedSource: OnboardingSource;
  onSelect: (value: OnboardingSource) => void;
};

const options: { key: OnboardingSource; body: string }[] = [
  {
    key: 'healthkit',
    body: 'Read recent sleep from the Health app. Aurora never writes to Health.',
  },
  {
    key: 'manual',
    body: 'Log nights yourself. You can connect Health later from Sleep.',
  },
];

export default function StepSources({ selectedSource, onSelect }: Props) {
  const palette = getAppPalette(useAppScheme());

  return (
    <View style={{ gap: spacing.sm }}>
      {options.map((option) => (
        <HealthOptionCard
          key={option.key}
          onPress={() => onSelect(option.key)}
          selected={option.key === selectedSource}
          icon={option.key === 'healthkit' ? 'heart-outline' : 'create-outline'}
          title={describeSleepSource(option.key)}
          subtitle={option.body}
          color={palette.tint}
        />
      ))}
    </View>
  );
}
