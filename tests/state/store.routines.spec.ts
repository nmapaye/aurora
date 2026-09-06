import { useStore } from '~/state/store';
import { defaultSleepRoutines } from '~/features/sleep/upgrades';
beforeEach(() =>
  useStore.setState({
    sleepRoutines: defaultSleepRoutines(8),
    sleeps: [],
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
    },
  }),
);
it('derives initial wake from sleep target until the weekly schedule is edited', () => {
  useStore.getState().setPrefs({ targetSleep: 7.25 });
  expect(useStore.getState().sleepRoutines.weekly[0].wake).toBe(345);
  const weekly = useStore
    .getState()
    .sleepRoutines.weekly.map((t) => ({ ...t, wake: 420 }));
  useStore.getState().setSleepRoutines({ weekly });
  useStore.getState().setPrefs({ targetSleep: 8 });
  expect(useStore.getState().sleepRoutines.weekly[0].wake).toBe(420);
});
it('rejects an overlong nap and keeps the timer available for correction', () => {
  const end = Date.now() - 1000;
  useStore
    .getState()
    .setSleepRoutines({ timer: { start: end - 25 * 3600000, end } });
  useStore.getState().confirmNap();
  expect(useStore.getState().sleeps).toEqual([]);
  expect(useStore.getState().sleepRoutines.timer).not.toBeNull();
});
it('retains an episode journal after an earlier overlap is added and the original anchor removed', () => {
  const end = Date.now() - 3600000;
  const original = {
    id: 'manual:sleep:original',
    start: end - 8 * 3600000,
    end,
    type: 'sleep' as const,
  };
  useStore.getState().addSleep(original);
  useStore
    .getState()
    .setSleepRoutines({
      annotations: { [original.id]: { quality: 4, note: 'Keep this journal' } },
    });
  useStore
    .getState()
    .addSleep({
      ...original,
      id: 'manual:sleep:earlier',
      start: original.start - 1800000,
    });
  useStore.getState().removeManualSleep(original.id);
  expect(
    useStore.getState().sleepRoutines.annotations['manual:sleep:earlier']?.note,
  ).toBe('Keep this journal');
});
