import {
  APP_WALKTHROUGH_STEPS,
  clampAppWalkthroughStep,
  getRevealedGroups,
  initialAppWalkthroughState,
  isAppWalkthroughPending,
  isWalkthroughTabDisabled,
  reduceAppWalkthrough,
} from '~/features/appWalkthrough/model';

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
      { id: 'summary-orientation', route: 'Summary', progress: '1 of 10', title: 'Your day at a glance', body: 'Estimated alertness and today’s caffeine curve, built from what you record.', primaryAction: 'Next' },
      { id: 'summary-signals', route: 'Summary', progress: '2 of 10', title: 'Your pinned signals', body: 'Caffeine logged today, your latest sleep, and your latest Reaction Test, each with its date and source.', primaryAction: 'Next' },
      { id: 'summary-logging', route: 'Summary', progress: '3 of 10', title: 'Log caffeine', body: 'Caffeine Logged opens Log, where you record the amount, time, and source and see recent entries.', primaryAction: 'Next' },
      { id: 'summary-sleep', route: 'Summary', progress: '4 of 10', title: 'Next: your sleep', body: 'Sleep comes from Health or your own entries. The Sleep tab shows each night and where it came from.', primaryAction: 'Next' },
      { id: 'sleep-understanding', route: 'Sleep', progress: '5 of 10', title: 'Your recorded nights', body: 'Week or Month shows each night you recorded. Tap or drag the chart to read a day; Most Recent Sleep shows its date and source.', primaryAction: 'Next' },
      { id: 'sleep-add-or-connect', route: 'Sleep', progress: '6 of 10', title: 'Where your sleep comes from', body: 'Sleep Data holds read-only Health access, manual entries, Sample Data, and every recorded night.', primaryAction: 'Next' },
      { id: 'log-quick-add', route: 'Log', progress: '7 of 10', title: 'Log caffeine', body: 'Logged Today totals what you record. Tap a drink to log it now, with Undo right after, or use Custom Entry to set the amount and time.', primaryAction: 'Next' },
      { id: 'log-details', route: 'Log', progress: '8 of 10', title: 'Fix a mistake', body: 'Recent shows each entry’s date, time, amount, and source. Tap one to edit or delete it; Show All Caffeine Data holds the full history.', primaryAction: 'Next' },
      { id: 'insights-patterns', route: 'Insights', progress: '9 of 10', title: 'Your caffeine over time', body: 'Choose W, 2W, or M. Tap or drag the chart to read a day; days without entries read as no record, not zero.', primaryAction: 'Next' },
      { id: 'insights-learning', route: 'Insights', progress: '10 of 10', title: 'Your Reaction Test', body: 'Your latest test shows its date and source. A baseline appears only after 3 tests; Details holds time of day, drinks, and every entry.', primaryAction: 'Finish' },
    ]);
  });

  it('keeps Insights as steps 9–10: the inspectable chart, then the Reaction Test signal', () => {
    expect(APP_WALKTHROUGH_STEPS.slice(8).map((step) => [step.route, step.anchor, step.primaryAction])).toEqual([
      ['Insights', 'insights-top', 'Next'],
      ['Insights', 'insights-reaction', 'Finish'],
    ]);
    expect(getRevealedGroups(8)).toEqual(['insights-header', 'insights-range']);
    expect(getRevealedGroups(9)).toEqual(['insights-header', 'insights-range', 'insights-reaction']);
    expect(
      APP_WALKTHROUGH_STEPS.slice(8).map((step) => `${step.title} ${step.body}`).join(' '),
    ).not.toMatch(/limit|adherence|highlights|bedtime|wake|should|recommend|export/i);
  });

  it('reveals the Today hero with the Summary header before the pinned signals', () => {
    expect(getRevealedGroups(0)).toEqual([
      'summary-header',
      'summary-today',
      'summary-alert',
    ]);
    expect(APP_WALKTHROUGH_STEPS.slice(0, 4).map((step) => step.anchor)).toEqual([
      'summary-top',
      'summary-pinned',
      'summary-caffeine',
      'summary-sleep',
    ]);
  });

  it('keeps Sleep as steps 5–6, ending on the Sleep Data entry', () => {
    expect(APP_WALKTHROUGH_STEPS).toHaveLength(10);
    expect(APP_WALKTHROUGH_STEPS.slice(4, 6).map((step) => [step.route, step.anchor])).toEqual([
      ['Sleep', 'sleep-top'],
      ['Sleep', 'sleep-data'],
    ]);
    expect(APP_WALKTHROUGH_STEPS.map((step) => step.body).join(' ')).not.toMatch(
      /plan|recommend|allowance|mg\b|cutoff/i,
    );
  });

  it('keeps Log as steps 7–8: logging from the top, then corrections in Recent', () => {
    expect(APP_WALKTHROUGH_STEPS.slice(6, 8).map((step) => [step.route, step.anchor])).toEqual([
      ['Log', 'log-top'],
      ['Log', 'log-details'],
    ]);
    expect(
      APP_WALKTHROUGH_STEPS.slice(6, 8).map((step) => `${step.title} ${step.body}`).join(' '),
    ).not.toMatch(/remaining|limit|budget|safe|guideline/i);
  });

  it('reveals groups cumulatively within the current route only', () => {
    expect(getRevealedGroups(2)).toEqual([
      'summary-header',
      'summary-today',
      'summary-alert',
      'summary-pinned',
    ]);
    expect(getRevealedGroups(5)).toEqual([
      'sleep-header',
      'sleep-history',
      'sleep-data',
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
