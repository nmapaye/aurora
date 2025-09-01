/****
 * Postinstall sanity script
 * - Ensures valid PNG placeholders exist (prevents Metro "unsupported file type")
 * - Ensures root App.tsx exists (Expo -> src/App bridge)
 *
 * Run manually: npx ts-node scripts/postinstall.ts
 */

import fs from 'fs';
import path from 'path';

const projectRoot = process.cwd();

const PNG_SIGNATURE = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
// 1x1 transparent PNG
const ONE_BY_ONE_PNG_BASE64 =
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+XnSMAAAAASUVORK5CYII=';

const pngTargets = [
  'assets/icons/app-icon.png',
  'assets/icons/splash.png',
  'assets/images/aurora-fallback.png',
];

function r(p: string) {
  return path.resolve(projectRoot, p);
}

async function ensureDir(filePath: string) {
  await fs.promises.mkdir(path.dirname(filePath), { recursive: true });
}

async function ensureValidPng(relPath: string) {
  const filePath = r(relPath);
  try {
    const data = await fs.promises.readFile(filePath);
    if (data.length >= 8 && data.subarray(0, 8).equals(PNG_SIGNATURE)) {
      return { file: relPath, created: false };
    }
    // Not a PNG; overwrite
    await fs.promises.writeFile(filePath, Buffer.from(ONE_BY_ONE_PNG_BASE64, 'base64'));
    return { file: relPath, created: true, reason: 'replaced invalid placeholder' };
  } catch {
    // Create directories and write new PNG
    await ensureDir(filePath);
    await fs.promises.writeFile(filePath, Buffer.from(ONE_BY_ONE_PNG_BASE64, 'base64'));
    return { file: relPath, created: true, reason: 'created missing file' };
  }
}

async function ensureAppEntry() {
  const rel = 'App.tsx';
  const filePath = r(rel);
  const content = `export { default } from './src/App';\n`;
  try {
    await fs.promises.access(filePath, fs.constants.F_OK);
    // exists; do nothing
    return { file: rel, created: false };
  } catch {
    await fs.promises.writeFile(filePath, content, 'utf8');
    return { file: rel, created: true };
  }
}

(async () => {
  const pngResults = await Promise.all(pngTargets.map(ensureValidPng));
  const appEntry = await ensureAppEntry();

  const created = pngResults.filter((r) => r.created);
  if (created.length) {
    console.log(
      `[postinstall] Wrote PNG placeholders:\n` +
        created.map((r) => `  - ${r.file}${r.reason ? ` (${r.reason})` : ''}`).join('\n'),
    );
  } else {
    console.log('[postinstall] PNG placeholders OK.');
  }

  if (appEntry.created) {
    console.log('[postinstall] Created App.tsx entry.');
  } else {
    console.log('[postinstall] App.tsx entry OK.');
  }
})().catch((e) => {
  console.error('[postinstall] Error:', e);
  process.exit(1);
});
