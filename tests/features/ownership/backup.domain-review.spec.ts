import { createBackup, parseBackup } from '~/features/ownership/backup';
import { useStore } from '~/state/store';
import { buildVigilanceSession } from '~/domain/vigilance';

const now = 1788825600000;
const backup = () => createBackup(useStore.getState(), now);

test('backup import rejects an unknown time zone before it can crash forecasts', () => {
  const value = backup();
  value.data.prefs.tz = 'Aurora/Unknown';
  expect(() => parseBackup(JSON.stringify(value))).toThrow();
});

test('backup import preserves valid explicit time zones', () => {
  const value = backup();
  value.data.prefs.tz = 'America/New_York';
  expect(parseBackup(JSON.stringify(value)).data.prefs.tz).toBe('America/New_York');
});

test.each([
  ['reaction count exceeds trial count', { validReactionCount: 2 }],
  ['lapse count exceeds trial count', { lapseCount: 2 }],
  ['duration disagrees with timestamps', { durationMs: 1 }],
  ['missing reaction median despite a valid reaction', { medianReactionMs: null }],
])('backup import rejects inconsistent vigilance metrics: %s', (_description, patch) => {
  const value = backup();
  value.data.vigilanceSessions = [{
    ...buildVigilanceSession({
      id: 'vigilance:review',
      startedAt: now - 60000,
      completedAt: now,
      trialResults: [{ outcome: 'valid', reactionMs: 250 }],
      falseStartCount: 0,
    }),
    ...patch,
  }];
  expect(() => parseBackup(JSON.stringify(value))).toThrow();
});
