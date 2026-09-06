import { useStore } from '~/state/store';
import { defaultPlanningState } from '~/features/planning/model';
const scenario = {
  id: 'one',
  name: 'Tea',
  doses: [{ id: 'dose', offsetMinutes: 60, mg: 50, label: 'Tea' }],
};
beforeEach(() =>
  useStore.setState({
    planning: defaultPlanningState(),
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  }),
);
it('saves, updates and removes plans without recording intake', () => {
  const before = useStore.getState().doses;
  useStore.getState().setPlanning({ scenarios: [scenario] });
  expect(useStore.getState().planning.scenarios).toEqual([scenario]);
  useStore
    .getState()
    .setPlanning({ scenarios: [{ ...scenario, name: 'Edited' }] });
  expect(useStore.getState().planning.scenarios[0].name).toBe('Edited');
  useStore.getState().setPlanning({ scenarios: [] });
  expect(useStore.getState().planning.scenarios).toEqual([]);
  expect(useStore.getState().doses).toBe(before);
});
it('guards planning and check-in mutations during the walkthrough', () => {
  useStore.setState({
    onboarding: {
      ...useStore.getState().onboarding,
      appWalkthroughCompleted: false,
    },
  });
  useStore
    .getState()
    .setPlanning({
      scenarios: [scenario],
      checkIns: [{ id: 'c', timestamp: Date.now(), rating: 4, note: '' }],
    });
  expect(useStore.getState().planning).toEqual(defaultPlanningState());
});
