import React from 'react';
import {
  Pressable,
  Text,
  View,
  StyleSheet,
  StyleProp,
  ViewStyle,
  TextStyle,
} from 'react-native';
import { colors } from '../theme/colors';

type Variant = 'glass' | 'outline' | 'filled';
type Size = 'sm' | 'md' | 'lg';

type Props = {
  label: string;
  selected?: boolean;
  onPress?: () => void;
  onLongPress?: () => void;
  disabled?: boolean;
  variant?: Variant;
  size?: Size;
  style?: StyleProp<ViewStyle>;
  textStyle?: StyleProp<TextStyle>;
  iconLeft?: React.ReactNode;
  iconRight?: React.ReactNode;
  accessibilityLabel?: string;
  testID?: string;
};

const sizeTokens: Record<Size, { pv: number; ph: number; font: number; radius: number }> = {
  sm: { pv: 6, ph: 10, font: 12, radius: 999 },
  md: { pv: 8, ph: 14, font: 14, radius: 999 },
  lg: { pv: 10, ph: 16, font: 16, radius: 999 },
};

export default function Chip({
  label,
  selected = false,
  onPress,
  onLongPress,
  disabled = false,
  variant = 'glass',
  size = 'md',
  style,
  textStyle,
  iconLeft,
  iconRight,
  accessibilityLabel,
  testID,
}: Props) {
  const t = sizeTokens[size];

  const baseContainer: ViewStyle = {
    paddingVertical: t.pv,
    paddingHorizontal: t.ph,
    borderRadius: t.radius,
    borderWidth: 1,
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 32,
  };

  // Variant styles
  const glass = { backgroundColor: colors.card, borderColor: 'rgba(255,255,255,0.12)' } as ViewStyle;
  const outline = { backgroundColor: 'transparent', borderColor: 'rgba(255,255,255,0.25)' } as ViewStyle;
  const filled = { backgroundColor: colors.caffeine, borderColor: 'transparent' } as ViewStyle;

  // Selected overrides
  const selectedGlass = { backgroundColor: 'rgba(255,255,255,0.18)' } as ViewStyle;
  const selectedOutline = { backgroundColor: 'rgba(255,255,255,0.08)' } as ViewStyle;
  const selectedFilled = { backgroundColor: colors.caffeine } as ViewStyle;

  const containerVariant =
    variant === 'filled' ? filled : variant === 'outline' ? outline : glass;
  const containerSelected =
    variant === 'filled' ? selectedFilled : variant === 'outline' ? selectedOutline : selectedGlass;

  const textColor =
    variant === 'filled' || selected ? colors.bg : colors.textPrimary;

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? label}
      testID={testID}
      onPress={onPress}
      onLongPress={onLongPress}
      disabled={disabled}
      style={({ pressed }) => [
        baseContainer,
        containerVariant,
        selected && containerSelected,
        disabled && styles.disabled,
        pressed && !disabled && styles.pressed,
        style,
      ]}
    >
      {iconLeft ? <View style={styles.icon}>{iconLeft}</View> : null}
      <Text style={[{ color: textColor, fontSize: t.font }, styles.text, textStyle]}>{label}</Text>
      {iconRight ? <View style={[styles.icon, styles.iconRight]}>{iconRight}</View> : null}
    </Pressable>
  );
}

const styles = StyleSheet.create({
  pressed: { transform: [{ scale: 0.98 }], opacity: 0.9 },
  disabled: { opacity: 0.5 },
  icon: { marginRight: 8 },
  iconRight: { marginLeft: 8, marginRight: 0 },
  text: {
    // If Inter fonts are loaded:
    // fontFamily: 'Inter-Regular',
    fontWeight: '500',
  },
});