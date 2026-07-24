import React from 'react';
import { Text, View } from 'react-native';

import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, numericText, radii, spacing, typeRamp } from '~/theme/tokens';

type Props = {
  label: string;
  value: string;
  detail?: string;
  accentColor?: string;
};

export function HealthHighlightCard({ label, value, detail, accentColor }: Props) {
  const palette = getAppPalette(useAppScheme());
  const color = accentColor ?? palette.tint;

  return (
    <View
      style={{
        flex: 1,
        minHeight: 112,
        backgroundColor: palette.card,
        borderRadius: radii.card,
        borderWidth: 1,
        borderColor: palette.cardBorder,
        padding: spacing.md,
        gap: spacing.xs,
      }}
    >
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...typeRamp.footnote, fontWeight: '600', color }}
      >
        {label}
      </Text>
      <Text
        maxFontSizeMultiplier={fontScaling.hero}
        style={{ ...numericText, color: palette.textPrimary }}
      >
        {value}
      </Text>
      {detail ? (
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.footnote, color: palette.textSecondary }}
        >
          {detail}
        </Text>
      ) : null}
    </View>
  );
}
