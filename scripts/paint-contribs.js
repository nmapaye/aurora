#!/usr/bin/env node
/**
 * Paint GitHub contribution graph using backdated commits.
 * - Consumes the Starry Night 7x52 plan from scripts/starry-night-grid.js plan
 * - Creates commits dated per-day with configurable commit counts per intensity level
 *
 * Usage:
 *   node scripts/paint-contribs.js                 # dry-run, prints summary
 *   node scripts/paint-contribs.js --year=2025     # dry-run for a specific year
 *   node scripts/paint-contribs.js --yes           # DO the commits in current repo
 *   node scripts/paint-contribs.js --file=contribs/starry.txt --yes
 *
 * Notes:
 * - This will create many commits; consider using a dedicated repo.
 * - Push to any public repo to affect your GitHub graph.
 */
const { execSync, spawnSync } = require('node:child_process');
const { existsSync, mkdirSync, appendFileSync } = require('node:fs');
const { dirname } = require('node:path');

function parseArgs() {
  const args = process.argv.slice(2);
  const out = { yes: false, year: undefined, file: 'contribs/starry.txt' };
  for (const a of args) {
    if (a === '--yes' || a === '-y') out.yes = true;
    else if (a.startsWith('--year=')) out.year = parseInt(a.split('=')[1], 10);
    else if (a.startsWith('--file=')) out.file = a.split('=')[1];
  }
  if (!out.year) out.year = parseInt(process.env.YEAR || `${new Date().getUTCFullYear()}`, 10);
  return out;
}

function run(cmd, opts = {}) {
  return execSync(cmd, { stdio: 'pipe', encoding: 'utf8', ...opts });
}

function getPlan(year) {
  const res = spawnSync(process.execPath, ['scripts/starry-night-grid.js', 'plan'], { env: { ...process.env, YEAR: String(year) }, encoding: 'utf8' });
  if (res.status !== 0) {
    console.error('Failed to generate plan:', res.stderr || res.stdout);
    process.exit(1);
  }
  return JSON.parse(res.stdout);
}

function ensureRepo() {
  try { run('git rev-parse --is-inside-work-tree'); }
  catch { console.error('Not inside a git repository. Run from a git repo root.'); process.exit(2); }
}

function main() {
  const opts = parseArgs();
  ensureRepo();
  const plan = getPlan(opts.year);
  const items = plan.plan || [];
  const totalCommits = items.reduce((a, p) => a + (p.commits || 0), 0);
  console.log(`Plan year ${plan.year}: ${items.length} days, ~${totalCommits} commits`);
  console.log(`Target file: ${opts.file}`);
  if (!opts.yes) {
    console.log('Dry-run. Pass --yes to execute. Sample:');
    console.log(items.slice(0, 5));
    return;
  }

  // Prepare target file
  const dir = dirname(opts.file);
  if (!existsSync(dir)) mkdirSync(dir, { recursive: true });
  if (!existsSync(opts.file)) appendFileSync(opts.file, '# Starry Night contributions\n');

  // Commit loop
  for (const it of items) {
    const { date, commits } = it;
    for (let i = 0; i < commits; i++) {
      // Stagger times within the day to avoid identical timestamps
      const hh = 12 + Math.floor(i / 3); // spread from noon
      const mm = (i * 7) % 60;
      const ss = (i * 13) % 60;
      const iso = `${date}T${String(hh).padStart(2, '0')}:${String(mm).padStart(2, '0')}:${String(ss).padStart(2, '0')}Z`;
      appendFileSync(opts.file, `${date} #${i + 1}\n`);
      try {
        run(`git add -- '${opts.file}'`);
        run(`git commit -m "chore(contribs): paint ${date} (${i + 1}/${commits})"`, {
          env: { ...process.env, GIT_AUTHOR_DATE: iso, GIT_COMMITTER_DATE: iso },
        });
      } catch (e) {
        console.error('Commit failed at', date, 'idx', i + 1, e?.message || e);
        process.exit(3);
      }
    }
  }
  console.log('Done creating commits. Push to your desired remote/branch to update the GitHub graph.');
}

main();

