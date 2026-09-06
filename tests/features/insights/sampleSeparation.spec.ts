import { getInsightsPresentation } from '~/features/insights/presentation';
import { buildVigilanceSession } from '~/domain/vigilance';
import { localDateKey } from '~/utils/calendar';

const now = new Date(2026, 8, 7, 12).getTime();
const yesterday = new Date(2026, 8, 6, 12).getTime();

it('keeps confirmed zero intake visible when sample drinks exist on the same day', () => {
  const result = getInsightsPresentation(
    [{ id: 'demo:drink', timestamp: now, mg: 160 }],
    [],
    400,
    '7',
    now,
    [localDateKey(now)],
  );
  expect(result.headline).toBe('0 mg/day');
  expect(result.points.at(-1)?.mg).toBe(0);
  expect(result.current.selected).toEqual([]);
  expect(result.isEmpty).toBe(false);
});

it('excludes sample doses and tests from personal comparisons and selected export records', () => {
  const personalTest = buildVigilanceSession({
    id: 'personal:test',
    startedAt: now - 60_000,
    completedAt: now,
    trialResults: [{ outcome: 'valid', reactionMs: 250 }],
    falseStartCount: 0,
  });
  const sampleTest = { ...personalTest, id: 'demo:test', score: 0 };
  const result = getInsightsPresentation(
    [
      { id: 'real:drink', timestamp: yesterday, mg: 80 },
      { id: 'demo:drink', timestamp: now, mg: 160 },
    ],
    [personalTest, sampleTest],
    100,
    '7',
    now,
    [localDateKey(now)],
  );
  expect(result.current.totalMg).toBe(80);
  expect(result.current.averageMg).toBe(40);
  expect(result.current.selected.map((record) => record.id)).toEqual([
    'real:drink',
  ]);
  expect(result.adherence.pct).toBe(100);
  expect(result.vigilance.trendSessions).toEqual([personalTest]);
});
