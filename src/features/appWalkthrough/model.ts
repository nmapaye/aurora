export type AppWalkthroughRoute = 'Summary' | 'Sleep' | 'Log' | 'Insights';

export type AppWalkthroughRevealGroup =
  | 'summary-header'
  | 'summary-alert'
  | 'summary-pinned'
  | 'summary-today'
  | 'summary-logging'
  | 'summary-recent'
  | 'sleep-header'
  | 'sleep-history'
  | 'sleep-sources'
  | 'log-header'
  | 'log-quick-add'
  | 'log-details'
  | 'insights-header'
  | 'insights-range'
  | 'insights-highlights';

export type AppWalkthroughAnchor =
  | 'summary-top'
  | 'summary-pinned'
  | 'summary-logging'
  | 'sleep-top'
  | 'sleep-sources'
  | 'log-top'
  | 'log-details'
  | 'insights-top'
  | 'insights-highlights';

export type AppWalkthroughStep = {
  id: string;
  route: AppWalkthroughRoute;
  progress: string;
  title: string;
  body: string;
  revealGroups: readonly AppWalkthroughRevealGroup[];
  anchor: AppWalkthroughAnchor;
  primaryAction: 'Next' | 'Finish';
};

export const WALKTHROUGH_START_DELAY_MS = 300;
export const WALKTHROUGH_SCROLL_SETTLE_MS = 350;
export const WALKTHROUGH_REVEAL_SETTLE_MS = 900;
export const WALKTHROUGH_REDUCED_MOTION_SETTLE_MS = 120;
export const WALKTHROUGH_TOP_CLEARANCE = 24;

export const APP_WALKTHROUGH_STEPS: readonly AppWalkthroughStep[] = [
  {
    id: 'summary-orientation',
    route: 'Summary',
    progress: '1 of 10',
    title: 'Your day at a glance',
    body: 'Aurora brings caffeine, sleep, and alertness together.',
    revealGroups: ['summary-header', 'summary-alert'],
    anchor: 'summary-top',
    primaryAction: 'Next',
  },
  {
    id: 'summary-signals',
    route: 'Summary',
    progress: '2 of 10',
    title: 'See what shapes alertness',
    body: 'These signals show how caffeine, sleep, and vigilance shape your day.',
    revealGroups: ['summary-pinned', 'summary-today'],
    anchor: 'summary-pinned',
    primaryAction: 'Next',
  },
  {
    id: 'summary-logging',
    route: 'Summary',
    progress: '3 of 10',
    title: 'Log in a tap',
    body: 'Use a common amount, or open Custom Entry when you need more detail.',
    revealGroups: ['summary-logging', 'summary-recent'],
    anchor: 'summary-logging',
    primaryAction: 'Next',
  },
  {
    id: 'summary-sleep',
    route: 'Summary',
    progress: '4 of 10',
    title: 'Next: your sleep',
    body: 'See where rest data comes from and how timing shapes tomorrow.',
    revealGroups: [],
    anchor: 'summary-logging',
    primaryAction: 'Next',
  },
  {
    id: 'sleep-understanding',
    route: 'Sleep',
    progress: '5 of 10',
    title: 'Understand your sleep',
    body: 'Use Week or Month to review your real sleep history and recent highlights.',
    revealGroups: ['sleep-header', 'sleep-history'],
    anchor: 'sleep-top',
    primaryAction: 'Next',
  },
  {
    id: 'sleep-add-or-connect',
    route: 'Sleep',
    progress: '6 of 10',
    title: 'Add or connect sleep',
    body: 'Aurora can read Health data or save a manual sleep session.',
    revealGroups: ['sleep-sources'],
    anchor: 'sleep-sources',
    primaryAction: 'Next',
  },
  {
    id: 'log-quick-add',
    route: 'Log',
    progress: '7 of 10',
    title: 'Log in one tap',
    body: 'Use the same quick amounts here and on Summary.',
    revealGroups: ['log-header', 'log-quick-add'],
    anchor: 'log-top',
    primaryAction: 'Next',
  },
  {
    id: 'log-details',
    route: 'Log',
    progress: '8 of 10',
    title: 'Add details when they matter',
    body: 'Custom Entry records amount, source, time, and an optional note.',
    revealGroups: ['log-details'],
    anchor: 'log-details',
    primaryAction: 'Next',
  },
  {
    id: 'insights-patterns',
    route: 'Insights',
    progress: '9 of 10',
    title: 'See patterns over time',
    body: 'Change the range to compare caffeine, timing, and alertness.',
    revealGroups: ['insights-header', 'insights-range'],
    anchor: 'insights-top',
    primaryAction: 'Next',
  },
  {
    id: 'insights-learning',
    route: 'Insights',
    progress: '10 of 10',
    title: 'Keep learning from your trends',
    body: 'Review highlights or open Show All Data whenever you need the details.',
    revealGroups: ['insights-highlights'],
    anchor: 'insights-highlights',
    primaryAction: 'Finish',
  },
];

export const APP_WALKTHROUGH_ROUTE_OWNERSHIP = APP_WALKTHROUGH_STEPS.map(
  (step) => step.route,
);

export function getAppWalkthroughRoute(stepIndex: number) {
  return APP_WALKTHROUGH_STEPS[clampAppWalkthroughStep(stepIndex)].route;
}

export function clampAppWalkthroughStep(step: number) {
  if (!Number.isFinite(step)) return 0;
  return Math.max(0, Math.min(APP_WALKTHROUGH_STEPS.length - 1, Math.floor(step)));
}

export function getRevealedGroups(stepIndex: number): AppWalkthroughRevealGroup[] {
  const clampedStep = clampAppWalkthroughStep(stepIndex);
  const route = APP_WALKTHROUGH_STEPS[clampedStep].route;
  const firstRouteStep = APP_WALKTHROUGH_STEPS.findIndex((step) => step.route === route);

  return [
    ...new Set(
      APP_WALKTHROUGH_STEPS.slice(firstRouteStep, clampedStep + 1).flatMap(
        (step) => step.revealGroups,
      ),
    ),
  ];
}

export type AppWalkthroughPhase =
  | 'waiting'
  | 'positioning'
  | 'revealing'
  | 'coaching'
  | 'complete';

export type AppWalkthroughState = {
  stepIndex: number;
  phase: AppWalkthroughPhase;
};

export type AppWalkthroughEvent =
  | { type: 'START' }
  | { type: 'SYNC'; stepIndex: number }
  | { type: 'POSITIONED' }
  | { type: 'SETTLED' }
  | { type: 'GEOMETRY_CHANGED' }
  | { type: 'NEXT' }
  | { type: 'SKIP' }
  | { type: 'FINISH' };

export const initialAppWalkthroughState: AppWalkthroughState = {
  stepIndex: 0,
  phase: 'waiting',
};

export function reduceAppWalkthrough(
  state: AppWalkthroughState,
  event: AppWalkthroughEvent,
): AppWalkthroughState {
  switch (event.type) {
    case 'SYNC':
      return {
        stepIndex: clampAppWalkthroughStep(event.stepIndex),
        phase:
          state.phase === 'complete'
            ? 'complete'
            : state.phase === 'waiting'
              ? 'waiting'
              : 'positioning',
      };
    case 'START':
      return state.phase === 'waiting'
        ? { stepIndex: clampAppWalkthroughStep(state.stepIndex), phase: 'positioning' }
        : state;
    case 'POSITIONED':
      return state.phase === 'positioning' ? { ...state, phase: 'revealing' } : state;
    case 'SETTLED':
      return state.phase === 'revealing' ? { ...state, phase: 'coaching' } : state;
    case 'GEOMETRY_CHANGED':
      return state.phase === 'revealing' || state.phase === 'coaching'
        ? { ...state, phase: 'positioning' }
        : state;
    case 'NEXT':
      return state.phase === 'coaching' && state.stepIndex < APP_WALKTHROUGH_STEPS.length - 1
        ? { stepIndex: state.stepIndex + 1, phase: 'positioning' }
        : state;
    case 'SKIP':
      return state.phase === 'complete' ? state : { ...state, phase: 'complete' };
    case 'FINISH':
      return state.phase === 'coaching' && state.stepIndex === APP_WALKTHROUGH_STEPS.length - 1
        ? { ...state, phase: 'complete' }
        : state;
    default:
      return state;
  }
}

export function isAppWalkthroughPending(onboarding: {
  completed: boolean;
  appWalkthroughCompleted: boolean;
}) {
  return onboarding.completed && !onboarding.appWalkthroughCompleted;
}

export function isWalkthroughTabDisabled(_routeName: string, pending: boolean) {
  return pending;
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
