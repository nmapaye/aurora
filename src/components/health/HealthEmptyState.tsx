import React from 'react';
import { Text, View } from 'react-native';

import AppSymbol, { type AppSymbolFallbackName, type AppSymbolName } from '~/components/AppSymbol';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, iconSizes, spacing, typeRamp } from '~/theme/tokens';

type Props = {
  message: string;
  detail?: string;
  symbol?: AppSymbolName;
  fallback?: AppSymbolFallbackName;
};

export function HealthEmptyState({
  message,
  detail,
  symbol,
  fallback = 'stats-chart-outline',
}: Props) {
  const palette = getAppPalette(useAppScheme());

  return (
    <View
      accessibilityRole="text"
      accessibilityLabel={detail ? `${message} ${detail}` : message}
      style={{ alignItems: 'center', gap: spacing.xs, paddingVertical: spacing.lg }}
    >
      {symbol ? (
        <AppSymbol
          name={symbol}
          fallback={fallback}
          size={iconSizes.button}
          tintColor={palette.textTertiary}
        />
      ) : null}
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...typeRamp.subheadline, color: palette.textSecondary, textAlign: 'center' }}
      >
        {message}
      </Text>
      {detail ? (
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.footnote, color: palette.textTertiary, textAlign: 'center' }}
        >
          {detail}
        </Text>
      ) : null}
    </View>
  );
}
