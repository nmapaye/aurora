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

// No style sets a fixed lineHeight: the natural line box grows with Dynamic
// Type, so scaled glyphs are never clipped by a line sized for the default.
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

// iOS reaches this scale at the largest standard text size. Past it, compact
// side-by-side rows stack so their text wraps at full width instead of
// squeezing into a narrow column.
export const LARGE_TEXT_FONT_SCALE = 1.35;

export function isLargeText(fontScale: number) {
  return fontScale > LARGE_TEXT_FONT_SCALE;
}

// Small uppercase label above grouped content.
export const eyebrowText = {
  ...typeRamp.footnote,
  fontWeight: '600',
  letterSpacing: 0.6,
  textTransform: 'uppercase',
} satisfies TextStyle;

export const borders = {
  hairline: 1,
  selected: 1.5,
} as const;

// Motion is restrained: short fades and small offsets, never bounce. Under
// Reduce Motion, callers use `reduced` and drop translation and scale.
export const motion = {
  duration: {
    quick: 160,
    standard: 240,
    gentle: 360,
    reduced: 120,
  },
  pressedOpacity: 0.7,
  disabledOpacity: 0.45,
  pressedScale: 0.98,
  entranceOffset: 8,
} as const;

export function getMotionDuration(
  speed: Exclude<keyof typeof motion.duration, 'reduced'>,
  reduceMotion: boolean,
) {
  return reduceMotion ? motion.duration.reduced : motion.duration[speed];
}

// Light surfaces lift with a soft warm shadow; dark surfaces rely on borders.
export const elevation = {
  none: {},
  raised: {
    shadowColor: '#3A2F1E',
    shadowOpacity: 0.06,
    shadowRadius: 12,
    shadowOffset: { width: 0, height: 4 },
  },
} as const;
