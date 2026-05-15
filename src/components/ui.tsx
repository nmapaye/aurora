import React from 'react';
import {
  Pressable,
  StyleProp,
  Text,
  TextInput,
  TextStyle,
  View,
  ViewStyle,
  useColorScheme,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';

import { getAppPalette, getStatusColors, type StatusTone } from '~/theme/colors';

export function SectionTitle({
  children,
  action,
}: {
  children: React.ReactNode;
  action?: React.ReactNode;
}) {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  return (
    <View style={{ flexDirection: 'row', alignItems: 'center', gap: 12 }}>
      <Text
        style={{
          flex: 1,
          fontSize: 17,
          lineHeight: 22,
          fontWeight: '600',
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
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  return (
    <View
      style={[
        {
          backgroundColor: palette.card,
          borderRadius: 14,
          padding: 16,
          borderWidth: 1,
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
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  return (
    <View
      style={[
        {
          flex: 1,
          minHeight: 92,
          backgroundColor: palette.cardMuted,
          borderRadius: 14,
          padding: 14,
          borderWidth: 1,
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
          fontWeight: '600',
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
  const scheme = useColorScheme();
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
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  return (
    <View
      style={{
        flexDirection: 'row',
        padding: 4,
        borderRadius: 12,
        backgroundColor: palette.cardMuted,
        borderWidth: 1,
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
  const scheme = useColorScheme();
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
  const scheme = useColorScheme();
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
  const scheme = useColorScheme();
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
  const scheme = useColorScheme();
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
        borderWidth: 1,
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
  const scheme = useColorScheme();
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
          borderWidth: 1,
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
