import { createBackup, parseBackup } from '~/features/ownership/backup';
import { useStore } from '~/state/store';

test('restoring a pre-native version 1 backup gives the lock privacy preference its default', () => {
  const original = useStore.getState();
  const legacy = JSON.parse(
    JSON.stringify(createBackup(original, 1700000000000)),
  );
  delete legacy.data.ownership.native;
  try {
    useStore.setState({
      onboarding: {
        ...original.onboarding,
        completed: true,
        appWalkthroughCompleted: true,
      },
    });
    useStore.getState().replaceBackup(parseBackup(JSON.stringify(legacy)));
    expect(useStore.getState().ownership.native).toEqual({
      showLockValues: false,
    });
  } finally {
    useStore.setState(original);
  }
});
