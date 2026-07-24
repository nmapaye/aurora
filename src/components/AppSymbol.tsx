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

  return (
    <SymbolView
      name={name}
      size={size}
      tintColor={tintColor}
      style={[{ width: size, height: size }, style]}
      accessible={isAccessible}
      {...props}
    />
  );
}
