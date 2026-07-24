import {
  APP_WALKTHROUGH_STEPS,
  clampAppWalkthroughStep,
  getRevealedGroups,
  initialAppWalkthroughState,
  isAppWalkthroughPending,
  isWalkthroughTabDisabled,
  reduceAppWalkthrough,
} from '~/features/appWalkthrough';

describe('app walkthrough model', () => {
  it('defines the ten approved steps in route order', () => {
    expect(
      APP_WALKTHROUGH_STEPS.map((step) => ({
        id: step.id,
        route: step.route,
        progress: step.progress,
        title: step.title,
        body: step.body,
        primaryAction: step.primaryAction,
      })),
    ).toEqual([
      { id: 'summary-orientation', route: 'Summary', progress: '1 of 10', title: 'Your day at a glance', body: 'Aurora brings caffeine, sleep, and alertness together.', primaryAction: 'Next' },
      { id: 'summary-signals', route: 'Summary', progress: '2 of 10', title: 'See what shapes alertness', body: 'These signals show how caffeine, sleep, and vigilance shape your day.', primaryAction: 'Next' },
      { id: 'summary-logging', route: 'Summary', progress: '3 of 10', title: 'Log in a tap', body: 'Use a common amount, or open Custom Entry when you need more detail.', primaryAction: 'Next' },
      { id: 'summary-sleep', route: 'Summary', progress: '4 of 10', title: 'Next: your sleep', body: 'See where rest data comes from and how timing shapes tomorrow.', primaryAction: 'Next' },
      { id: 'sleep-understanding', route: 'Sleep', progress: '5 of 10', title: 'Understand your sleep', body: 'Use Week or Month to review your real sleep history and recent highlights.', primaryAction: 'Next' },
      { id: 'sleep-add-or-connect', route: 'Sleep', progress: '6 of 10', title: 'Add or connect sleep', body: 'Aurora can read Health data or save a manual sleep session.', primaryAction: 'Next' },
      { id: 'log-quick-add', route: 'Log', progress: '7 of 10', title: 'Log in one tap', body: 'Use the same quick amounts here and on Summary.', primaryAction: 'Next' },
      { id: 'log-details', route: 'Log', progress: '8 of 10', title: 'Add details when they matter', body: 'Custom Entry records amount, source, time, and an optional note.', primaryAction: 'Next' },
      { id: 'insights-patterns', route: 'Insights', progress: '9 of 10', title: 'See patterns over time', body: 'Change the range to compare caffeine, timing, and alertness.', primaryAction: 'Next' },
      { id: 'insights-learning', route: 'Insights', progress: '10 of 10', title: 'Keep learning from your trends', body: 'Review highlights or open Show All Data whenever you need the details.', primaryAction: 'Finish' },
    ]);
  });

  it('reveals groups cumulatively within the current route only', () => {
    expect(getRevealedGroups(2)).toEqual([
      'summary-header',
      'summary-alert',
      'summary-pinned',
      'summary-today',
      'summary-logging',
      'summary-recent',
    ]);
    expect(getRevealedGroups(5)).toEqual([
      'sleep-header',
      'sleep-history',
      'sleep-sources',
    ]);
    expect(getRevealedGroups(6)).toEqual([
      'log-header',
      'log-quick-add',
    ]);
  });

  it('advances only after a reveal settles and completes by skip or final finish', () => {
    const positioning = reduceAppWalkthrough(initialAppWalkthroughState, { type: 'START' });
    expect(reduceAppWalkthrough(positioning, { type: 'NEXT' })).toEqual(positioning);

    const coaching = reduceAppWalkthrough(
      reduceAppWalkthrough(positioning, { type: 'POSITIONED' }),
      { type: 'SETTLED' },
    );
    expect(reduceAppWalkthrough(coaching, { type: 'NEXT' })).toEqual({ stepIndex: 1, phase: 'positioning' });
    expect(reduceAppWalkthrough(coaching, { type: 'SKIP' })).toEqual({ stepIndex: 0, phase: 'complete' });
    expect(
      reduceAppWalkthrough({ stepIndex: 9, phase: 'coaching' }, { type: 'FINISH' }),
    ).toEqual({ stepIndex: 9, phase: 'complete' });
  });

  it('clamps persisted cursor and gates every tab while the walkthrough is pending', () => {
    expect(clampAppWalkthroughStep(-1)).toBe(0);
    expect(clampAppWalkthroughStep(3.8)).toBe(3);
    expect(clampAppWalkthroughStep(100)).toBe(9);
    expect(isAppWalkthroughPending({ completed: true, appWalkthroughCompleted: false })).toBe(true);
    expect(isWalkthroughTabDisabled('Summary', true)).toBe(true);
    expect(isWalkthroughTabDisabled('Insights', false)).toBe(false);
  });
});
