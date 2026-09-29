// Raw Aurora brand color primitives. Screens should read semantic roles from
// `getAppPalette` instead of these values. `scripts/make-icons.mjs` and
// `website/public/aurora-mark.svg` mirror the ivory, ink, and sea-glass values.

export const ivory = {
  50: '#FFFDF8',
  100: '#FBF8F2',
  200: '#F6F2EA',
  300: '#EFE9DE',
  400: '#E6DFD2',
  500: '#D9D1C2',
} as const;

export const ink = {
  950: '#0B0F13',
  900: '#0F1317',
  850: '#151A1F',
  800: '#1C2227',
  700: '#262D33',
  600: '#343C43',
  500: '#6E757C',
  400: '#8A9097',
  300: '#AEB3B8',
  100: '#F3EFE7',
} as const;

export const seaGlass = {
  900: '#123F3A',
  800: '#17332F',
  700: '#1E6B64',
  600: '#2A7C73',
  500: '#3E9C90',
  300: '#7CC4B8',
  200: '#A7DBD1',
  100: '#E1EEEA',
} as const;

export const brandColors = {
  ivory: ivory[200],
  ink: ink[900],
  seaGlass: seaGlass[700],
  seaGlassLight: seaGlass[300],
} as const;

// The Aurora wave mark in a 128-unit square. The ribbon crests once and then
// rises; the dot is the sun or moon above the horizon.
export const auroraMark = {
  viewBox: 128,
  wavePath: 'M30 84C46 48 60 48 74 82C82 62 92 54 102 56',
  waveStrokeWidth: 13,
  dot: { cx: 36, cy: 38, r: 9 },
  // Center of the stroked glyph bounds, used to scale the mark in place.
  opticalCenter: { x: 66, y: 60 },
} as const;

// A wide horizon that stretches the mark's crest-then-rise rhythm into a quiet
// backdrop for first-run setup. Ribbons repeat below the lead line and fade.
export const auroraHorizon = {
  width: 320,
  height: 104,
  wavePath: 'M8 70C38 32 66 32 96 68C120 48 146 40 176 42C220 45 262 36 312 20',
  ribbonOffset: 12,
  ribbonOpacities: [0.9, 0.34, 0.16],
  strokeWidth: 3,
  dot: { cx: 42, cy: 20, r: 6 },
} as const;
