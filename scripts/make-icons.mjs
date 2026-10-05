// Aurora app icons for the calm luxury brand: warm ivory
// and deep ink tiles, a sea-glass wave, and no glow or blur so the mark stays
// crisp at 29 pt. Emits iOS 18+ light/dark/tinted variants as full-bleed
// squares — the OS applies its own corner mask.
//
// Usage (Node 24): node scripts/make-icons.mjs
//
// Xcode owns Aurora/Assets.xcassets. This script overwrites only the PNGs
// listed at the bottom; the catalog Contents.json files are edited by hand.
import sharp from 'sharp';

// Mirrors Aurora/Theme/Palette.swift, `AuroraMark` in Aurora/App/AuroraApp.swift,
// and website/public/aurora-mark.svg.
const WAVE = 'M30 84C46 48 60 48 74 82C82 62 92 54 102 56';
const WAVE_STROKE = 13;
const DOT = { cx: 36, cy: 38, r: 9 };
const CENTER = { x: 66, y: 60 };

const IVORY_50 = '#FFFDF8';
const IVORY_300 = '#EFE9DE';
const INK_TEXT = '#1A1F24';
const INK_950 = '#0B0F13';
const INK_RAISED = '#1A2127';
const IVORY_TEXT = '#F3EFE7';
const SEA_700 = '#1E6B64';
const SEA_500 = '#3E9C90';
const SEA_300 = '#7CC4B8';
const SEA_200 = '#A7DBD1';

const gradient = (id, from, to) => `
    <linearGradient id="${id}" x1="30" y1="84" x2="102" y2="56" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="${from}"/>
      <stop offset="1" stop-color="${to}"/>
    </linearGradient>`;

const defs = `
  <defs>
    <linearGradient id="bgLight" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${IVORY_50}"/>
      <stop offset="1" stop-color="${IVORY_300}"/>
    </linearGradient>
    <linearGradient id="bgDark" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${INK_RAISED}"/>
      <stop offset="1" stop-color="${INK_950}"/>
    </linearGradient>
    ${gradient('waveLight', SEA_500, SEA_700)}
    ${gradient('waveDark', SEA_200, SEA_300)}
    ${gradient('waveTint', '#FFFFFF', '#C8C8C8')}
  </defs>`;

// The glyph spans ~66% of the tile: large enough to read at Settings and
// Spotlight sizes, inside the HIG safe area.
const glyph = (waveFill, dotFill, scale = 0.84) => `
  <g transform="translate(64 64) scale(${scale}) translate(${-CENTER.x} ${-CENTER.y})">
    <path d="${WAVE}" stroke="${waveFill}" stroke-width="${WAVE_STROKE}"
      stroke-linecap="round" stroke-linejoin="round" fill="none"/>
    <circle cx="${DOT.cx}" cy="${DOT.cy}" r="${DOT.r}" fill="${dotFill}"/>
  </g>`;

const icon = (body) =>
  `<svg width="1024" height="1024" viewBox="0 0 128 128" xmlns="http://www.w3.org/2000/svg">${defs}${body}</svg>`;

const lightIcon = icon(`
  <rect width="128" height="128" fill="url(#bgLight)"/>
  ${glyph('url(#waveLight)', INK_TEXT)}`);

const darkIcon = icon(`
  <rect width="128" height="128" fill="url(#bgDark)"/>
  ${glyph('url(#waveDark)', IVORY_TEXT)}`);

// Tinted: grayscale glyph on transparent — the system supplies the backdrop
// and applies the user's tint color.
const tintedIcon = icon(glyph('url(#waveTint)', '#FFFFFF'));

const png = (s) => sharp(Buffer.from(s)).png();
const CATALOG = 'Aurora/Assets.xcassets';
const ICONSET = `${CATALOG}/AppIcon.appiconset`;

// iOS appearance variants (sources)
await png(lightIcon).toFile('assets/icons/ios-light.png');
await png(darkIcon).toFile('assets/icons/ios-dark.png');
await png(tintedIcon).toFile('assets/icons/ios-tinted.png');
// Primary source/store icon — the ivory brand variant
await png(lightIcon).toFile('assets/icon.png');
await png(lightIcon).toFile('assets/icons/app-icon.png');
// Xcode asset catalog
await png(lightIcon).toFile(`${ICONSET}/App-Icon-1024x1024@1x.png`);
await png(darkIcon).toFile(`${ICONSET}/App-Icon-dark-1024x1024@1x.png`);
await png(tintedIcon).toFile(`${ICONSET}/App-Icon-tinted-1024x1024@1x.png`);
