import React from 'react';
import {
  Pressable,
  Text,
  View,
  ActivityIndicator,
  StyleSheet,
  StyleProp,
  ViewStyle,
  TextStyle,
} from 'react-native';
import { colors } from '../theme/colors';

type Variant = 'primary' | 'glass' | 'outline';

type Props = {
  title: string;
  onPress?: () => void;
  variant?: Variant;
  disabled?: boolean;
  loading?: boolean;
  style?: StyleProp<ViewStyle>;
  textStyle?: StyleProp<TextStyle>;
  iconLeft?: React.ReactNode;
  iconRight?: React.ReactNode;
  accessibilityLabel?: string;
  testID?: string;
};

export default function Button({
  title,
  onPress,
  variant = 'glass',
  disabled = false,
  loading = false,
  style,
  textStyle,
  iconLeft,
  iconRight,
  accessibilityLabel,
  testID,
}: Props) {
  const containerVariantStyle =
    variant === 'primary'
      ? { backgroundColor: colors.caffeine, borderColor: 'transparent' }
      : variant === 'outline'
      ? { backgroundColor: 'transparent', borderColor: 'rgba(255,255,255,0.25)' }
      : { backgroundColor: colors.card, borderColor: 'rgba(255,255,255,0.12)' };

  const textColor = variant === 'primary' ? colors.bg : colors.textPrimary;

  return (
    <Pressable
      accessibilityRole="button"
      accessibilityLabel={accessibilityLabel ?? title}
      testID={testID}
      disabled={disabled || loading}
      onPress={onPress}
      style={({ pressed }) => [
        styles.base,
        containerVariantStyle,
        (disabled || loading) && styles.disabled,
        pressed && styles.pressed,
        style,
      ]}
    >
      <View style={styles.content}>
        {iconLeft ? <View style={styles.icon}>{iconLeft}</View> : null}
        <Text style={[styles.text, { color: textColor }, textStyle]}>{title}</Text>
        {loading ? (
          <ActivityIndicator size="small" style={styles.spinner} />
        ) : iconRight ? (
          <View style={[styles.icon, styles.iconRight]}>{iconRight}</View>
        ) : null}
      </View>
    </Pressable>
  );
}

const styles = StyleSheet.create({
  base: {
    paddingVertical: 12,
    paddingHorizontal: 16,
    borderRadius: 12,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 44,
  },
  pressed: { transform: [{ scale: 0.98 }], opacity: 0.9 },
  disabled: { opacity: 0.5 },
  content: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center' },
  icon: { marginRight: 8 },
  iconRight: { marginLeft: 8, marginRight: 0 },
  spinner: { marginLeft: 8 },
  text: {
    fontSize: 16,
    fontWeight: '600', // If you loaded Inter fonts, you can use: fontFamily: 'Inter-SemiBold'
  },
});