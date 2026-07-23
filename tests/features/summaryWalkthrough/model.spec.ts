import {
  SUMMARY_WALKTHROUGH_STEPS,
  getRevealedGroups,
  getTargetScrollY,
  initialWalkthroughState,
  isSummaryWalkthroughPending,
  isTargetFullyVisible,
  isWalkthroughTabDisabled,
  reduceWalkthrough,
} from '~/features/summaryWalkthrough/model';

describe('Summary walkthrough model', () => {
  it('defines the four approved steps in order', () => {
    expect(
      SUMMARY_WALKTHROUGH_STEPS.map((step) => ({
        id: step.id,
        progress: step.progress,
        title: step.title,
      })),
    ).toEqual([
      {
        id: 'orientation',
        progress: '1 of 4',
        title: 'Your day at a glance',
      },
      {
        id: 'signals',
        progress: '2 of 4',
        title: 'See what shapes alertness',
      },
      {
        id: 'logging',
        progress: '3 of 4',
        title: 'Log in a tap',
      },
      {
        id: 'explore',
        progress: '4 of 4',
        title: 'Keep exploring',
      },
    ]);
  });

  it('reveals groups cumulatively and omits an absent alert', () => {
    expect(
      getRevealedGroups(1, { hasAlert: false, isWideLayout: false }),
    ).toEqual(['header', 'pinned']);
    expect(
      getRevealedGroups(2, { hasAlert: true, isWideLayout: true }),
    ).toEqual([
      'header',
      'alert',
      'pinned',
      'today',
      'logging',
      'recent',
    ]);
  });

  it('advances only after a reveal settles', () => {
    const positioning = reduceWalkthrough(initialWalkthroughState, {
      type: 'START',
    });
    expect(positioning).toEqual({
      stageIndex: 0,
      phase: 'positioning',
    });

    expect(
      reduceWalkthrough(positioning, { type: 'NEXT' }),
    ).toEqual(positioning);

    const revealing = reduceWalkthrough(positioning, {
      type: 'POSITIONED',
    });
    expect(revealing).toEqual({ stageIndex: 0, phase: 'revealing' });
    const coaching = reduceWalkthrough(revealing, { type: 'SETTLED' });
    expect(coaching).toEqual({ stageIndex: 0, phase: 'coaching' });
    expect(
      reduceWalkthrough(coaching, { type: 'NEXT' }),
    ).toEqual({ stageIndex: 1, phase: 'positioning' });
  });

  it('completes only through Skip or Finish', () => {
    expect(
      reduceWalkthrough(
        { stageIndex: 2, phase: 'coaching' },
        { type: 'SKIP' },
      ),
    ).toEqual({ stageIndex: 2, phase: 'complete' });

    expect(
      reduceWalkthrough(
        { stageIndex: 3, phase: 'coaching' },
        { type: 'FINISH' },
      ),
    ).toEqual({ stageIndex: 3, phase: 'complete' });
  });

  it('does not advance beyond the last coach step', () => {
    expect(
      reduceWalkthrough(
        { stageIndex: 3, phase: 'coaching' },
        { type: 'NEXT' },
      ),
    ).toEqual({ stageIndex: 3, phase: 'coaching' });
  });

  it('gates only non-Summary tabs for a pending walkthrough', () => {
    expect(
      isSummaryWalkthroughPending({
        completed: true,
        summaryWalkthroughCompleted: false,
      }),
    ).toBe(true);
    expect(isWalkthroughTabDisabled('Summary', true)).toBe(false);
    expect(isWalkthroughTabDisabled('Sleep', true)).toBe(true);
    expect(isWalkthroughTabDisabled('Log', false)).toBe(false);
  });

  it('detects visible targets and clamps scroll positions', () => {
    expect(
      isTargetFullyVisible({
        targetY: 240,
        targetHeight: 120,
        scrollY: 100,
        viewportHeight: 600,
        topClearance: 24,
        bottomClearance: 180,
      }),
    ).toBe(true);
    expect(getTargetScrollY(20, 32)).toBe(0);
    expect(getTargetScrollY(420, 32)).toBe(388);
  });
});
