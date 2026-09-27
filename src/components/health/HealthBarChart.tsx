import React, { useEffect } from 'react';
import { Text, View } from 'react-native';
import Animated, {
  Easing,
  type SharedValue,
  useAnimatedStyle,
  useSharedValue,
  withTiming,
} from 'react-native-reanimated';

import useAppScheme from '~/hooks/useAppScheme';
import useReduceMotion from '~/hooks/useReduceMotion';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, spacing, typeRamp } from '~/theme/tokens';

export type BarPoint = { key: string | number; value: number | null };

type Props = {
  points: readonly BarPoint[];
  /** Top of the scale; the reference line always fits inside it. */
  max: number;
  color: string;
  height?: number;
  reference?: { value: number; label: string };
  startLabel?: string;
  endLabel?: string;
  testID?: string;
};

const EMPTY_BAR = 3;
const MIN_BAR = 6;
const DRAW_IN_MS = 520;

function Bar({
  target,
  progress,
  color,
}: {
  target: number;
  progress: SharedValue<number>;
  color: string;
}) {
  const style = useAnimatedStyle(() => ({
    height: Math.max(EMPTY_BAR, target * progress.value),
  }));
  return (
    <Animated.View
      style={[{ flex: 1, borderRadius: 3, backgroundColor: color }, style]}
    />
  );
}

/**
 * Daily bars that grow in when the data or range changes, with an optional
 * dashed reference (daily limit, sleep target). Decorative: the parent card
 * carries the spoken summary.
 */
export function HealthBarChart({
  points,
  max,
  color,
  height = 112,
  reference,
  startLabel,
  endLabel,
  testID,
}: Props) {
  const palette = getAppPalette(useAppScheme());
  const reduceMotion = useReduceMotion();
  const progress = useSharedValue(reduceMotion ? 1 : 0);
  const scaleMax = Math.max(1, max, reference ? reference.value * 1.1 : 0);
  const signature = points.map((point) => `${point.key}:${point.value}`).join('|');

  useEffect(() => {
    if (reduceMotion) {
      progress.value = 1;
      return;
    }
    progress.value = 0;
    progress.value = withTiming(1, {
      duration: DRAW_IN_MS,
      easing: Easing.out(Easing.cubic),
    });
  }, [progress, reduceMotion, signature]);

  const referenceBottom = reference
    ? Math.min(height, (reference.value / scaleMax) * height)
    : 0;

  return (
    <View
      testID={testID}
      accessibilityElementsHidden
      importantForAccessibility="no-hide-descendants"
      style={{ gap: spacing.xs }}
    >
      <View style={{ height, justifyContent: 'flex-end' }}>
        <View
          style={{ height, flexDirection: 'row', alignItems: 'flex-end', gap: 3 }}
        >
          {points.map((point) => (
            <Bar
              key={point.key}
              progress={progress}
              color={point.value === null ? palette.separator : color}
              target={
                point.value === null
                  ? EMPTY_BAR
                  : Math.max(MIN_BAR, Math.min(height, (point.value / scaleMax) * height))
              }
            />
          ))}
        </View>
        {reference ? (
          <View
            testID={testID ? `${testID}-reference` : undefined}
            pointerEvents="none"
            style={{
              position: 'absolute',
              left: 0,
              right: 0,
              bottom: referenceBottom,
              flexDirection: 'row',
              alignItems: 'center',
              gap: spacing.xxs,
            }}
          >
            <View
              style={{
                flex: 1,
                borderTopWidth: 1,
                borderStyle: 'dashed',
                borderColor: palette.textTertiary,
              }}
            />
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.caption, color: palette.textSecondary }}
            >
              {reference.label}
            </Text>
          </View>
        ) : null}
      </View>
      {startLabel || endLabel ? (
        <View style={{ flexDirection: 'row', justifyContent: 'space-between' }}>
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{ ...typeRamp.caption, color: palette.textSecondary }}
          >
            {startLabel}
          </Text>
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{ ...typeRamp.caption, color: palette.textSecondary }}
          >
            {endLabel}
          </Text>
        </View>
      ) : null}
    </View>
  );
}
