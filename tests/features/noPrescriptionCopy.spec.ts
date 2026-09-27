import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

// Aurora describes what was recorded and estimates alertness; it never
// prescribes doses, bedtimes, wake times, sleep-cycle schedules, or a
// universal caffeine limit. This guard scans every user-facing source file so
// that kind of copy can't return unnoticed.
const FORBIDDEN =
  /\b(kickstart|top-up|suggested (bedtime|wake)|recommended (dose|bedtime|wake)|90-minute|sleep cycles?|safe (amount|dose|limit)|allowance|mg (left|remaining)|remaining (mg|caffeine)|you should (drink|sleep|stop)|limit adherence)\b/i;

// Explicit disclaimers that negate the idea are allowed.
const ALLOWED = ['It is not a recommended or safe amount.'];

function sourceFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return sourceFiles(path);
    return /\.(ts|tsx)$/.test(name) ? [path] : [];
  });
}

function withoutComments(source: string) {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/(^|[^:])\/\/.*$/gm, '$1');
}

describe('no prescription copy', () => {
  const root = join(__dirname, '..', '..', 'src');

  it.each(sourceFiles(root).map((path) => [path.slice(root.length + 1), path]))(
    '%s prescribes nothing',
    (_name, path) => {
      let text = withoutComments(readFileSync(path, 'utf8'));
      ALLOWED.forEach((sentence) => {
        text = text.split(sentence).join('');
      });
      expect(text).not.toMatch(FORBIDDEN);
    },
  );
});
