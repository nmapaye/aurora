export type SummaryWalkthroughStageId =
  | 'orientation'
  | 'signals'
  | 'logging'
  | 'explore';

export type SummaryRevealGroup =
  | 'header'
  | 'alert'
  | 'pinned'
  | 'today'
  | 'logging'
  | 'recent';

export type SummaryAnchorId = 'top' | 'pinned' | 'logging';

export type SummaryWalkthroughStep = {
  id: SummaryWalkthroughStageId;
  progress: string;
  title: string;
  body: string;
  revealGroups: readonly SummaryRevealGroup[];
  anchor: SummaryAnchorId;
  primaryAction: 'Next' | 'Finish';
};

export const WALKTHROUGH_START_DELAY_MS = 300;
export const WALKTHROUGH_SCROLL_SETTLE_MS = 350;
export const WALKTHROUGH_REVEAL_SETTLE_MS = 900;
export const WALKTHROUGH_REDUCED_MOTION_SETTLE_MS = 120;
export const WALKTHROUGH_TOP_CLEARANCE = 24;

export const SUMMARY_WALKTHROUGH_STEPS: readonly SummaryWalkthroughStep[] = [
  {
    id: 'orientation',
    progress: '1 of 4',
    title: 'Your day at a glance',
    body: 'Aurora brings caffeine, sleep, and alertness together.',
    revealGroups: ['header', 'alert'],
    anchor: 'top',
    primaryAction: 'Next',
  },
  {
    id: 'signals',
    progress: '2 of 4',
    title: 'See what shapes alertness',
    body: 'These signals show how caffeine, sleep, and vigilance shape your day. Tap any card later to explore it.',
    revealGroups: ['pinned', 'today'],
    anchor: 'pinned',
    primaryAction: 'Next',
  },
  {
    id: 'logging',
    progress: '3 of 4',
    title: 'Log in a tap',
    body: 'Use a common amount, or open Custom Entry when you need more detail.',
    revealGroups: ['logging', 'recent'],
    anchor: 'logging',
    primaryAction: 'Next',
  },
  {
    id: 'explore',
    progress: '4 of 4',
    title: 'Keep exploring',
    body: 'Sleep manages rest data, Log records caffeine, and Insights reveals patterns over time.',
    revealGroups: [],
    anchor: 'logging',
    primaryAction: 'Finish',
  },
];

export type WalkthroughPhase =
  | 'waiting'
  | 'positioning'
  | 'revealing'
  | 'coaching'
  | 'complete';

export type WalkthroughState = {
  stageIndex: number;
  phase: WalkthroughPhase;
};

export type WalkthroughEvent =
  | { type: 'START' }
  | { type: 'POSITIONED' }
  | { type: 'SETTLED' }
  | { type: 'NEXT' }
  | { type: 'SKIP' }
  | { type: 'FINISH' };

export const initialWalkthroughState: WalkthroughState = {
  stageIndex: 0,
  phase: 'waiting',
};

export function reduceWalkthrough(
  state: WalkthroughState,
  event: WalkthroughEvent,
): WalkthroughState {
  switch (event.type) {
    case 'START':
      return state.phase === 'waiting'
        ? { stageIndex: 0, phase: 'positioning' }
        : state;
    case 'POSITIONED':
      return state.phase === 'positioning'
        ? { ...state, phase: 'revealing' }
        : state;
    case 'SETTLED':
      return state.phase === 'revealing'
        ? { ...state, phase: 'coaching' }
        : state;
    case 'NEXT':
      return state.phase === 'coaching' &&
        state.stageIndex < SUMMARY_WALKTHROUGH_STEPS.length - 1
        ? { stageIndex: state.stageIndex + 1, phase: 'positioning' }
        : state;
    case 'SKIP':
      return state.phase === 'complete'
        ? state
        : { ...state, phase: 'complete' };
    case 'FINISH':
      if (state.phase === 'complete') return state;
      return state.phase === 'coaching' &&
        state.stageIndex === SUMMARY_WALKTHROUGH_STEPS.length - 1
        ? { ...state, phase: 'complete' }
        : state;
    default:
      return state;
  }
}

export function getRevealedGroups(
  stageIndex: number,
  options: { hasAlert: boolean; isWideLayout: boolean },
): SummaryRevealGroup[] {
  const groups = SUMMARY_WALKTHROUGH_STEPS.slice(0, stageIndex + 1)
    .flatMap((step) => step.revealGroups)
    .filter((group) => options.hasAlert || group !== 'alert')
    .filter((group) => options.isWideLayout || group !== 'today');
  return [...new Set(groups)];
}

export function isSummaryWalkthroughPending(onboarding: {
  completed: boolean;
  summaryWalkthroughCompleted: boolean;
}) {
  return onboarding.completed && !onboarding.summaryWalkthroughCompleted;
}

export function isWalkthroughTabDisabled(routeName: string, pending: boolean) {
  return pending && routeName !== 'Summary';
}

export function getTargetScrollY(targetY: number, topClearance: number) {
  return Math.max(0, targetY - topClearance);
}

export function isTargetFullyVisible({
  targetY,
  targetHeight,
  scrollY,
  viewportHeight,
  topClearance,
  bottomClearance,
}: {
  targetY: number;
  targetHeight: number;
  scrollY: number;
  viewportHeight: number;
  topClearance: number;
  bottomClearance: number;
}) {
  const visibleTop = scrollY + topClearance;
  const visibleBottom = scrollY + viewportHeight - bottomClearance;
  return targetY >= visibleTop && targetY + targetHeight <= visibleBottom;
}
