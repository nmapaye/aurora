

/**
 * Icon & splash generator
 * Usage:
 *   npx ts-node scripts/generate-icons.ts [sourcePath]
 *   # or compile to JS and run with node
 *
 * Requires: sharp (dev dependency)
 *   npm i -D sharp
 */

import fs from 'fs';
import path from 'path';

async function dynamicImportSharp() {
  try {
    // Use eval(require) to avoid TypeScript module resolution during type-check
    // eslint-disable-next-line no-eval
    const rq: any = eval('require');
    const mod = rq('sharp');
    return (mod && mod.default) ? mod.default : mod;
  } catch (err) {
    console.error('Missing peer dependency: sharp');
    console.error('Install with: npm i -D sharp');
    process.exit(1);
  }
}

const CWD = process.cwd();
const SRC = process.argv[2] ?? 'assets/icons/source.png';
const BG = process.env.ICON_BG ?? '#0B1020';
const SPLASH_SIZE = Number(process.env.SPLASH_SIZE ?? 2000);

const outputs = [
  { file: 'assets/icons/app-icon.png', size: 1024 },   // Expo: app.json "icon"
  { file: 'assets/icons/adaptive-icon.png', size: 432 }, // Expo Android adaptive foreground
  { file: 'assets/icons/marketing-512.png', size: 512 },
  { file: 'assets/icons/marketing-256.png', size: 256 },
];

function resolve(p: string) { return path.resolve(CWD, p); }

async function ensureDir(filePath: string) {
  await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
}

function parseHexColor(hex: string) {
  const clean = hex.replace('#','').trim();
  const n = parseInt(clean.length === 3
    ? clean.split('').map(c=>c+c).join('')
    : clean, 16);
  return { r: (n>>16)&255, g: (n>>8)&255, b: n&255, alpha: 1 };
}

async function main() {
  const sharp = await dynamicImportSharp();
  const srcPath = resolve(SRC);
  if (!fs.existsSync(srcPath)) {
    console.error(`Source not found: ${srcPath}`);
    process.exit(1);
  }

  // Make sure output dirs exist
  for (const o of outputs) await ensureDir(resolve(o.file));
  await ensureDir(resolve('assets/icons/splash.png'));

  const bg = parseHexColor(BG);

  // Generate square icons (contain to square with background)
  await Promise.all(outputs.map(async (o) => {
    await sharp(srcPath)
      .resize(o.size, o.size, { fit: 'contain', background: bg })
      .png()
      .toFile(resolve(o.file));
  }));

  // Generate splash (cover into large square so Expo can scale)
  await sharp(srcPath)
    .resize(SPLASH_SIZE, SPLASH_SIZE, { fit: 'cover' })
    .png()
    .toFile(resolve('assets/icons/splash.png'));

  console.log(`Generated:`);
  for (const o of outputs) console.log(` - ${o.file} (${o.size}x${o.size})`);
  console.log(` - assets/icons/splash.png (${SPLASH_SIZE}x${SPLASH_SIZE})`);
}

main().catch((e) => { console.error(e); process.exit(1); });
