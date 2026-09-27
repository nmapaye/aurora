import React from 'react';
import { Pressable, Text, View } from 'react-native';

import AppIcon from '~/components/AppIcon';
import { Eyebrow, Surface } from '~/components/ui';
import {
  formatSleepTarget,
  SLEEP_TARGET_PRESETS,
  SLEEP_TARGET_RANGE,
} from '~/features/onboarding/presentation';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import {
  borders,
  fontScaling,
  iconSizes,
  motion,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';

type Props = {
  targetSleep: number;
  onChange: (value: number) => void;
};

const STEP_BUTTON_SIZE = 52;

export default function StepSleepTarget({ targetSleep, onChange }: Props) {
  const palette = getAppPalette(useAppScheme());
  const { min, max, step } = SLEEP_TARGET_RANGE;
  const target = formatSleepTarget(targetSleep);
  const update = (next: number) =>
    onChange(Math.min(max, Math.max(min, Math.round(next * 2) / 2)));
  const canDecrease = targetSleep > min;
  const canIncrease = targetSleep < max;

  return (
    <View style={{ gap: spacing.lg }}>
      <Surface
        radius={radii.hero}
        style={{
          paddingVertical: spacing.xl,
          paddingHorizontal: spacing.lg,
          gap: spacing.sm,
        }}
      >
        <View
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: spacing.sm,
          }}
        >
          <RoundStepButton
            icon="remove"
            accessibilityLabel="Decrease sleep target"
            disabled={!canDecrease}
            onPress={() => update(targetSleep - step)}
          />
          <View
            accessible
            accessibilityRole="adjustable"
            accessibilityLabel="Sleep target"
            accessibilityValue={{ text: target.spoken }}
            accessibilityActions={[
              { name: 'increment' },
              { name: 'decrement' },
            ]}
            onAccessibilityAction={(event) => {
              if (event.nativeEvent.actionName === 'increment') {
                update(targetSleep + step);
              } else if (event.nativeEvent.actionName === 'decrement') {
                update(targetSleep - step);
              }
            }}
            style={{ flex: 1, alignItems: 'center' }}
          >
            <Text
              maxFontSizeMultiplier={fontScaling.hero}
              style={{
                fontSize: 64,
                fontWeight: '300',
                fontVariant: ['tabular-nums'],
                color: palette.textPrimary,
              }}
            >
              {target.value}
            </Text>
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.subheadline, color: palette.textSecondary }}
            >
              {target.unit} a night
            </Text>
          </View>
          <RoundStepButton
            icon="add"
            accessibilityLabel="Increase sleep target"
            disabled={!canIncrease}
            onPress={() => update(targetSleep + step)}
          />
        </View>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            ...typeRamp.footnote,
            textAlign: 'center',
            color: palette.textTertiary,
          }}
        >
          From {min} to {max} hours, in half-hour steps.
        </Text>
      </Surface>

      <View style={{ gap: spacing.sm }}>
        <Eyebrow text="Common targets" />
        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}>
          {SLEEP_TARGET_PRESETS.map((preset) => {
            const selected = preset === targetSleep;
            return (
              <Pressable
                key={preset}
                accessibilityRole="button"
                accessibilityLabel={`${preset} hours`}
                accessibilityState={{ selected }}
                onPress={() => onChange(preset)}
                style={({ pressed }) => ({
                  flexGrow: 1,
                  flexBasis: 88,
                  minHeight: STEP_BUTTON_SIZE,
                  paddingHorizontal: spacing.md,
                  paddingVertical: spacing.sm,
                  borderRadius: radii.capsule,
                  alignItems: 'center',
                  justifyContent: 'center',
                  borderWidth: selected ? borders.selected : borders.hairline,
                  borderColor: selected ? palette.tint : palette.cardBorder,
                  backgroundColor: selected
                    ? palette.selectionFill
                    : pressed
                      ? palette.pressed
                      : palette.card,
                })}
              >
                <Text
                  maxFontSizeMultiplier={fontScaling.body}
                  style={{
                    ...typeRamp.headline,
                    fontWeight: selected ? '600' : '500',
                    color: selected ? palette.tint : palette.textPrimary,
                  }}
                >
                  {preset} hours
                </Text>
              </Pressable>
            );
          })}
        </View>
      </View>
    </View>
  );
}

function RoundStepButton({
  icon,
  accessibilityLabel,
  disabled,
  onPress,
}: {
  icon: 'add' | 'remove';
  accessibilityLabel: string;
  disabled: boolean;
  onPress: () => void;
}) {
  const palette = getAppPalette(useAppScheme());
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ disabled }}
      disabled={disabled}
      onPress={onPress}
      style={({ pressed }) => ({
        width: STEP_BUTTON_SIZE,
        height: STEP_BUTTON_SIZE,
        borderRadius: radii.capsule,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: pressed ? palette.pressed : palette.cardMuted,
        borderWidth: borders.hairline,
        borderColor: palette.cardBorder,
        opacity: disabled ? motion.disabledOpacity : 1,
      })}
    >
      <AppIcon name={icon} size={iconSizes.button} color={palette.textPrimary} />
    </Pressable>
  );
}
