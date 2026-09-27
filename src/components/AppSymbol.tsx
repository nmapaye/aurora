import { Ionicons } from '@expo/vector-icons';
import { SymbolView, type SFSymbol, type SymbolViewProps } from 'expo-symbols';
import type { ComponentProps } from 'react';
import { Platform } from 'react-native';

export type AppSymbolName = SFSymbol;
export type AppSymbolFallbackName = ComponentProps<typeof Ionicons>['name'];

type Props = Omit<SymbolViewProps, 'name' | 'fallback' | 'size' | 'tintColor'> & {
  name: AppSymbolName;
  fallback: AppSymbolFallbackName;
  size?: number;
  tintColor?: SymbolViewProps['tintColor'];
};

export default function AppSymbol({
  name,
  fallback,
  size = 24,
  tintColor,
  style,
  accessible,
  ...props
}: Props) {
  const isAccessible = accessible ?? Boolean(props.accessibilityLabel);

  if (Platform.OS !== 'ios') {
    return (
      <Ionicons
        name={fallback}
        size={size}
        color={tintColor}
        style={style as ComponentProps<typeof Ionicons>['style']}
        accessible={isAccessible}
        {...props}
      />
    );
  }

  // A decorative symbol must be hidden, not just non-focusable: otherwise its
  // built-in description ("love" for heart) is folded into the parent's
  // VoiceOver label.
  return (
    <SymbolView
      name={name}
      size={size}
      tintColor={tintColor}
      style={[{ width: size, height: size }, style]}
      accessible={isAccessible}
      accessibilityElementsHidden={!isAccessible}
      importantForAccessibility={isAccessible ? 'auto' : 'no-hide-descendants'}
      {...props}
    />
  );
}
