import { Ionicons } from '@expo/vector-icons';
import type { ComponentProps } from 'react';

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

type Props = Omit<ComponentProps<typeof Ionicons>, 'name'> & {
  name: AppIconName;
};

export default function AppIcon({ accessible = false, ...props }: Props) {
  return <Ionicons accessible={accessible} {...props} />;
}
