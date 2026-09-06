import { useStore } from '~/state/store';
import {
  calculateServing,
  filterDoses,
  localDayKey,
  previewDose,
} from '~/features/caffeine/upgrades';

const now = new Date(2026, 8, 7, 12).getTime();
const dose = {
  id: 'one',
  timestamp: now,
  mg: 100,
  source: 'Coffee',
  note: 'meeting',
};
beforeEach(() => {
  jest.spyOn(Date, 'now').mockReturnValue(now);
  useStore.setState({
    doses: [],
    caffeine: {
      drinks: [],
      favoriteIds: ['espresso'],
      draft: null,
      zeroDays: [],
    },
    doseUndo: null,
  });
});
afterEach(() => jest.restoreAllMocks());
it('calculates servings and concentration without accepting invalid amounts', () => {
  expect(calculateServing('servings', '95', '1.5', '100')).toBe(143);
  expect(calculateServing('volume', '32', '250', '100')).toBe(80);
  expect(calculateServing('volume', '32', '250', '0')).toBeNull();
});
it('combines date, source, amount and note search', () => {
  expect(
    filterDoses([dose, { ...dose, id: 'other', mg: 40 }], {
      query: 'meeting',
      source: 'Coffee',
      minMg: 80,
      start: now,
      end: now,
    }),
  ).toEqual([dose]);
});
it('excludes sample data and the replaced entry from previews', () => {
  expect(
    previewDose(
      [dose, { ...dose, id: 'demo:one', mg: 900 }],
      { ...dose, mg: 50 },
      now + 5 * 3600000,
      5,
      'one',
    ),
  ).toEqual({ dailyTotal: 50, bedtimeMg: 25 });
});
it('records zero days and clears them when a real dose arrives', () => {
  useStore.getState().markCaffeineFree(now);
  expect(useStore.getState().caffeine.zeroDays).toEqual([localDayKey(now)]);
  useStore.getState().addDose(dose);
  expect(useStore.getState().caffeine.zeroDays).toEqual([]);
  useStore.getState().markCaffeineFree(now);
  expect(useStore.getState().caffeine.zeroDays).toEqual([]);
});
it('undoes only the last change and preserves unrelated changes', () => {
  useStore.getState().addDose(dose);
  useStore.getState().updateDose('one', { mg: 80 });
  useStore.setState({
    doses: [...useStore.getState().doses, { ...dose, id: 'two' }],
  });
  useStore.getState().undoDoseChange(now + 9999);
  expect(useStore.getState().doses.map((d) => d.mg)).toEqual([100, 100]);
});
it('refuses expired undo and conflicting changes', () => {
  useStore.getState().addDose(dose);
  useStore.getState().undoDoseChange(now + 10000);
  expect(useStore.getState().doses).toEqual([dose]);
  useStore.getState().updateDose('one', { mg: 80 });
  useStore.setState({ doses: [{ ...dose, mg: 70 }] });
  useStore.getState().undoDoseChange(now + 1);
  expect(useStore.getState().doses[0].mg).toBe(70);
});
it('keeps sample entries read-only', () => {
  useStore.setState({ doses: [{ ...dose, id: 'demo:one' }] });
  useStore.getState().updateDose('demo:one', { mg: 10 });
  useStore.getState().removeDose('demo:one');
  expect(useStore.getState().doses[0].mg).toBe(100);
});
it('archives personal drinks and removes their favorite', () => {
  useStore
    .getState()
    .saveDrink({
      id: 'personal:one',
      label: 'Home coffee',
      mg: 90,
      archived: false,
    });
  useStore.getState().setFavoriteDrinks(['personal:one', 'espresso']);
  useStore
    .getState()
    .saveDrink({
      id: 'personal:one',
      label: 'Home coffee',
      mg: 90,
      archived: true,
    });
  expect(useStore.getState().caffeine.favoriteIds).toEqual(['espresso']);
});
it('restores a zero marker when undoing an addition, and restores a deletion', () => {
  useStore.getState().markCaffeineFree(now);
  useStore.getState().addDose(dose);
  useStore.getState().undoDoseChange(now + 1);
  expect(useStore.getState().doses).toEqual([]);
  expect(useStore.getState().caffeine.zeroDays).toEqual([localDayKey(now)]);
  useStore.getState().addDose(dose);
  useStore.getState().removeDose(dose.id);
  useStore.getState().markCaffeineFree(now);
  useStore.getState().undoDoseChange(now + 1);
  expect(useStore.getState().doses).toEqual([dose]);
  expect(useStore.getState().caffeine.zeroDays).toEqual([]);
});
