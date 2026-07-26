import { jsonStringStorage } from '~/services/storage';
import {
  isAppWalkthroughPending,
  isWalkthroughTabDisabled,
} from '~/features/appWalkthrough/model';
import { useStore } from '~/state/store';

function resetOnboarding() {
  useStore.setState({
    onboarding: {
      completed: false,
      source: 'healthkit',
      permissionStatus: 'idle',
      appWalkthroughCompleted: false,
      appWalkthroughStep: 0,
    },
  });
}

describe('app walkthrough persistence', () => {
  beforeEach(() => {
    resetOnboarding();
  });

  it('starts incomplete at step zero, advances through the final step, and completes without changing user data', () => {
    const originalDoses = useStore.getState().doses;
    expect(useStore.getState().onboarding).toMatchObject({
      appWalkthroughCompleted: false,
      appWalkthroughStep: 0,
    });

    for (let index = 0; index < 12; index += 1) {
      useStore.getState().advanceAppWalkthrough();
    }

    expect(useStore.getState().onboarding.appWalkthroughStep).toBe(9);
    useStore.getState().completeAppWalkthrough();
    expect(useStore.getState().onboarding.appWalkthroughCompleted).toBe(true);
    expect(useStore.getState().doses).toBe(originalDoses);
  });

  it('does not complete the walkthrough when setup completes', () => {
    useStore.getState().completeOnboarding();

    expect(useStore.getState().onboarding.completed).toBe(true);
    expect(
      useStore.getState().onboarding.appWalkthroughCompleted,
    ).toBe(false);
  });

  it('does not complete the walkthrough when the user chooses sample data', () => {
    useStore.getState().loadDemoData();

    expect(useStore.getState().onboarding.completed).toBe(true);
    expect(
      useStore.getState().onboarding.appWalkthroughCompleted,
    ).toBe(false);
  });

  it('re-enables every tab as soon as completion is persisted', () => {
    useStore.getState().completeOnboarding();

    const pendingBefore = isAppWalkthroughPending(
      useStore.getState().onboarding,
    );
    expect(isWalkthroughTabDisabled('Summary', pendingBefore)).toBe(true);

    useStore.getState().completeAppWalkthrough();

    const pendingAfter = isAppWalkthroughPending(
      useStore.getState().onboarding,
    );
    expect(isWalkthroughTabDisabled('Sleep', pendingAfter)).toBe(false);
  });

  it('migrates a version 4 completed Summary walkthrough as complete', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          onboarding: {
            completed: true,
            source: 'manual',
            permissionStatus: 'unsupported',
            summaryWalkthroughCompleted: true,
          },
        },
        version: 4,
      }),
    );

    await useStore.persist.rehydrate();

    expect(
      useStore.getState().onboarding.appWalkthroughCompleted,
    ).toBe(true);
    expect(useStore.getState().onboarding).not.toHaveProperty(
      'summaryWalkthroughCompleted',
    );
  });

  it('migrates an incomplete legacy user as incomplete at step zero', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          onboarding: {
            completed: false,
            source: 'healthkit',
            permissionStatus: 'idle',
          },
        },
        version: 4,
      }),
    );

    await useStore.persist.rehydrate();

    expect(
      useStore.getState().onboarding,
    ).toMatchObject({ appWalkthroughCompleted: false, appWalkthroughStep: 0 });
  });
});
