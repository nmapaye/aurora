import { createBackup } from '~/features/ownership/backup';
import { defaultOwnership } from '~/features/ownership/model';
import { useStore } from '~/state/store';
beforeEach(() =>
  useStore.setState({
    ownership: defaultOwnership(),
    doses: [],
    onboarding: {
      ...useStore.getState().onboarding,
      completed: true,
      appWalkthroughCompleted: true,
      permissionStatus: 'denied',
    },
  }),
);
test('restore replaces data atomically while retaining current OS permission', () => {
  const backup = createBackup(useStore.getState(), 1700000000000);
  backup.data.doses = [{ id: 'original', mg: 50, timestamp: 1700000000000 }];
  useStore.getState().replaceBackup(backup);
  expect(useStore.getState().doses[0].id).toBe('original');
  expect(useStore.getState().onboarding.permissionStatus).toBe('denied');
  const bad = { ...backup, version: 2 } as unknown as typeof backup;
  expect(() => useStore.getState().replaceBackup(bad)).toThrow();
  expect(useStore.getState().doses[0].id).toBe('original');
});
test('walkthrough blocks customization, restore and deletion', () => {
  const backup = createBackup(useStore.getState(), 1700000000000);
  useStore.setState({
    onboarding: {
      ...useStore.getState().onboarding,
      appWalkthroughCompleted: false,
    },
  });
  const before = useStore.getState();
  useStore
    .getState()
    .setOwnership({
      ...defaultOwnership(),
      summary: {
        order: ['sleep', 'caffeine', 'active-caffeine', 'vigilance', 'cutoff'],
        hidden: ['sleep'],
      },
    });
  useStore.getState().replaceBackup(backup);
  useStore.getState().deleteLocalCategories(['all']);
  expect(useStore.getState()).toEqual(before);
});
