import React from 'react';
import { Text, View } from 'react-native';
import Svg, { Circle } from 'react-native-svg';

import {
  describeAlertnessEstimate,
  type AlertnessEstimate,
} from '~/features/summary/presentation';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { eyebrowText, fontScaling, typeRamp } from '~/theme/tokens';

// The Summary hero ring. It shows the alertness model's 0–100 output and never
// a placeholder number: without recent sleep the ring stays an empty track.
export default function AlertnessRing({
  estimate,
  size = 152,
}: {
  estimate: AlertnessEstimate;
  size?: number;
}) {
  const palette = getAppPalette(useAppScheme());
  const strokeWidth = Math.round(size * 0.07);
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const hasScore = estimate.status === 'estimated';
  const fraction = hasScore
    ? Math.max(0, Math.min(1, estimate.score / 100))
    : 0;

  return (
    <View
      accessible
      accessibilityRole="image"
      accessibilityLabel={describeAlertnessEstimate(estimate)}
      style={{ width: size, height: size }}
    >
      <Svg width={size} height={size}>
        <Circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          stroke={palette.cardMuted}
          strokeWidth={strokeWidth}
          strokeDasharray={hasScore ? undefined : [2, 8]}
          strokeLinecap="round"
          fill="none"
        />
        {hasScore && fraction > 0 ? (
          <Circle
            cx={size / 2}
            cy={size / 2}
            r={radius}
            stroke={palette.tint}
            strokeWidth={strokeWidth}
            strokeDasharray={[circumference * fraction, circumference]}
            strokeLinecap="round"
            fill="none"
            rotation={-90}
            origin={`${size / 2}, ${size / 2}`}
          />
        ) : null}
      </Svg>
      <View
        pointerEvents="none"
        style={{
          position: 'absolute',
          top: 0,
          left: 0,
          width: size,
          height: size,
          alignItems: 'center',
          justifyContent: 'center',
          paddingHorizontal: strokeWidth * 2,
        }}
      >
        <Text
          numberOfLines={1}
          adjustsFontSizeToFit
          maxFontSizeMultiplier={fontScaling.hero}
          style={{
            fontSize: Math.round(size * 0.3),
            fontWeight: '300',
            fontVariant: ['tabular-nums'],
            letterSpacing: -1,
            color: hasScore ? palette.textPrimary : palette.textTertiary,
          }}
        >
          {hasScore ? `${estimate.score}` : '—'}
        </Text>
        <Text
          numberOfLines={1}
          adjustsFontSizeToFit
          maxFontSizeMultiplier={fontScaling.hero}
          style={{
            ...eyebrowText,
            fontSize: typeRamp.caption.fontSize,
            color: palette.textSecondary,
          }}
        >
          {hasScore ? 'Estimate' : 'No estimate'}
        </Text>
      </View>
    </View>
  );
}
