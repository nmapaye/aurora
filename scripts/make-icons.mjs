// Aurora app icons in the iOS design language: soft vertical background
// gradient, gradient glyph with subtle glow/shadow depth, and iOS 18+
// light/dark/tinted appearance variants. Full-bleed squares — the OS
// applies its own corner mask.
import sharp from 'sharp';

// The aurora-wave mark from website/public/aurora-mark.svg.
// Path spans x 28..108, y 38..91; optical center ≈ (67, 62).
const WAVE = 'M28 83C47.5 43 62.5 43 79 83C89 58 97 50 108 53';

const defs = `
  <defs>
    <linearGradient id="bgDark" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1B2647"/>
      <stop offset="1" stop-color="#0A0E1C"/>
    </linearGradient>
    <linearGradient id="bgLight" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#E7EAF3"/>
    </linearGradient>
    <linearGradient id="wave" x1="28" y1="83" x2="108" y2="53" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#67B6FF"/>
      <stop offset="1" stop-color="#0A84FF"/>
    </linearGradient>
    <linearGradient id="waveTint" x1="28" y1="83" x2="108" y2="53" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#ABABAB"/>
    </linearGradient>
    <radialGradient id="glowAurora" cx="0.5" cy="0.38" r="0.55">
      <stop offset="0" stop-color="#3FD8C7" stop-opacity="0.22"/>
      <stop offset="0.6" stop-color="#0A84FF" stop-opacity="0.10"/>
      <stop offset="1" stop-color="#0A84FF" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="dot" cx="0.35" cy="0.3" r="1">
      <stop offset="0" stop-color="#FFFFFF"/>
      <stop offset="1" stop-color="#D7DEF0"/>
    </radialGradient>
    <filter id="soft" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="3.2"/>
    </filter>
  </defs>`;

// scale(0.72) around the mark's optical center keeps the glyph at ~57%
// of the canvas, per HIG glyph sizing.
const glyph = (waveFill, dotFill, { glow = null, shadow = null } = {}) => `
  <g transform="translate(64 64) scale(0.72) translate(-67 -62)">
    ${glow ? `<path d="${WAVE}" stroke="${glow}" stroke-opacity="0.55" stroke-width="12"
        stroke-linecap="round" stroke-linejoin="round" fill="none" filter="url(#soft)"/>` : ''}
    ${shadow ? `<path d="${WAVE}" transform="translate(0 3)" stroke="${shadow}" stroke-opacity="0.28"
        stroke-width="10" stroke-linecap="round" stroke-linejoin="round" fill="none" filter="url(#soft)"/>` : ''}
    <path d="${WAVE}" stroke="${waveFill}" stroke-width="10"
      stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    <circle cx="38" cy="38" r="8" fill="${dotFill}"/>
  </g>`;

const svg = (body) =>
  `<svg width="1024" height="1024" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">${defs}${body}</svg>`;

const darkIcon = svg(`
  <rect width="128" height="128" fill="url(#bgDark)"/>
  <rect width="128" height="128" fill="url(#glowAurora)"/>
  ${glyph('url(#wave)', 'url(#dot)', { glow: '#0A84FF' })}`);

const lightIcon = svg(`
  <rect width="128" height="128" fill="url(#bgLight)"/>
  ${glyph('url(#wave)', '#1C1C2E', { shadow: '#0A3D7A' })}`);

// Tinted: grayscale glyph on transparent — the system supplies the
// backdrop and applies the user's tint color.
const tintedIcon = svg(glyph('url(#waveTint)', '#FFFFFF'));

const splashSvg = `<svg width="1242" height="2436" viewBox="0 0 1242 2436" xmlns="http://www.w3.org/2000/svg">
  <defs>
    <linearGradient id="bgSplash" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#131C36"/>
      <stop offset="1" stop-color="#0A0E1C"/>
    </linearGradient>
    <radialGradient id="glowSplash" cx="0.5" cy="0.46" r="0.5">
      <stop offset="0" stop-color="#3FD8C7" stop-opacity="0.18"/>
      <stop offset="0.6" stop-color="#0A84FF" stop-opacity="0.08"/>
      <stop offset="1" stop-color="#0A84FF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="waveS" x1="28" y1="83" x2="108" y2="53" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#67B6FF"/>
      <stop offset="1" stop-color="#0A84FF"/>
    </linearGradient>
    <filter id="softS" x="-40%" y="-40%" width="180%" height="180%">
      <feGaussianBlur stdDeviation="3.2"/>
    </filter>
  </defs>
  <rect width="1242" height="2436" fill="url(#bgSplash)"/>
  <rect width="1242" height="2436" fill="url(#glowSplash)"/>
  <g transform="translate(621 1218) scale(3.4) translate(-67 -62)">
    <path d="${WAVE}" stroke="#0A84FF" stroke-opacity="0.55" stroke-width="12"
      stroke-linecap="round" stroke-linejoin="round" fill="none" filter="url(#softS)"/>
    <path d="${WAVE}" stroke="url(#waveS)" stroke-width="10"
      stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    <circle cx="38" cy="38" r="8" fill="#F2F2F7"/>
  </g>
</svg>`;

const png = (s) => sharp(Buffer.from(s)).png();

// iOS appearance variants
await png(darkIcon).toFile('assets/icons/ios-dark.png');
await png(lightIcon).toFile('assets/icons/ios-light.png');
await png(tintedIcon).toFile('assets/icons/ios-tinted.png');
// Primary icon (Android launcher, stores, fallback) — dark brand variant
await png(darkIcon).toFile('assets/icon.png');
await png(darkIcon).toFile('assets/icons/app-icon.png');
await png(darkIcon).resize(432, 432).toFile('assets/icons/adaptive-icon.png');
// Splash
await png(splashSvg).toFile('assets/splash.png');
await png(splashSvg).toFile('assets/icons/splash.png');

console.log('done');
