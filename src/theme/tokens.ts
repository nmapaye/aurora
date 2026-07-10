import type { TextStyle } from 'react-native';

export const spacing = {
  xxs: 4,
  xs: 8,
  sm: 12,
  md: 16,
  lg: 20,
  xl: 24,
  xxl: 32,
} as const;

export const radii = {
  control: 12,
  card: 16,
  hero: 24,
  capsule: 999,
} as const;

export const typeRamp = {
  largeTitle: { fontSize: 34, fontWeight: '700' },
  title1: { fontSize: 28, fontWeight: '700' },
  title3: { fontSize: 20, fontWeight: '600' },
  headline: { fontSize: 17, fontWeight: '600' },
  body: { fontSize: 17, fontWeight: '400' },
  subheadline: { fontSize: 15, fontWeight: '400' },
  footnote: { fontSize: 13, fontWeight: '400' },
  caption: { fontSize: 12, fontWeight: '400' },
} satisfies Record<string, TextStyle>;

export const numericText = {
  ...typeRamp.title1,
  fontVariant: ['tabular-nums'],
} satisfies TextStyle;

export const iconSizes = {
  inline: 17,
  row: 20,
  button: 24,
  hero: 40,
} as const;

export const controlSizes = {
  minimumTouchTarget: 44,
  inputHeight: 48,
} as const;

export const layout = {
  screenGutter: spacing.md,
  wideScreenGutter: spacing.lg,
  contentMaxWidth: 600,
  wideContentMaxWidth: 1220,
  sectionGap: spacing.xl,
  cardGap: spacing.sm,
  cardPadding: spacing.md,
} as const;

export const fontScaling = {
  body: 1.6,
  hero: 1.3,
} as const;
