import { defaultPlanningState, type PlanningState } from '~/features/planning/model';
import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';

const now = new Date(2026, 8, 7, 10).getTime();
const planning: PlanningState = {
  ...defaultPlanningState(),
  scenarios: [{ id: 'plan', name: 'Afternoon tea', doses: [{ id: 'tea', label: 'Tea', offsetMinutes: 120, mg: 70 }] }],
  thresholdMg: 15,
  sensitivityHours: [4, 6, 8],
  reduction: { startDate: '2026-09-08', startMg: 180, endMg: 90, days: 8 },
  budget: { targetMg: 180, allocations: [{ id: 'a', label: 'Coffee', mg: 95 }] },
  focus: { startMinutes: 90, endMinutes: 240 },
  checkIns: [{ id: 'check', timestamp: now, rating: 3, note: 'After lunch' }],
  experiments: [{ id: 'experiment', question: 'Does my earlier coffee coincide with longer sleep?', baseline: { start: '2026-08-01', end: '2026-08-07' }, comparison: { start: '2026-08-08', end: '2026-08-14' } }],
};
beforeEach(() => {
  useStore.setState({ doses: [], planning: defaultPlanningState(), onboarding: { ...useStore.getState().onboarding, completed: true, appWalkthroughCompleted: true } });
});

it('round-trips every customized planning field without recording hypothetical doses', async () => {
  useStore.getState().setPlanning(planning);
  const saved = jsonStringStorage.getItem('aurora/state');
  expect(saved).not.toBeNull();
  useStore.setState({ planning: defaultPlanningState() });
  jsonStringStorage.setItem('aurora/state', saved!);
  await useStore.persist.rehydrate();
  expect(useStore.getState().planning).toEqual(planning);
  expect(useStore.getState().doses).toEqual([]);
});

it('preserves plans when a personal drink is saved', () => {
  useStore.getState().setPlanning(planning);
  useStore.getState().saveDrink({ id: 'personal:tea', label: 'My tea', mg: 70, archived: false });
  expect(useStore.getState().planning).toEqual(planning);
  expect(useStore.getState().caffeine.drinks).toContainEqual({ id: 'personal:tea', label: 'My tea', mg: 70, archived: false });
});

it('rejects malformed check-in dates and ratings during hydration', async () => {
  jsonStringStorage.setItem('aurora/state', JSON.stringify({ version: 9, state: { planning: { ...planning,
    checkIns: [planning.checkIns[0], ...[null, true, '2026-09-07', 1e100].map((timestamp, i) => ({ id: `bad${i}`, timestamp, rating: 3, note: '' })), { id: 'fraction', timestamp: now, rating: 2.5, note: '' }],
  } } }));
  await useStore.persist.rehydrate();
  expect(useStore.getState().planning.checkIns).toEqual(planning.checkIns);
  expect(useStore.getState().planning.scenarios).toEqual(planning.scenarios);
});
