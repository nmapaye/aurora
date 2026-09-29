export type AppWalkthroughRoute = 'Summary' | 'Sleep' | 'Log' | 'Insights';

export type AppWalkthroughRevealGroup =
  | 'summary-header'
  | 'summary-alert'
  | 'summary-pinned'
  | 'summary-today'
  | 'sleep-header'
  | 'sleep-history'
  | 'sleep-data'
  | 'log-header'
  | 'log-quick-add'
  | 'log-details'
  | 'insights-header'
  | 'insights-range'
  | 'insights-reaction';

export type AppWalkthroughAnchor =
  | 'summary-top'
  | 'summary-pinned'
  | 'summary-caffeine'
  | 'summary-sleep'
  | 'sleep-top'
  | 'sleep-data'
  | 'log-top'
  | 'log-details'
  | 'insights-top'
  | 'insights-reaction';

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
    body: 'Estimated alertness and today’s caffeine curve, built from what you record.',
    // The Today hero leads Summary, so it arrives with the header.
    revealGroups: ['summary-header', 'summary-today', 'summary-alert'],
    anchor: 'summary-top',
    primaryAction: 'Next',
  },
  {
    id: 'summary-signals',
    route: 'Summary',
    progress: '2 of 10',
    title: 'Your pinned signals',
    body: 'Caffeine logged today, your latest sleep, and your latest Reaction Test, each with its date and source.',
    revealGroups: ['summary-pinned'],
    anchor: 'summary-pinned',
    primaryAction: 'Next',
  },
  {
    id: 'summary-logging',
    route: 'Summary',
    progress: '3 of 10',
    title: 'Log caffeine',
    body: 'Caffeine Logged opens Log, where you record the amount, time, and source and see recent entries.',
    // Points at the Caffeine Logged signal, Summary's one way into Log.
    revealGroups: [],
    anchor: 'summary-caffeine',
    primaryAction: 'Next',
  },
  {
    id: 'summary-sleep',
    route: 'Summary',
    progress: '4 of 10',
    title: 'Next: your sleep',
    body: 'Sleep comes from Health or your own entries. The Sleep tab shows each night and where it came from.',
    // Points back at the real Sleep signal rather than at empty space.
    revealGroups: [],
    anchor: 'summary-sleep',
    primaryAction: 'Next',
  },
  {
    id: 'sleep-understanding',
    route: 'Sleep',
    progress: '5 of 10',
    title: 'Your recorded nights',
    body: 'Week or Month shows each night you recorded. Tap or drag the chart to read a day; Most Recent Sleep shows its date and source.',
    revealGroups: ['sleep-header', 'sleep-history'],
    anchor: 'sleep-top',
    primaryAction: 'Next',
  },
  {
    id: 'sleep-add-or-connect',
    route: 'Sleep',
    progress: '6 of 10',
    title: 'Where your sleep comes from',
    body: 'Sleep Data holds read-only Health access, manual entries, Sample Data, and every recorded night.',
    // Points at the one Sleep Data entry that opens those controls.
    revealGroups: ['sleep-data'],
    anchor: 'sleep-data',
    primaryAction: 'Next',
  },
  {
    id: 'log-quick-add',
    route: 'Log',
    progress: '7 of 10',
    title: 'Log caffeine',
    body: 'Logged Today totals what you record. Tap a drink to log it now, with Undo right after, or use Custom Entry to set the amount and time.',
    // Logged Today, Quick Add, and Custom Entry share the primary column.
    revealGroups: ['log-header', 'log-quick-add'],
    anchor: 'log-top',
    primaryAction: 'Next',
  },
  {
    id: 'log-details',
    route: 'Log',
    progress: '8 of 10',
    title: 'Fix a mistake',
    body: 'Recent shows each entry’s date, time, amount, and source. Tap one to edit or delete it; Show All Caffeine Data holds the full history.',
    // Points at Recent and the history row, which share one anchor.
    revealGroups: ['log-details'],
    anchor: 'log-details',
    primaryAction: 'Next',
  },
  {
    id: 'insights-patterns',
    route: 'Insights',
    progress: '9 of 10',
    title: 'Your caffeine over time',
    body: 'Choose W, 2W, or M. Tap or drag the chart to read a day; days without entries read as no record, not zero.',
    // The range control and the inspectable chart share one reveal.
    revealGroups: ['insights-header', 'insights-range'],
    anchor: 'insights-top',
    primaryAction: 'Next',
  },
  {
    id: 'insights-learning',
    route: 'Insights',
    progress: '10 of 10',
    title: 'Your Reaction Test',
    body: 'Your latest test shows its date and source. A baseline appears only after 3 tests; Details holds time of day, drinks, and every entry.',
    // Points at the Reaction Test signal; Details sits just below it.
    revealGroups: ['insights-reaction'],
    anchor: 'insights-reaction',
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
