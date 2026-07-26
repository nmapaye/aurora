import { getRevealMotionPlan } from '~/features/appWalkthrough/motion';
import {
  WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
  WALKTHROUGH_REVEAL_SETTLE_MS,
} from '~/features/appWalkthrough/model';

describe('App walkthrough motion', () => {
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

  it('settles the final index-7 reveal before coaching in under one second', () => {
    const finalReveal = getRevealMotionPlan(false, 7);

    expect(finalReveal.delayMs).toBe(560);
    expect(WALKTHROUGH_REVEAL_SETTLE_MS).toBe(900);
    expect(WALKTHROUGH_REVEAL_SETTLE_MS).toBeLessThan(1000);
    expect(
      WALKTHROUGH_REVEAL_SETTLE_MS - finalReveal.delayMs,
    ).toBeGreaterThanOrEqual(340);
    expect(WALKTHROUGH_REDUCED_MOTION_SETTLE_MS).toBe(120);
  });
});
