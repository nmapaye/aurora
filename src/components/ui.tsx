import React from 'react';
import {
  Pressable,
  StyleProp,
  Text,
  TextInput,
  TextStyle,
  View,
  ViewStyle,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';

import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette, getStatusColors, type StatusTone } from '~/theme/colors';

export function SectionTitle({
  children,
  action,
}: {
  children: React.ReactNode;
  action?: React.ReactNode;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
      <Text
        style={{
          flex: 1,
          fontSize: 20,
          lineHeight: 24,
          fontWeight: '700',
          color: palette.textPrimary,
        }}
      >
        {children}
      </Text>
      {action}
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
          borderRadius: 22,
          padding: 16,
          borderWidth: scheme === 'dark' ? 0 : 1,
          borderColor: palette.cardBorder,
          gap: 12,
        },
        style,
      ]}
    >
      {children}
    </View>
  );
}

export function HealthSectionHeader({
  title,
  actionLabel,
  onAction,
}: {
  title: string;
  actionLabel?: string;
  onAction?: () => void;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
      <Text
        style={{
          flex: 1,
          fontSize: 28,
          lineHeight: 34,
          fontWeight: '700',
          color: palette.textPrimary,
        }}
      >
        {title}
      </Text>
      {actionLabel ? (
        <Pressable
          accessibilityRole="button"
          onPress={onAction}
          style={({ pressed }) => ({
            borderRadius: 12,
            paddingHorizontal: 4,
            paddingVertical: 3,
            opacity: pressed ? 0.65 : 1,
          })}
        >
          <Text
            style={{
              fontSize: 17,
              lineHeight: 22,
              color: palette.tint,
            }}
          >
            {actionLabel}
          </Text>
        </Pressable>
      ) : null}
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
  icon: keyof typeof Ionicons.glyphMap;
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
        paddingHorizontal: 20,
        paddingVertical: 18,
        gap: 24,
      }}
    >
      <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
        <Ionicons name={icon} size={21} color={labelColor} />
        <Text
          style={{
            flex: 1,
            fontSize: 17,
            lineHeight: 22,
            fontWeight: '700',
            color: labelColor,
          }}
        >
          {label}
        </Text>
        {dateLabel ? (
          <Text
            style={{
              fontSize: 17,
              lineHeight: 22,
              color: palette.textTertiary,
            }}
          >
            {dateLabel}
          </Text>
        ) : null}
        {onPress ? (
          <Ionicons
            name="chevron-forward"
            size={20}
            color={palette.textTertiary}
          />
        ) : null}
      </View>
      <View style={{ gap: 5 }}>
        <Text
          style={{
            fontSize: 33,
            lineHeight: 39,
            fontWeight: '700',
            color: palette.textPrimary,
          }}
        >
          {value}
        </Text>
        {detail ? (
          <Text
            style={{
              fontSize: 15,
              lineHeight: 20,
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
        borderRadius: 28,
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
}: {
  icon?: keyof typeof Ionicons.glyphMap;
  title: string;
  subtitle?: string;
  selected?: boolean;
  onPress?: () => void;
  color?: string;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const accent = color ?? palette.tint;
  return (
    <Pressable
      accessibilityRole="button"
      accessibilityState={{ selected }}
      onPress={onPress}
      style={({ pressed }) => ({
        flexDirection: 'row',
        alignItems: 'center',
        gap: 14,
        minHeight: 72,
        borderRadius: 24,
        paddingHorizontal: 18,
        paddingVertical: 16,
        backgroundColor: pressed ? palette.pressed : palette.card,
        borderWidth: scheme === 'dark' ? 0 : 1,
        borderColor: selected ? accent : palette.cardBorder,
      })}
    >
      {icon ? (
        <Ionicons
          name={icon}
          size={24}
          color={selected ? accent : palette.textSecondary}
        />
      ) : null}
      <View style={{ flex: 1, gap: 3 }}>
        <Text
          style={{
            fontSize: 17,
            lineHeight: 22,
            fontWeight: '600',
            color: selected ? accent : palette.textPrimary,
          }}
        >
          {title}
        </Text>
        {subtitle ? (
          <Text
            style={{
              fontSize: 14,
              lineHeight: 19,
              color: palette.textSecondary,
            }}
          >
            {subtitle}
          </Text>
        ) : null}
      </View>
      {selected ? (
        <Ionicons name="checkmark-circle" size={22} color={accent} />
      ) : (
        <Ionicons name="chevron-forward" size={18} color={palette.textTertiary} />
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
  icon?: keyof typeof Ionicons.glyphMap;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const header =
    tone === 'warning'
      ? { backgroundColor: '#FFD60A', color: '#1C1C1E' }
      : tone === 'error'
      ? { backgroundColor: palette.destructive, color: '#FFFFFF' }
      : { backgroundColor: 'transparent', color: palette.textSecondary };
  const iconColor =
    tone === 'warning'
      ? '#FFD60A'
      : tone === 'error'
      ? palette.destructive
      : palette.tint;

  return (
    <View
      style={{
        overflow: 'hidden',
        borderRadius: 28,
        backgroundColor: palette.card,
      }}
    >
      {tone === 'warning' || tone === 'error' ? (
        <View
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: 8,
            paddingHorizontal: 18,
            paddingVertical: 10,
            backgroundColor: header.backgroundColor,
          }}
        >
          <Ionicons name="warning" size={17} color={header.color} />
          <Text
            style={{
              flex: 1,
              fontSize: 15,
              lineHeight: 20,
              fontWeight: '700',
              color: header.color,
            }}
          >
            {label.toUpperCase()}
          </Text>
          {dateLabel ? (
            <Text style={{ fontSize: 15, lineHeight: 20, color: header.color }}>
              {dateLabel}
            </Text>
          ) : null}
        </View>
      ) : null}
      <View style={{ paddingHorizontal: 20, paddingVertical: 18, gap: 12 }}>
        {tone === 'info' ? (
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            <Text
              style={{
                flex: 1,
                fontSize: 15,
                lineHeight: 20,
                fontWeight: '700',
                color: palette.tint,
              }}
            >
              {label}
            </Text>
            {dateLabel ? (
              <Text
                style={{
                  fontSize: 15,
                  lineHeight: 20,
                  color: palette.textTertiary,
                }}
              >
                {dateLabel}
              </Text>
            ) : null}
          </View>
        ) : null}
        <View style={{ flexDirection: 'row', gap: 16 }}>
          <Ionicons name={icon} size={42} color={iconColor} />
          <View style={{ flex: 1, gap: 8 }}>
            <Text
              style={{
                fontSize: 24,
                lineHeight: 30,
                fontWeight: '700',
                color: palette.textPrimary,
              }}
            >
              {title}
            </Text>
            {body ? (
              <Text
                style={{
                  fontSize: 17,
                  lineHeight: 23,
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
                  borderRadius: 18,
                  paddingHorizontal: 14,
                  paddingVertical: 8,
                  backgroundColor: pressed
                    ? palette.pressed
                    : palette.selectionFill,
                })}
              >
                <Text
                  style={{
                    fontSize: 17,
                    lineHeight: 22,
                    fontWeight: '600',
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
          borderRadius: 16,
          padding: 14,
          borderWidth: scheme === 'dark' ? 0 : 1,
          borderColor: palette.cardBorder,
          gap: 4,
        },
        style,
      ]}
    >
      <Text
        style={{
          fontSize: 13,
          lineHeight: 18,
          fontWeight: '600',
          color: palette.textSecondary,
        }}
      >
        {label}
      </Text>
      <Text
        style={{
          fontSize: 28,
          lineHeight: 34,
          fontWeight: '700',
          color: palette.textPrimary,
        }}
      >
        {value}
      </Text>
      {detail ? (
        <Text
          style={{
            fontSize: 13,
            lineHeight: 18,
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
        gap: 12,
        minHeight: 52,
      }}
    >
      <View style={{ flex: 1, gap: 2 }}>
        <Text style={{ fontSize: 16, lineHeight: 20, color }}>{title}</Text>
        {subtitle ? (
          <Text
            style={{
              fontSize: 13,
              lineHeight: 18,
              color: palette.textSecondary,
            }}
          >
            {subtitle}
          </Text>
        ) : null}
      </View>
      {value ? (
        <Text
          style={{
            fontSize: 15,
            lineHeight: 20,
            color: palette.textSecondary,
          }}
        >
          {value}
        </Text>
      ) : null}
      {accessory ?? (onPress ? (
        <Ionicons
          name="chevron-forward"
          size={16}
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
          borderRadius: 14,
          paddingHorizontal: 2,
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
        padding: 4,
        borderRadius: 12,
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
              minHeight: 36,
              borderRadius: 10,
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
              style={{
                fontSize: 15,
                lineHeight: 20,
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
    <View style={{ gap: 8 }}>
      <Text
        style={{
          fontSize: 13,
          lineHeight: 18,
          fontWeight: '600',
          color: palette.textSecondary,
        }}
      >
        {label.toUpperCase()}
      </Text>
      {children}
      {footer ? (
        <Text
          style={{
            fontSize: 13,
            lineHeight: 18,
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
        paddingHorizontal: 10,
        paddingVertical: 6,
        borderRadius: 999,
        backgroundColor: status.backgroundColor,
      }}
    >
      <Text
        style={{
          fontSize: 13,
          lineHeight: 18,
          fontWeight: '600',
          color: status.color ?? palette.textSecondary,
        }}
      >
        {text}
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
        value={displayValue}
        accessory={
          <View style={{ flexDirection: 'row', alignItems: 'center', gap: 8 }}>
            <StepperButton
              symbol="remove"
              onPress={() => update(value - step)}
            />
            <StepperButton symbol="add" onPress={() => update(value + step)} />
          </View>
        }
      />
      {footer ? (
        <Text
          style={{
            fontSize: 13,
            lineHeight: 18,
            color: palette.textTertiary,
          }}
        >
          {footer}
        </Text>
      ) : null}
    </SectionCard>
  );
}

function StepperButton({
  symbol,
  onPress,
}: {
  symbol: 'add' | 'remove';
  onPress: () => void;
}) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  return (
    <Pressable
      accessibilityRole="button"
      onPress={onPress}
      style={({ pressed }) => ({
        width: 32,
        height: 32,
        borderRadius: 16,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: pressed ? palette.pressed : palette.cardMuted,
        borderWidth: scheme === 'dark' ? 0 : 1,
        borderColor: palette.cardBorder,
      })}
    >
      <Ionicons name={symbol} size={18} color={palette.textPrimary} />
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
          minHeight: multiline ? 96 : 48,
          borderRadius: 14,
          paddingHorizontal: 14,
          paddingVertical: multiline ? 12 : 14,
          backgroundColor: palette.fieldBackground,
          borderWidth: scheme === 'dark' ? 0 : 1,
          borderColor: palette.cardBorder,
          color: palette.textPrimary,
          fontSize: 16,
          lineHeight: 20,
        },
        style,
      ]}
    />
  );
}
