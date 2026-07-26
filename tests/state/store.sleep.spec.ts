import { useStore } from '~/state/store';

const manual = {
  id: 'manual:sleep:1:abc',
  start: 1_700_000_000_000,
  end: 1_700_028_800_000,
  type: 'sleep' as const,
  note: 'Quiet night',
};
const imported = {
  id: 'healthkit:sleep:1:2',
  start: 1_700_000_000_000,
  end: 1_700_028_800_000,
  type: 'sleep' as const,
};

describe('manual sleep store actions', () => {
  beforeEach(() => {
    useStore.setState({ sleeps: [manual, imported] });
  });

  it('updates a manual sleep session while preserving its ID and type', () => {
    useStore.getState().updateManualSleep(manual.id, { note: 'Edited', end: manual.end - 1 });

    expect(useStore.getState().sleeps[0]).toEqual({ ...manual, note: 'Edited', end: manual.end - 1 });
  });

  it('removes a manual sleep session', () => {
    useStore.getState().removeManualSleep(manual.id);

    expect(useStore.getState().sleeps).toEqual([imported]);
  });

  it('does not update or remove imported Health sleep', () => {
    useStore.getState().updateManualSleep(imported.id, { note: 'Nope' });
    useStore.getState().removeManualSleep(imported.id);

    expect(useStore.getState().sleeps).toEqual([manual, imported]);
  });

  it('replaces only a boundary-equivalent legacy Health record during canonical refresh', () => {
    const legacy = {
      id: `sleep:${manual.start}:${manual.end}`,
      start: manual.start,
      end: manual.end,
      type: 'sleep' as const,
    };
    const distinct = {
      id: `sleep:${manual.start + 1}:${manual.end}`,
      start: manual.start + 1,
      end: manual.end,
      type: 'sleep' as const,
    };
    useStore.setState({ sleeps: [legacy, distinct] });

    useStore.getState().upsertSleepSessions([
      {
        id: `healthkit:sleep:${manual.start}:${manual.end}`,
        start: manual.start,
        end: manual.end,
        type: 'sleep',
      },
    ]);

    expect(useStore.getState().sleeps).toEqual([
      {
        id: `healthkit:sleep:${manual.start}:${manual.end}`,
        start: manual.start,
        end: manual.end,
        type: 'sleep',
      },
      {
        ...distinct,
        id: `healthkit:sleep:${manual.start + 1}:${manual.end}`,
      },
    ]);
  });
});
