import { getRevealMotionPlan } from '~/features/summaryWalkthrough/motion';

describe('Summary walkthrough motion', () => {
  it('uses the approved soft spring cascade', () => {
    expect(getRevealMotionPlan(false, 2)).toEqual({
      delayMs: 160,
      initialTranslateY: 14,
      initialScale: 0.97,
      mode: 'spring',
      durationMs: 0,
    });
  });

  it('removes motion and stagger when Reduce Motion is enabled', () => {
    expect(getRevealMotionPlan(true, 4)).toEqual({
      delayMs: 0,
      initialTranslateY: 0,
      initialScale: 1,
      mode: 'timing',
      durationMs: 120,
    });
  });
});
