import React from 'react';
import { Pressable, Text, View } from 'react-native';

import AppIcon, { type AppIconName } from '~/components/AppIcon';
import {
  describeSignal,
  signalMetaLine,
  type SignalCardModel,
} from '~/features/signals/model';
import useAppScheme from '~/hooks/useAppScheme';
import useLargeText from '~/hooks/useLargeText';
import { getAppPalette } from '~/theme/colors';
import {
  borders,
  controlSizes,
  fontScaling,
  iconSizes,
  numericText,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';

// Renders one SignalCardModel. A real observation gets the full card: label,
// value, when/where it came from, and one line of context. An empty signal
// collapses to a quiet row that names what is missing and where to add it, so
// "no data" never looks as weighty as a recorded value. Sample data carries a
// visible badge.
export default function SignalCard({
  model,
  icon,
  accent,
  onPress,
}: {
  model: SignalCardModel;
  icon: AppIconName;
  accent: string;
  onPress: () => void;
}) {
  const palette = getAppPalette(useAppScheme());
  const largeText = useLargeText();
  const empty = model.status === 'empty';

  return (
    <Pressable
      accessible
      accessibilityRole="button"
      // One stop for VoiceOver instead of several fragments.
      accessibilityLabel={describeSignal(model)}
      accessibilityHint={`${model.destination}.`}
      onPress={onPress}
      style={({ pressed }) => ({
        overflow: 'hidden',
        borderRadius: empty ? radii.card : radii.hero,
        borderWidth: empty ? borders.hairline : 0,
        borderColor: palette.cardBorder,
        backgroundColor: pressed
          ? palette.pressed
          : empty
            ? 'transparent'
            : palette.card,
        transform: [{ scale: pressed ? 0.98 : 1 }],
      })}
    >
      {empty ? (
        <View
          style={{
            minHeight: controlSizes.minimumTouchTarget + spacing.md,
            paddingHorizontal: spacing.md,
            paddingVertical: spacing.sm,
            flexDirection: largeText ? 'column' : 'row',
            alignItems: largeText ? 'flex-start' : 'center',
            gap: largeText ? spacing.xs : spacing.sm,
          }}
        >
          <View
            style={{
              flex: largeText ? undefined : 1,
              flexDirection: 'row',
              alignItems: 'center',
              gap: spacing.sm,
            }}
          >
            <AppIcon
              name={icon}
              size={iconSizes.inline}
              color={palette.textTertiary}
            />
            <View style={{ flex: 1, gap: 2 }}>
              <Text
                maxFontSizeMultiplier={fontScaling.body}
                style={{
                  ...typeRamp.subheadline,
                  fontWeight: '600',
                  color: palette.textSecondary,
                }}
              >
                {model.label}
              </Text>
              <Text
                maxFontSizeMultiplier={fontScaling.body}
                style={{ ...typeRamp.footnote, color: palette.textTertiary }}
              >
                {model.context}
              </Text>
            </View>
          </View>
          <View
            style={{ flexDirection: 'row', alignItems: 'center', gap: 2 }}
          >
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.subheadline, color: palette.tint }}
            >
              {model.destination}
            </Text>
            <AppIcon
              name="chevron-forward"
              size={iconSizes.inline}
              color={palette.tint}
            />
          </View>
        </View>
      ) : (
        <View
          style={{
            paddingHorizontal: spacing.lg,
            paddingVertical: spacing.md,
            gap: spacing.md,
          }}
        >
          <View
            style={{
              flexDirection: 'row',
              alignItems: 'center',
              gap: spacing.xs,
            }}
          >
            <AppIcon name={icon} size={iconSizes.row} color={accent} />
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ flex: 1, ...typeRamp.headline, color: accent }}
            >
              {model.label}
            </Text>
            <AppIcon
              name="chevron-forward"
              size={iconSizes.row}
              color={palette.textTertiary}
            />
          </View>
          <View style={{ gap: spacing.xxs }}>
            <Text
              maxFontSizeMultiplier={fontScaling.hero}
              style={{ ...numericText, color: palette.textPrimary }}
            >
              {model.value}
            </Text>
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.subheadline, color: palette.textSecondary }}
            >
              {model.context}
            </Text>
          </View>
          <View
            style={{
              flexDirection: 'row',
              flexWrap: 'wrap',
              alignItems: 'center',
              gap: spacing.xs,
            }}
          >
            {model.status === 'sample' ? (
              <View
                style={{
                  flexDirection: 'row',
                  alignItems: 'center',
                  gap: spacing.xxs,
                  paddingHorizontal: spacing.xs,
                  paddingVertical: 2,
                  borderRadius: radii.capsule,
                  backgroundColor: palette.selectionFill,
                }}
              >
                <AppIcon
                  name="sparkles-outline"
                  size={iconSizes.inline}
                  color={palette.tint}
                />
                <Text
                  maxFontSizeMultiplier={fontScaling.body}
                  style={{
                    ...typeRamp.caption,
                    fontWeight: '600',
                    color: palette.tint,
                  }}
                >
                  Sample Data
                </Text>
              </View>
            ) : null}
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                flexShrink: 1,
                ...typeRamp.footnote,
                color: palette.textTertiary,
              }}
            >
              {model.status === 'sample'
                ? model.period
                : signalMetaLine(model)}
            </Text>
          </View>
        </View>
      )}
    </Pressable>
  );
}
