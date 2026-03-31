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
  useColorScheme,
} from 'react-native';
import {
  getAppPalette,
  getNeutralButtonColors,
  getPrimaryButtonColors,
  getSecondaryButtonColors,
} from '../theme/colors';

type Variant = 'primary' | 'secondary' | 'plain' | 'outline' | 'glass';

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
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const primary = getPrimaryButtonColors(scheme, disabled || loading);
  const secondary = getSecondaryButtonColors(scheme);
  const neutral = getNeutralButtonColors(scheme);
  const containerVariantStyle =
    variant === 'primary'
      ? {
          backgroundColor: primary.backgroundColor,
          borderColor: 'transparent',
        }
      : variant === 'secondary'
      ? {
          backgroundColor: secondary.backgroundColor,
          borderColor: secondary.borderColor,
        }
      : variant === 'plain'
      ? {
          backgroundColor: 'transparent',
          borderColor: 'transparent',
        }
      : variant === 'outline'
      ? {
          backgroundColor: palette.card,
          borderColor: neutral.borderColor,
        }
      : {
          backgroundColor: palette.cardMuted,
          borderColor: palette.cardBorder,
        };

  const textColor =
    variant === 'primary'
      ? primary.color
      : variant === 'secondary'
      ? secondary.color
      : variant === 'plain'
      ? palette.plainButtonText
      : neutral.color;

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
    paddingVertical: 13,
    paddingHorizontal: 16,
    borderRadius: 14,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: 44,
  },
  pressed: { transform: [{ scale: 0.985 }], opacity: 0.92 },
  disabled: { opacity: 0.5 },
  content: { flexDirection: 'row', alignItems: 'center', justifyContent: 'center' },
  icon: { marginRight: 8 },
  iconRight: { marginLeft: 8, marginRight: 0 },
  spinner: { marginLeft: 8 },
  text: {
    fontSize: 16,
    lineHeight: 20,
    fontWeight: '600', // If you loaded Inter fonts, you can use: fontFamily: 'Inter-SemiBold'
  },
});
