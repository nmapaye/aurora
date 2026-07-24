import React from 'react';
import { Text, View } from 'react-native';

import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, numericText, radii, spacing, typeRamp } from '~/theme/tokens';

type Props = {
  title: string;
  value: string;
  dateRange: string;
  accessibilitySummary: string;
  children?: React.ReactNode;
  emptyState?: React.ReactNode;
};

export function HealthChartCard({
  title,
  value,
  dateRange,
  accessibilitySummary,
  children,
  emptyState,
}: Props) {
  const palette = getAppPalette(useAppScheme());

  return (
    <View
      accessible
      accessibilityLabel={accessibilitySummary}
      style={{
        backgroundColor: palette.card,
        borderRadius: radii.hero,
        borderWidth: 1,
        borderColor: palette.cardBorder,
        padding: spacing.md,
        gap: spacing.md,
      }}
    >
      <View style={{ gap: spacing.xxs }}>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.headline, color: palette.textPrimary }}
        >
          {title}
        </Text>
        <Text
          maxFontSizeMultiplier={fontScaling.hero}
          style={{ ...numericText, color: palette.textPrimary }}
        >
          {value}
        </Text>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.footnote, color: palette.textSecondary }}
        >
          {dateRange}
        </Text>
      </View>
      {children ?? emptyState}
    </View>
  );
}
