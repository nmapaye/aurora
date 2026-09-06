import { validateCustomDoseDraft } from '~/features/caffeine/logging';
import { normalizeCaffeine } from '~/features/caffeine/upgrades';
import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';
import { localDateKey } from '~/utils/calendar';

const now = new Date(2026, 8, 7, 12).getTime();
const yesterday = new Date(2026, 8, 6, 12).getTime();
const dose = { id: 'review:dose', timestamp: now, mg: 90, source: 'Coffee' };
const draft = { mg: '90', timestamp: now, source: 'Coffee', note: 'Keep this' };

beforeEach(() => {
  jest.spyOn(Date, 'now').mockReturnValue(now);
  useStore.setState({
    doses: [],
    doseUndo: null,
    caffeine: { drinks: [], favoriteIds: [], draft: null, zeroDays: [] },
  });
});
afterEach(() => jest.restoreAllMocks());

it('rejects a finite timestamp that cannot be represented by Date', () => {
  const invalid = { ...draft, timestamp: -1e100 };
  expect(normalizeCaffeine({ draft: invalid }).draft).toBeNull();
  expect(validateCustomDoseDraft(invalid, now).valid).toBe(false);
});

it('preserves unfinished amount and source text during hydration', async () => {
  const unfinished = { ...draft, mg: '', source: 'My unfinished drink' };
  jsonStringStorage.setItem(
    'aurora/state',
    JSON.stringify({ version: 7, state: { caffeine: { draft: unfinished } } }),
  );
  await useStore.persist.rehydrate();
  expect(useStore.getState().caffeine.draft).toEqual(unfinished);
});

it.each([null, true, '2026-09-07', '0'])(
  'rejects coercible nonnumeric timestamps during hydration: %p',
  async (timestamp) => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        version: 7,
        state: { caffeine: { draft: { ...draft, timestamp } } },
      }),
    );
    await useStore.persist.rehydrate();
    expect(useStore.getState().caffeine.draft).toBeNull();
  },
);

it('normalizes malformed caffeine collections without losing existing doses', async () => {
  jsonStringStorage.setItem(
    'aurora/state',
    JSON.stringify({
      version: 7,
      state: {
        doses: [dose],
        caffeine: {
          drinks: [null, {}, { id: 'personal:bad', label: '', mg: -10 }],
          favoriteIds: ['unknown', null],
          zeroDays: ['2026-02-30', 123, null],
          draft: { ...draft, timestamp: -1e100 },
        },
      },
    }),
  );
  await useStore.persist.rehydrate();
  expect(useStore.getState().doses).toEqual([dose]);
  expect(useStore.getState().caffeine).toEqual({
    drinks: [],
    favoriteIds: [],
    zeroDays: [],
    draft: null,
  });
});

it('undoes an addition and restores its caffeine-free marker', () => {
  useStore.getState().markCaffeineFree(now);
  useStore.getState().addDose(dose);
  useStore.getState().undoDoseChange(now + 1);
  expect(useStore.getState().doses).toEqual([]);
  expect(useStore.getState().caffeine.zeroDays).toEqual([localDateKey(now)]);
});

it('undoes deletion without dropping an unrelated record', () => {
  const other = { ...dose, id: 'review:other', mg: 30 };
  useStore.setState({ doses: [dose, other] });
  useStore.getState().removeDose(dose.id);
  useStore.getState().undoDoseChange(now + 1);
  expect(useStore.getState().doses).toEqual(
    expect.arrayContaining([dose, other]),
  );
  expect(useStore.getState().doses).toHaveLength(2);
});

it('restores a destination zero marker when undo moves a dose back to its original day', () => {
  useStore.setState({ doses: [{ ...dose, timestamp: yesterday }] });
  useStore.getState().markCaffeineFree(now);
  useStore.getState().updateDose(dose.id, { timestamp: now });
  expect(useStore.getState().caffeine.zeroDays).toEqual([]);
  useStore.getState().undoDoseChange(now + 1);
  expect(useStore.getState().doses[0].timestamp).toBe(yesterday);
  expect(useStore.getState().caffeine.zeroDays).toEqual([localDateKey(now)]);
});

it('does not restore a zero marker when another dose now occupies that day', () => {
  useStore.getState().markCaffeineFree(now);
  useStore.getState().addDose(dose);
  const other = { ...dose, id: 'review:concurrent', mg: 40 };
  useStore.setState({ doses: [dose, other] });
  useStore.getState().undoDoseChange(now + 1);
  expect(useStore.getState().doses).toEqual([other]);
  expect(useStore.getState().caffeine.zeroDays).toEqual([]);
});
