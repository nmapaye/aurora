export type RevealMotionPlan = {
  delayMs: number;
  initialTranslateY: number;
  initialScale: number;
  mode: 'spring' | 'timing';
  durationMs: number;
};

export function getRevealMotionPlan(
  reduceMotion: boolean,
  staggerIndex: number,
): RevealMotionPlan {
  if (reduceMotion) {
    return {
      delayMs: 0,
      initialTranslateY: 0,
      initialScale: 1,
      mode: 'timing',
      durationMs: 120,
    };
  }

  return {
    delayMs: Math.max(0, staggerIndex) * 80,
    initialTranslateY: 14,
    initialScale: 0.97,
    mode: 'spring',
    durationMs: 0,
  };
}
