import { jsonStringStorage } from '~/services/storage';
import { useStore } from '~/state/store';

function resetOnboarding() {
  useStore.setState({
    onboarding: {
      completed: false,
      source: 'healthkit',
      permissionStatus: 'idle',
      summaryWalkthroughCompleted: false,
    },
  });
}

describe('summary walkthrough persistence', () => {
  beforeEach(() => {
    resetOnboarding();
  });

  it('starts incomplete and completes through its focused action', () => {
    expect(
      useStore.getState().onboarding.summaryWalkthroughCompleted,
    ).toBe(false);

    useStore.getState().completeSummaryWalkthrough();

    expect(
      useStore.getState().onboarding.summaryWalkthroughCompleted,
    ).toBe(true);
  });

  it('does not complete the walkthrough when setup completes', () => {
    useStore.getState().completeOnboarding();

    expect(useStore.getState().onboarding.completed).toBe(true);
    expect(
      useStore.getState().onboarding.summaryWalkthroughCompleted,
    ).toBe(false);
  });

  it('does not complete the walkthrough when the user chooses sample data', () => {
    useStore.getState().loadDemoData();

    expect(useStore.getState().onboarding.completed).toBe(true);
    expect(
      useStore.getState().onboarding.summaryWalkthroughCompleted,
    ).toBe(false);
  });

  it('migrates a version 3 completed user as walkthrough-complete', async () => {
    jsonStringStorage.setItem(
      'aurora/state',
      JSON.stringify({
        state: {
          onboarding: {
            completed: true,
            source: 'manual',
            permissionStatus: 'unsupported',
          },
        },
        version: 3,
      }),
    );

    await useStore.persist.rehydrate();

    expect(
      useStore.getState().onboarding.summaryWalkthroughCompleted,
    ).toBe(true);
  });

  it('migrates a version 3 incomplete user as walkthrough-incomplete', async () => {
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
        version: 3,
      }),
    );

    await useStore.persist.rehydrate();

    expect(
      useStore.getState().onboarding.summaryWalkthroughCompleted,
    ).toBe(false);
  });
});
