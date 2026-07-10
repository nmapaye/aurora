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
import {
  getAppPalette,
  getPrimaryButtonColors,
  getSecondaryButtonColors,
} from '../theme/colors';
import useAppScheme from '~/hooks/useAppScheme';
import { controlSizes, radii, spacing, typeRamp } from '~/theme/tokens';

type Variant = 'primary' | 'tinted' | 'plain';
type ButtonRole = 'default' | 'destructive';

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
  role?: ButtonRole;
};

export default function Button({
  title,
  onPress,
  variant = 'tinted',
  disabled = false,
  loading = false,
  style,
  textStyle,
  iconLeft,
  iconRight,
  accessibilityLabel,
  testID,
  role = 'default',
}: Props) {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const primary = getPrimaryButtonColors(scheme, disabled || loading);
  const secondary = getSecondaryButtonColors(scheme);
  const destructive = role === 'destructive';
  const containerVariantStyle =
    variant === 'primary'
      ? {
          backgroundColor: destructive
            ? palette.destructive
            : primary.backgroundColor,
          borderColor: 'transparent',
        }
      : variant === 'tinted'
        ? {
            backgroundColor: destructive
              ? palette.statusErrorBackground
              : secondary.backgroundColor,
            borderColor: 'transparent',
          }
        : {
            backgroundColor: 'transparent',
            borderColor: 'transparent',
          };

  const textColor =
    destructive && variant === 'primary'
      ? palette.onDestructive
      : destructive
        ? palette.destructive
        : variant === 'primary'
          ? primary.color
          : variant === 'tinted'
            ? secondary.color
            : palette.plainButtonText;

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
        <Text style={[styles.text, { color: textColor }, textStyle]}>
          {title}
        </Text>
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
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.md,
    borderRadius: radii.control,
    borderWidth: 1,
    alignItems: 'center',
    justifyContent: 'center',
    minHeight: controlSizes.minimumTouchTarget,
  },
  pressed: { opacity: 0.72 },
  disabled: { opacity: 0.5 },
  content: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
  },
  icon: { marginRight: spacing.xs },
  iconRight: { marginLeft: spacing.xs, marginRight: 0 },
  spinner: { marginLeft: spacing.xs },
  text: {
    ...typeRamp.headline,
  },
});
