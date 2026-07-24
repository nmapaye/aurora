import type { AppSymbolName } from '~/components/AppSymbol';

export type CaffeinePreset = {
  id: 'espresso' | 'drip' | 'matcha' | 'energy';
  label: string;
  mg: number;
  symbol: AppSymbolName;
};

export const CAFFEINE_PRESETS: readonly CaffeinePreset[] = [
  { id: 'espresso', label: 'Espresso', mg: 60, symbol: 'cup.and.saucer.fill' },
  { id: 'drip', label: 'Drip', mg: 95, symbol: 'cup.and.saucer.fill' },
  { id: 'matcha', label: 'Matcha', mg: 70, symbol: 'leaf.fill' },
  { id: 'energy', label: 'Energy', mg: 160, symbol: 'bolt.fill' },
];
