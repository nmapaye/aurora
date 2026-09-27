import React, { useEffect, useMemo, useRef, useState } from 'react';
import type { AccessibilityActionEvent } from 'react-native';
import { PanResponder, Text, View } from 'react-native';
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

export type BarInspection = {
  /** Spoken summary of the whole range; the adjustable chart's label. */
  accessibilityLabel: string;
  /** Readout for one bar. Missing days must say so rather than read zero. */
  describe: (index: number) => { title: string; value: string };
  /** The bar the readout shows before anything is selected. */
  defaultIndex: number;
};

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
  /**
   * Makes the bars inspectable by tap, horizontal drag, and VoiceOver
   * adjustment, with a readout above them. Without it the chart is decorative
   * and the parent card carries the spoken summary.
   */
  inspection?: BarInspection;
};

const EMPTY_BAR = 3;
const MIN_BAR = 6;
const DRAW_IN_MS = 520;
const TOUCH_SLOP = 6;
const DIMMED_OPACITY = 0.35;

type GestureAxis = 'undecided' | 'horizontal' | 'vertical';

function Bar({
  target,
  progress,
  color,
  dimmed,
}: {
  target: number;
  progress: SharedValue<number>;
  color: string;
  dimmed: boolean;
}) {
  const style = useAnimatedStyle(() => ({
    height: Math.max(EMPTY_BAR, target * progress.value),
  }));
  return (
    <Animated.View
      style={[
        {
          flex: 1,
          borderRadius: 3,
          backgroundColor: color,
          opacity: dimmed ? DIMMED_OPACITY : 1,
        },
        style,
      ]}
    />
  );
}

function clampIndex(index: number, count: number) {
  return Math.max(0, Math.min(count - 1, index));
}

/**
 * Daily bars that grow in when the data or range changes, with an optional
 * dashed reference (daily limit, sleep target).
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
  inspection,
}: Props) {
  const palette = getAppPalette(useAppScheme());
  const reduceMotion = useReduceMotion();
  const progress = useSharedValue(reduceMotion ? 1 : 0);
  const scaleMax = Math.max(1, max, reference ? reference.value * 1.1 : 0);
  const signature = points.map((point) => `${point.key}:${point.value}`).join('|');
  const [selectedIndex, setSelectedIndex] = useState<number | null>(null);
  const [width, setWidth] = useState(0);

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

  // A new range or new data starts from the default readout again.
  useEffect(() => {
    setSelectedIndex(null);
  }, [signature]);

  // The responder is created once; refs keep it reading the latest geometry.
  const inspectableRef = useRef(Boolean(inspection) && points.length > 0);
  inspectableRef.current = Boolean(inspection) && points.length > 0;
  const selectAtRef = useRef((_x: number) => {});
  selectAtRef.current = (x: number) => {
    if (width <= 0 || points.length === 0) return;
    setSelectedIndex(
      clampIndex(Math.floor((x / width) * points.length), points.length),
    );
  };
  const gesture = useRef<{ grantX: number; axis: GestureAxis }>({
    grantX: 0,
    axis: 'undecided',
  });

  // The chart sits inside the page's vertical ScrollView. It takes the touch
  // so a tap can select, but yields to the ScrollView until a gesture commits
  // to the horizontal axis, and a committed vertical swipe stays a scroll.
  const responder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => inspectableRef.current,
        onMoveShouldSetPanResponder: (_event, g) =>
          inspectableRef.current &&
          Math.abs(g.dx) > TOUCH_SLOP &&
          Math.abs(g.dx) > Math.abs(g.dy),
        onShouldBlockNativeResponder: () => false,
        onPanResponderGrant: (event) => {
          gesture.current = {
            grantX: event.nativeEvent.locationX,
            axis: 'undecided',
          };
        },
        onPanResponderMove: (_event, g) => {
          const state = gesture.current;
          if (
            state.axis === 'undecided' &&
            Math.max(Math.abs(g.dx), Math.abs(g.dy)) > TOUCH_SLOP
          ) {
            state.axis =
              Math.abs(g.dx) > Math.abs(g.dy) ? 'horizontal' : 'vertical';
          }
          if (state.axis === 'horizontal') {
            selectAtRef.current(state.grantX + g.dx);
          }
        },
        onPanResponderTerminationRequest: () =>
          gesture.current.axis !== 'horizontal',
        onPanResponderRelease: () => {
          if (gesture.current.axis === 'undecided') {
            selectAtRef.current(gesture.current.grantX);
          }
          gesture.current.axis = 'undecided';
        },
        onPanResponderTerminate: () => {
          gesture.current.axis = 'undecided';
        },
      }),
    [],
  );

  const inspectable = Boolean(inspection) && points.length > 0;
  const activeIndex = inspectable
    ? clampIndex(selectedIndex ?? inspection!.defaultIndex, points.length)
    : null;
  const readout =
    inspection && activeIndex !== null ? inspection.describe(activeIndex) : null;
  const readoutText = readout ? `${readout.title}, ${readout.value}` : '';

  const onAccessibilityAction = (event: AccessibilityActionEvent) => {
    if (activeIndex === null) return;
    const step =
      event.nativeEvent.actionName === 'increment'
        ? 1
        : event.nativeEvent.actionName === 'decrement'
          ? -1
          : 0;
    if (step) setSelectedIndex(clampIndex(activeIndex + step, points.length));
  };

  const referenceBottom = reference
    ? Math.min(height, (reference.value / scaleMax) * height)
    : 0;

  const plot = (
    <View style={{ height, justifyContent: 'flex-end' }}>
      <View
        pointerEvents={inspectable ? 'none' : undefined}
        style={{ height, flexDirection: 'row', alignItems: 'flex-end', gap: 3 }}
      >
        {points.map((point, index) => {
          const selected = selectedIndex === index;
          return (
            <Bar
              key={point.key}
              progress={progress}
              dimmed={selectedIndex !== null && !selected}
              color={
                point.value === null
                  ? selected
                    ? palette.textTertiary
                    : palette.separator
                  : color
              }
              target={
                point.value === null
                  ? EMPTY_BAR
                  : Math.max(MIN_BAR, Math.min(height, (point.value / scaleMax) * height))
              }
            />
          );
        })}
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
  );

  const axisLabels =
    startLabel || endLabel ? (
      <View
        accessibilityElementsHidden={inspectable}
        importantForAccessibility={inspectable ? 'no-hide-descendants' : undefined}
        style={{ flexDirection: 'row', justifyContent: 'space-between' }}
      >
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
    ) : null;

  if (!inspectable || !inspection) {
    return (
      <View
        testID={testID}
        accessibilityElementsHidden
        importantForAccessibility="no-hide-descendants"
        style={{ gap: spacing.xs }}
      >
        {plot}
        {axisLabels}
      </View>
    );
  }

  return (
    <View testID={testID} style={{ gap: spacing.xs }}>
      {readout ? (
        // Visual only: the adjustable plot speaks the same readout as its value.
        <View
          testID={testID ? `${testID}-readout` : undefined}
          accessibilityElementsHidden
          importantForAccessibility="no-hide-descendants"
          style={{ gap: 2 }}
        >
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{ ...typeRamp.footnote, color: palette.textSecondary }}
          >
            {readout.title}
          </Text>
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              ...typeRamp.headline,
              fontVariant: ['tabular-nums'],
              color: palette.textPrimary,
            }}
          >
            {readout.value}
          </Text>
        </View>
      ) : null}
      <View
        testID={testID ? `${testID}-plot` : undefined}
        accessible
        accessibilityRole="adjustable"
        accessibilityLabel={inspection.accessibilityLabel}
        accessibilityValue={{ text: readoutText }}
        accessibilityHint="Swipe up or down to move between days."
        accessibilityActions={[{ name: 'increment' }, { name: 'decrement' }]}
        onAccessibilityAction={onAccessibilityAction}
        onLayout={(event) => setWidth(event.nativeEvent.layout.width)}
        {...responder.panHandlers}
      >
        {plot}
      </View>
      {axisLabels}
    </View>
  );
}
