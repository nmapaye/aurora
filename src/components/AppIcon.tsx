import { Ionicons } from '@expo/vector-icons';
import type { SFSymbol } from 'expo-symbols';
import type { ComponentProps } from 'react';

import AppSymbol from '~/components/AppSymbol';

export type AppIconName = keyof typeof Ionicons.glyphMap;

export const appIcons = {
  settings: 'settings-outline',
  summary: 'speedometer-outline',
  summarySelected: 'speedometer',
  sleep: 'moon-outline',
  sleepSelected: 'moon',
  log: 'add-circle-outline',
  logSelected: 'add-circle',
  insights: 'stats-chart-outline',
  insightsSelected: 'stats-chart',
  fallback: 'ellipse-outline',
} as const satisfies Record<string, AppIconName>;

// On iOS every icon renders as its SF Symbol so Aurora matches system chrome.
// Ionicons remain the fallback for other platforms and for unmapped names.
export const sfSymbolFor: Partial<Record<AppIconName, SFSymbol>> = {
  'settings-outline': 'gearshape',
  'speedometer-outline': 'gauge.with.dots.needle.67percent',
  speedometer: 'gauge.with.dots.needle.67percent',
  'moon-outline': 'moon',
  moon: 'moon.fill',
  'add-circle-outline': 'plus.circle',
  'add-circle': 'plus.circle.fill',
  'stats-chart-outline': 'chart.bar',
  'stats-chart': 'chart.bar.fill',
  'ellipse-outline': 'circle',
  'chevron-forward': 'chevron.forward',
  'checkmark-circle': 'checkmark.circle.fill',
  warning: 'exclamationmark.triangle.fill',
  bed: 'bed.double.fill',
  pulse: 'waveform.path.ecg',
  'options-outline': 'slider.horizontal.3',
  'lock-closed-outline': 'lock',
  'create-outline': 'square.and.pencil',
  cafe: 'cup.and.saucer.fill',
  flash: 'bolt.fill',
  add: 'plus',
  remove: 'minus',
  'sunny-outline': 'sun.max',
  'sparkles-outline': 'sparkles',
  'information-circle-outline': 'info.circle',
  'heart-outline': 'heart',
  'alert-circle-outline': 'exclamationmark.circle',
};

type Props = Omit<ComponentProps<typeof Ionicons>, 'name'> & {
  name: AppIconName;
};

export default function AppIcon({ accessible = false, ...props }: Props) {
  const symbol = sfSymbolFor[props.name];
  if (symbol) {
    const { name, size, color, style, ...rest } = props;
    return (
      <AppSymbol
        name={symbol}
        fallback={name}
        size={size}
        tintColor={typeof color === 'string' ? color : undefined}
        style={style as ComponentProps<typeof AppSymbol>['style']}
        accessible={accessible}
        {...rest}
      />
    );
  }
  return <Ionicons accessible={accessible} {...props} />;
}
