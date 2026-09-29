import React from 'react';
import { Text, View } from 'react-native';

import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, numericText, radii, spacing, typeRamp } from '~/theme/tokens';

type Props = {
  title: string;
  /** Omit rather than show a placeholder number when there is no data. */
  value?: string;
  dateRange: string;
  accessibilitySummary: string;
  children?: React.ReactNode;
  emptyState?: React.ReactNode;
  /**
   * Set when the children are themselves accessible (an inspectable chart):
   * the card then stops grouping everything into one element, and only its
   * header speaks as a unit.
   */
  interactiveChildren?: boolean;
};

export function HealthChartCard({
  title,
  value,
  dateRange,
  accessibilitySummary,
  children,
  emptyState,
  interactiveChildren = false,
}: Props) {
  const palette = getAppPalette(useAppScheme());
  const grouped = !interactiveChildren || !children;

  return (
    <View
      accessible={grouped}
      accessibilityLabel={grouped ? accessibilitySummary : undefined}
      style={{
        backgroundColor: palette.card,
        borderRadius: radii.hero,
        borderWidth: 1,
        borderColor: palette.cardBorder,
        padding: spacing.md,
        gap: spacing.md,
      }}
    >
      <View
        accessible={!grouped}
        accessibilityRole={grouped ? undefined : 'header'}
        accessibilityLabel={
          grouped ? undefined : [title, value, dateRange].filter(Boolean).join(', ')
        }
        style={{ gap: spacing.xxs }}
      >
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.headline, color: palette.textPrimary }}
        >
          {title}
        </Text>
        {value ? (
          <Text
            maxFontSizeMultiplier={fontScaling.hero}
            style={{ ...numericText, color: palette.textPrimary }}
          >
            {value}
          </Text>
        ) : null}
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
