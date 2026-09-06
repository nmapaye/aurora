import { defaultSleepRoutines, sleepJournalKey } from '~/features/sleep/upgrades';
import { makeHealthSleepSessionId } from '~/features/sleep/healthSleep';
import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';

const now = new Date(2026, 8, 7, 12).getTime();
const hour = 3_600_000;

beforeEach(() => {
  jest.spyOn(Date, 'now').mockReturnValue(now);
  useStore.setState({
    sleeps: [],
    prefs: { ...useStore.getState().prefs, targetSleep: 8 },
    sleepRoutines: defaultSleepRoutines(8),
    onboarding: { ...useStore.getState().onboarding, completed: false, appWalkthroughCompleted: false },
  });
});
afterEach(() => jest.restoreAllMocks());

it('uses the onboarding target for the initial unconfigured wake time', () => {
  useStore.getState().setPrefs({ targetSleep: 7.25 });
  expect(useStore.getState().sleepRoutines.weekly.every(times => times.bedtime === 1350 && times.wake === 345)).toBe(true);
});

it('preserves a configured weekly schedule when the sleep target changes', () => {
  const weekly = defaultSleepRoutines(8).weekly;
  weekly[1] = { bedtime: 1260, wake: 300 };
  useStore.getState().setSleepRoutines({ weekly });
  useStore.getState().setPrefs({ targetSleep: 7.25 });
  expect(useStore.getState().sleepRoutines.weekly).toEqual(weekly);
});

it('restores a stopped timer without logging sleep until confirmation', async () => {
  const timer = { start: now - hour, end: now - hour / 2 };
  jsonStringStorage.setItem('aurora/state', JSON.stringify({ version: 8, state: {
    sleeps: [], sleepRoutines: { ...defaultSleepRoutines(8), timer },
    onboarding: { completed: true, appWalkthroughCompleted: true },
  } }));
  await useStore.persist.rehydrate();
  expect(useStore.getState().sleeps).toEqual([]);
  expect(useStore.getState().sleepRoutines.timer).toEqual(timer);
  useStore.getState().confirmNap();
  expect(useStore.getState().sleeps).toHaveLength(1);
  expect(useStore.getState().sleeps[0]).toMatchObject({ start: timer.start, end: timer.end, type: 'nap' });
  expect(useStore.getState().sleeps[0].id).toMatch(/^manual:sleep:/);
  expect(useStore.getState().sleepRoutines.timer).toBeNull();
  useStore.getState().confirmNap();
  expect(useStore.getState().sleeps).toHaveLength(1);
});

it('does not save running, future-ended or overlong nap timers', () => {
  for (const timer of [{ start: now - hour }, { start: now - hour, end: now + hour }, { start: now - 25 * hour, end: now }]) {
    useStore.setState({ sleepRoutines: { ...defaultSleepRoutines(8), timer } });
    useStore.getState().confirmNap();
    expect(useStore.getState().sleeps).toEqual([]);
    expect(useStore.getState().sleepRoutines.timer).toEqual(timer);
  }
});

it('blocks schedule changes and nap confirmation during the walkthrough', () => {
  const timer = { start: now - hour, end: now - hour / 2 };
  const original = { ...defaultSleepRoutines(8), timer };
  useStore.setState({ sleepRoutines: original, onboarding: { ...useStore.getState().onboarding, completed: true, appWalkthroughCompleted: false } });
  useStore.getState().setSleepRoutines({ timer: null });
  useStore.getState().confirmNap();
  expect(useStore.getState().sleepRoutines).toEqual(original);
  expect(useStore.getState().sleeps).toEqual([]);
});

describe('journal association during overlap correction', () => {
  const boundaries = { start: now - 13 * hour, end: now - 5 * hour };
  const health = { ...boundaries, id: makeHealthSleepSessionId(boundaries), type: 'sleep' as const };
  const manual = { ...health, id: 'manual:sleep:earlier', start: health.start - hour / 2 };
  const journal = { quality: 4, note: 'Quiet room after a busy day' };

  function visibleJournal(id: string) {
    const state = useStore.getState();
    return state.sleepRoutines.annotations[sleepJournalKey(id, state.sleeps, now, state.sleepRoutines.annotations)];
  }

  it('keeps a journal visible when an earlier overlapping manual record is added', () => {
    useStore.setState({ sleeps: [health], sleepRoutines: { ...defaultSleepRoutines(8), annotations: { [health.id]: journal } } });
    useStore.getState().addSleep(manual);
    expect(visibleJournal(health.id)).toEqual(journal);
    expect(visibleJournal(manual.id)).toEqual(journal);
    expect(useStore.getState().sleeps.find(record => record.id === health.id)).toEqual(health);
  });

  it('keeps a journal when Health supplies an earlier segment on refresh', () => {
    useStore.setState({ sleeps: [health], sleepRoutines: { ...defaultSleepRoutines(8), annotations: { [health.id]: journal } } });
    const earlier = { ...health, start: health.start - hour };
    earlier.id = makeHealthSleepSessionId(earlier);
    useStore.getState().upsertSleepSessions([earlier]);
    expect(visibleJournal(health.id)).toEqual(journal);
  });

  it('keeps the episode journal when its earliest manual record is deleted', () => {
    useStore.setState({ sleeps: [manual, health], sleepRoutines: { ...defaultSleepRoutines(8), annotations: { [manual.id]: journal } } });
    useStore.getState().removeManualSleep(manual.id);
    expect(useStore.getState().sleeps).toEqual([health]);
    expect(visibleJournal(health.id)).toEqual(journal);
  });
});
