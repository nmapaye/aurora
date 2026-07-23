import React from 'react';
import type { RefObject } from 'react';
import type {
  LayoutChangeEvent,
  Text as TextInstance,
} from 'react-native';
import { Text, View } from 'react-native';

import Button from '~/components/Button';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import {
  fontScaling,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';
import type { SummaryWalkthroughStep } from './model';

type Props = {
  step: SummaryWalkthroughStep;
  locked: boolean;
  headingRef: RefObject<TextInstance | null>;
  onLayout?: (event: LayoutChangeEvent) => void;
  onSkip: () => void;
  onPrimary: () => void;
};

export default function SummaryWalkthroughCoach({
  step,
  locked,
  headingRef,
  onLayout,
  onSkip,
  onPrimary,
}: Props) {
  const palette = getAppPalette(useAppScheme());

  return (
    <View
      accessibilityViewIsModal
      onLayout={onLayout}
      style={{
        width: '100%',
        maxWidth: 560,
        alignSelf: 'center',
        gap: spacing.sm,
        padding: spacing.md,
        borderRadius: radii.hero,
        backgroundColor: palette.card,
        borderWidth: 1,
        borderColor: palette.cardBorder,
        shadowColor: '#000000',
        shadowOpacity: 0.14,
        shadowRadius: 18,
        shadowOffset: { width: 0, height: 8 },
        elevation: 6,
      }}
    >
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.footnote,
          fontWeight: '600',
          color: palette.tint,
        }}
      >
        {step.progress}
      </Text>
      <Text
        ref={headingRef}
        accessibilityRole="header"
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.title3,
          color: palette.textPrimary,
        }}
      >
        {step.title}
      </Text>
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.body,
          color: palette.textSecondary,
        }}
      >
        {step.body}
      </Text>
      <View
        style={{
          flexDirection: 'row',
          justifyContent: 'flex-end',
          alignItems: 'center',
          gap: spacing.sm,
        }}
      >
        <Button
          title="Skip"
          variant="plain"
          disabled={locked}
          onPress={onSkip}
        />
        <Button
          title={step.primaryAction}
          variant="primary"
          disabled={locked}
          onPress={onPrimary}
        />
      </View>
    </View>
  );
}
