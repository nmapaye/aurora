import React from 'react';
import {
  Pressable,
  ActivityIndicator,
  StyleProp,
  Text,
  TextInput,
  TextStyle,
  View,
  ViewStyle,
} from 'react-native';

import AppIcon, {
  appIcons,
  type AppIconName,
} from '~/components/AppIcon';
import AppSymbol, {
  type AppSymbolName,
} from '~/components/AppSymbol';
import useAppScheme from '~/hooks/useAppScheme';
import {
  getAppPalette,
  getStatusColors,
  type StatusTone,
} from '~/theme/colors';
import {
  controlSizes,
  fontScaling,
  iconSizes,
  numericText,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';

export function SectionHeader({
  title,
  prominence = 'standard',
  action,
  actionLabel,
  onAction,
}: {
  title: string;
  prominence?: 'standard' | 'prominent';
  action?: React.ReactNode;
  actionLabel?: string;
  onAction?: () => void;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View
      style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.sm }}
    >
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          flex: 1,
          ...(prominence === 'prominent' ? typeRamp.title1 : typeRamp.headline),
          color: palette.textPrimary,
        }}
      >
        {title}
      </Text>
      {action ??
        (actionLabel ? (
          <Pressable
            accessibilityRole="button"
            accessibilityLabel={actionLabel}
            onPress={onAction}
            style={({ pressed }) => ({
              minHeight: controlSizes.minimumTouchTarget,
              minWidth: controlSizes.minimumTouchTarget,
              borderRadius: radii.control,
              paddingHorizontal: spacing.xs,
              justifyContent: 'center',
              opacity: pressed ? 0.65 : 1,
            })}
          >
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.body, color: palette.tint }}
            >
              {actionLabel}
            </Text>
          </Pressable>
        ) : null)}
    </View>
  );
}

export function SectionCard({
  children,
  style,
}: {
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View
      style={[
        {
          backgroundColor: palette.card,
          borderRadius: radii.card,
          padding: spacing.md,
          borderWidth: scheme === 'dark' ? 0 : 1,
          borderColor: palette.cardBorder,
          gap: spacing.sm,
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

export function HealthMetricCard({
  icon,
  label,
  labelColor,
  value,
  detail,
  dateLabel,
  onPress,
}: {
  icon: AppIconName;
  label: string;
  labelColor: string;
  value: string;
  detail?: string;
  dateLabel?: string;
  onPress?: () => void;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const content = (
    <View
      style={{
        minHeight: 118,
        paddingHorizontal: spacing.lg,
        paddingVertical: spacing.md,
        gap: spacing.xl,
      }}
    >
      <View
        style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs }}
      >
        <AppIcon name={icon} size={iconSizes.row} color={labelColor} />
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            flex: 1,
            ...typeRamp.headline,
            color: labelColor,
          }}
        >
          {label}
        </Text>
        {dateLabel ? (
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              ...typeRamp.body,
              color: palette.textTertiary,
            }}
          >
            {dateLabel}
          </Text>
        ) : null}
        {onPress ? (
          <AppIcon
            name="chevron-forward"
            size={iconSizes.row}
            color={palette.textTertiary}
          />
        ) : null}
      </View>
      <View style={{ gap: spacing.xxs }}>
        <Text
          maxFontSizeMultiplier={fontScaling.hero}
          style={{
            ...numericText,
            color: palette.textPrimary,
          }}
        >
          {value}
        </Text>
        {detail ? (
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              ...typeRamp.subheadline,
              color: palette.textSecondary,
            }}
          >
            {detail}
          </Text>
        ) : null}
      </View>
    </View>
  );

  return (
    <Pressable
      accessibilityRole={onPress ? 'button' : undefined}
      onPress={onPress}
      disabled={!onPress}
      style={({ pressed }) => ({
        overflow: 'hidden',
        borderRadius: radii.hero,
        backgroundColor: pressed ? palette.pressed : palette.card,
      })}
    >
      {content}
    </Pressable>
  );
}

export function HealthOptionCard({
  icon,
  title,
  subtitle,
  selected = false,
  onPress,
  color,
  accessibilityLabel,
  symbol,
}: {
  icon?: AppIconName;
  title: string;
  subtitle?: string;
  selected?: boolean;
  onPress?: () => void;
  color?: string;
  accessibilityLabel?: string;
  symbol?: AppSymbolName;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const accent = color ?? palette.tint;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => ({
        flexDirection: 'row',
        alignItems: 'center',
        gap: spacing.sm,
        minHeight: 72,
        borderRadius: radii.hero,
        paddingHorizontal: spacing.md,
        paddingVertical: spacing.md,
        backgroundColor: pressed ? palette.pressed : palette.card,
        borderWidth: scheme === 'dark' ? 0 : 1,
        borderColor: selected ? accent : palette.cardBorder,
      })}
    >
      {symbol ? (
        <AppSymbol
          name={symbol}
          fallback={icon ?? appIcons.fallback}
          size={iconSizes.button}
          tintColor={selected ? accent : palette.textSecondary}
        />
      ) : icon ? (
        <AppIcon
          name={icon}
          size={iconSizes.button}
          color={selected ? accent : palette.textSecondary}
        />
      ) : null}
      <View style={{ flex: 1, gap: spacing.xxs }}>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            ...typeRamp.headline,
            color: selected ? accent : palette.textPrimary,
          }}
        >
          {title}
        </Text>
        {subtitle ? (
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              ...typeRamp.subheadline,
              color: palette.textSecondary,
            }}
          >
            {subtitle}
          </Text>
        ) : null}
      </View>
      {selected ? (
        <AppIcon name="checkmark-circle" size={iconSizes.row} color={accent} />
      ) : (
        <AppIcon
          name="chevron-forward"
          size={iconSizes.inline}
          color={palette.textTertiary}
        />
      )}
    </Pressable>
  );
}

export function HealthAlertCard({
  tone = 'info',
  label,
  dateLabel,
  title,
  body,
  actionLabel,
  onAction,
  icon = 'information-circle-outline',
}: {
  tone?: 'info' | 'warning' | 'error';
  label: string;
  dateLabel?: string;
  title: string;
  body?: string;
  actionLabel?: string;
  onAction?: () => void;
  icon?: AppIconName;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const header =
    tone === 'warning'
      ? {
          backgroundColor: palette.warningFill,
          color: palette.warningForeground,
        }
      : tone === 'error'
        ? { backgroundColor: palette.destructive, color: palette.onDestructive }
        : { backgroundColor: 'transparent', color: palette.textSecondary };
  const iconColor =
    tone === 'warning'
      ? palette.warningFill
      : tone === 'error'
        ? palette.destructive
        : palette.tint;

  return (
    <View
      style={{
        overflow: 'hidden',
        borderRadius: radii.hero,
        backgroundColor: palette.card,
      }}
    >
      {tone === 'warning' || tone === 'error' ? (
        <View
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: spacing.xs,
            paddingHorizontal: spacing.md,
            paddingVertical: spacing.xs,
            backgroundColor: header.backgroundColor,
          }}
        >
          <AppIcon
            name="warning"
            size={iconSizes.inline}
            color={header.color}
          />
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              flex: 1,
              ...typeRamp.subheadline,
              fontWeight: '700',
              color: header.color,
            }}
          >
            {label.toUpperCase()}
          </Text>
          {dateLabel ? (
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.subheadline, color: header.color }}
            >
              {dateLabel}
            </Text>
          ) : null}
        </View>
      ) : null}
      <View
        style={{
          paddingHorizontal: spacing.lg,
          paddingVertical: spacing.md,
          gap: spacing.sm,
        }}
      >
        {tone === 'info' ? (
          <View
            style={{
              flexDirection: 'row',
              alignItems: 'center',
              gap: spacing.xs,
            }}
          >
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                flex: 1,
                ...typeRamp.subheadline,
                fontWeight: '700',
                color: palette.tint,
              }}
            >
              {label}
            </Text>
            {dateLabel ? (
              <Text
                maxFontSizeMultiplier={fontScaling.body}
                style={{
                  ...typeRamp.subheadline,
                  color: palette.textTertiary,
                }}
              >
                {dateLabel}
              </Text>
            ) : null}
          </View>
        ) : null}
        <View style={{ flexDirection: 'row', gap: spacing.md }}>
          <AppIcon name={icon} size={iconSizes.hero} color={iconColor} />
          <View style={{ flex: 1, gap: spacing.xs }}>
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                ...typeRamp.title3,
                fontWeight: '700',
                color: palette.textPrimary,
              }}
            >
              {title}
            </Text>
            {body ? (
              <Text
                maxFontSizeMultiplier={fontScaling.body}
                style={{
                  ...typeRamp.body,
                  color: palette.textSecondary,
                }}
              >
                {body}
              </Text>
            ) : null}
            {actionLabel ? (
              <Pressable
                accessibilityRole="button"
                onPress={onAction}
                style={({ pressed }) => ({
                  alignSelf: 'flex-start',
                  minHeight: controlSizes.minimumTouchTarget,
                  borderRadius: radii.capsule,
                  paddingHorizontal: spacing.sm,
                  paddingVertical: spacing.xs,
                  justifyContent: 'center',
                  backgroundColor: pressed
                    ? palette.pressed
                    : palette.selectionFill,
                })}
              >
                <Text
                  maxFontSizeMultiplier={fontScaling.body}
                  style={{
                    ...typeRamp.headline,
                    color: palette.tint,
                  }}
                >
                  {actionLabel}
                </Text>
              </Pressable>
            ) : null}
          </View>
        </View>
      </View>
    </View>
  );
}

export function StatTile({
  label,
  value,
  detail,
  style,
}: {
  label: string;
  value: string;
  detail?: string;
  style?: StyleProp<ViewStyle>;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View
      style={[
        {
          flex: 1,
          minHeight: 92,
          backgroundColor: palette.cardMuted,
          borderRadius: radii.card,
          padding: spacing.sm,
          borderWidth: scheme === 'dark' ? 0 : 1,
          borderColor: palette.cardBorder,
          gap: spacing.xxs,
        },
        style,
      ]}
    >
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.footnote,
          fontWeight: '600',
          color: palette.textSecondary,
        }}
      >
        {label}
      </Text>
      <Text
        maxFontSizeMultiplier={fontScaling.hero}
        style={{
          ...numericText,
          fontWeight: '600',
          color: palette.textPrimary,
        }}
      >
        {value}
      </Text>
      {detail ? (
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            ...typeRamp.footnote,
            color: palette.textTertiary,
          }}
        >
          {detail}
        </Text>
      ) : null}
    </View>
  );
}

export function ListRow({
  title,
  subtitle,
  value,
  onPress,
  destructive = false,
  accessory,
}: {
  title: string;
  subtitle?: string;
  value?: string;
  onPress?: () => void;
  destructive?: boolean;
  accessory?: React.ReactNode;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const color = destructive ? palette.destructive : palette.textPrimary;

  const content = (
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        gap: spacing.sm,
        minHeight: 52,
      }}
    >
      <View style={{ flex: 1, gap: spacing.xxs }}>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{ ...typeRamp.body, color }}
        >
          {title}
        </Text>
        {subtitle ? (
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              ...typeRamp.footnote,
              color: palette.textSecondary,
            }}
          >
            {subtitle}
          </Text>
        ) : null}
      </View>
      {value ? (
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            ...typeRamp.subheadline,
            color: palette.textSecondary,
          }}
        >
          {value}
        </Text>
      ) : null}
      {accessory ??
        (onPress ? (
          <AppIcon
            name="chevron-forward"
            size={iconSizes.inline}
            color={palette.textTertiary}
          />
        ) : null)}
    </View>
  );

  if (onPress) {
    return (
      <Pressable
        accessibilityRole="button"
        onPress={onPress}
        style={({ pressed }) => ({
          borderRadius: radii.control,
          paddingHorizontal: spacing.xxs,
          backgroundColor: pressed ? palette.pressed : 'transparent',
        })}
      >
        {content}
      </Pressable>
    );
  }
  return content;
}

export function SegmentedControl<T extends string>({
  options,
  value,
  onChange,
}: {
  options: { key: T; label: string }[];
  value: T;
  onChange: (value: T) => void;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View
      style={{
        flexDirection: 'row',
        padding: spacing.xxs,
        borderRadius: radii.control,
        backgroundColor: palette.cardMuted,
        borderWidth: scheme === 'dark' ? 0 : 1,
        borderColor: palette.cardBorder,
      }}
    >
      {options.map((option) => {
        const active = option.key === value;
        return (
          <Pressable
            key={option.key}
            accessibilityRole="button"
            accessibilityState={{ selected: active }}
            onPress={() => onChange(option.key)}
            style={({ pressed }) => ({
              flex: 1,
              minHeight: controlSizes.minimumTouchTarget,
              borderRadius: radii.control,
              alignItems: 'center',
              justifyContent: 'center',
              backgroundColor: active
                ? palette.card
                : pressed
                  ? palette.pressed
                  : 'transparent',
            })}
          >
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                ...typeRamp.subheadline,
                fontWeight: active ? '600' : '500',
                color: palette.textPrimary,
              }}
            >
              {option.label}
            </Text>
          </Pressable>
        );
      })}
    </View>
  );
}

export function FormField({
  label,
  footer,
  children,
}: {
  label: string;
  footer?: string;
  children: React.ReactNode;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View style={{ gap: spacing.xs }}>
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.footnote,
          fontWeight: '600',
          color: palette.textSecondary,
        }}
      >
        {label.toUpperCase()}
      </Text>
      {children}
      {footer ? (
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            ...typeRamp.footnote,
            color: palette.textTertiary,
          }}
        >
          {footer}
        </Text>
      ) : null}
    </View>
  );
}

export function InlineStatus({
  tone = 'neutral',
  text,
}: {
  tone?: StatusTone;
  text: string;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const status = getStatusColors(tone, scheme);
  return (
    <View
      style={{
        alignSelf: 'flex-start',
        paddingHorizontal: spacing.sm,
        paddingVertical: spacing.xs,
        borderRadius: radii.capsule,
        backgroundColor: status.backgroundColor,
      }}
    >
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.footnote,
          fontWeight: '600',
          color: status.color ?? palette.textSecondary,
        }}
      >
        {text}
      </Text>
    </View>
  );
}

export function ProgressState({ label }: { label: string }) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View
      accessible
      accessibilityRole="progressbar"
      accessibilityLabel={label}
      style={{
        flexDirection: 'row',
        alignItems: 'center',
        gap: spacing.xs,
      }}
    >
      <ActivityIndicator color={palette.tint} />
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{ ...typeRamp.subheadline, color: palette.textSecondary }}
      >
        {label}
      </Text>
    </View>
  );
}

export function StepperField({
  label,
  value,
  onChange,
  step = 1,
  min,
  max,
  formatValue,
  footer,
}: {
  label: string;
  value: number;
  onChange: (value: number) => void;
  step?: number;
  min?: number;
  max?: number;
  formatValue?: (value: number) => string;
  footer?: string;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const displayValue = formatValue ? formatValue(value) : String(value);

  const update = (next: number) => {
    let clamped = next;
    if (typeof min === 'number') clamped = Math.max(min, clamped);
    if (typeof max === 'number') clamped = Math.min(max, clamped);
    onChange(clamped);
  };

  return (
    <SectionCard>
      <ListRow
        title={label}
        accessory={
          <StepperControl
            decrementLabel={`Decrease ${label}`}
            incrementLabel={`Increase ${label}`}
            onDecrement={() => update(value - step)}
            onIncrement={() => update(value + step)}
          >
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.subheadline, color: palette.textSecondary }}
            >
              {displayValue}
            </Text>
          </StepperControl>
        }
      />
      {footer ? (
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            ...typeRamp.footnote,
            color: palette.textTertiary,
          }}
        >
          {footer}
        </Text>
      ) : null}
    </SectionCard>
  );
}

export function StepperControl({
  children,
  decrementLabel,
  incrementLabel,
  onDecrement,
  onIncrement,
}: {
  children: React.ReactNode;
  decrementLabel: string;
  incrementLabel: string;
  onDecrement: () => void;
  onIncrement: () => void;
}) {
  return (
    <View
      style={{ flexDirection: 'row', alignItems: 'center', gap: spacing.xs }}
    >
      <StepperButton
        symbol="remove"
        accessibilityLabel={decrementLabel}
        onPress={onDecrement}
      />
      {children}
      <StepperButton
        symbol="add"
        accessibilityLabel={incrementLabel}
        onPress={onIncrement}
      />
    </View>
  );
}

function StepperButton({
  symbol,
  accessibilityLabel,
  onPress,
}: {
  symbol: 'add' | 'remove';
  accessibilityLabel: string;
  onPress: () => void;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel}
      onPress={onPress}
      style={({ pressed }) => ({
        width: controlSizes.minimumTouchTarget,
        height: controlSizes.minimumTouchTarget,
        borderRadius: radii.control,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: pressed ? palette.pressed : palette.cardMuted,
        borderWidth: scheme === 'dark' ? 0 : 1,
        borderColor: palette.cardBorder,
      })}
    >
      <AppIcon
        name={symbol}
        size={iconSizes.inline}
        color={palette.textPrimary}
      />
    </Pressable>
  );
}

export function FieldInput({
  value,
  onChangeText,
  placeholder,
  keyboardType,
  multiline = false,
  style,
}: {
  value: string;
  onChangeText: (value: string) => void;
  placeholder?: string;
  keyboardType?: 'default' | 'number-pad';
  multiline?: boolean;
  style?: StyleProp<TextStyle>;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <TextInput
      value={value}
      onChangeText={onChangeText}
      placeholder={placeholder}
      placeholderTextColor={palette.textTertiary}
      keyboardType={keyboardType}
      multiline={multiline}
      style={[
        {
          minHeight: multiline ? 96 : controlSizes.inputHeight,
          borderRadius: radii.control,
          paddingHorizontal: spacing.sm,
          paddingVertical: spacing.sm,
          backgroundColor: palette.fieldBackground,
          borderWidth: scheme === 'dark' ? 0 : 1,
          borderColor: palette.cardBorder,
          color: palette.textPrimary,
          ...typeRamp.body,
        },
        style,
      ]}
    />
  );
}
