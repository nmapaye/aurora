import {
  buildNativeSnapshot,
  parseNativeAction,
  resolveNativeDraft,
} from '~/features/native/model';
import { useStore } from '~/state/store';
import { localDateKey } from '~/utils/calendar';

const now = new Date(2026, 8, 7, 12).getTime();
function state() {
  const s = useStore.getState();
  return {
    ...s,
    doses: [],
    onboarding: {
      ...s.onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  };
}
it('distinguishes missing daily intake from modeled carryover and filters sample/future doses', () => {
  const s = state();
  const snapshot = buildNativeSnapshot(
    {
      ...s,
      doses: [
        { id: 'old', timestamp: now - 24 * 3600000, mg: 100 },
        { id: 'demo:today', timestamp: now, mg: 500 },
        { id: 'future', timestamp: now + 3600000, mg: 500 },
      ],
    },
    now,
  );
  expect(snapshot.loggedMg).toBeNull();
  expect(snapshot.activeMg).toBeCloseTo(
    100 * Math.pow(0.5, 24 / s.prefs.halfLife),
  );
  expect(snapshot.expiresAt).toBe(now + 15 * 60000);
  expect(
    buildNativeSnapshot(
      { ...s, caffeine: { ...s.caffeine, zeroDays: [localDateKey(now)] } },
      now,
    ).loggedMg,
  ).toBe(0);
});
it('caps expiry at local midnight and chooses the next cutoff after the current one', () => {
  const s = state(),
    late = new Date(2026, 8, 7, 23, 59, 30).getTime();
  const snapshot = buildNativeSnapshot(
    { ...s, prefs: { ...s.prefs, cutoffHour: 16 } },
    late,
  );
  expect(snapshot.expiresAt).toBe(new Date(2026, 8, 8).getTime());
  expect(snapshot.cutoff).toBe(new Date(2026, 8, 8, 16).getTime());
  expect(snapshot.showLockValues).toBe(false);
});
it.each([
  'aurora://user@native/log?amount=95',
  'aurora://native:80/log?amount=95',
  'aurora://native/log?amount=95#fragment',
  'aurora://native/log?amount=095',
  'aurora://native/log?amount=1e2',
  'aurora://native/log?amount=%2B95',
  'aurora://native/log?drinkId=personal%3Atea&drinkId=personal%3Acoffee',
  'aurora://native/log?drinkId=%00',
  'aurora://native/nap?amount=95',
  'aurora://native/log?drinkId=%E0%A4%A',
])('rejects ambiguous or malformed action %s', (url) =>
  expect(parseNativeAction(url)).toBeNull(),
);
it('resolves current active library values without overwriting an existing draft', () => {
  const s = state();
  const draft = {
    mg: '111',
    source: 'Unfinished',
    note: 'Keep this',
    timestamp: now - 60000,
  };
  const caffeine = {
    ...s.caffeine,
    draft,
    drinks: [
      { id: 'personal:tea', label: 'Updated tea', mg: 80, archived: false },
    ],
  };
  const action = parseNativeAction(
    'aurora://native/log?drinkId=personal%3Atea',
  )!;
  expect(resolveNativeDraft(action, caffeine, now)).toEqual({
    mg: '80',
    source: 'Updated tea',
    note: '',
    timestamp: now,
  });
  expect(caffeine.draft).toBe(draft);
  expect(
    resolveNativeDraft(
      action,
      { ...caffeine, drinks: [{ ...caffeine.drinks[0], archived: true }] },
      now,
    ),
  ).toBeNull();
});
