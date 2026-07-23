# Summary Walkthrough Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a polished, one-time, four-stage walkthrough that progressively reveals Aurora's real Summary screen immediately after a new user completes setup.

**Architecture:** Keep the real Summary screen as the source of truth. A pure walkthrough model defines stages and transitions, focused presentation components render the reveal and coach card, and a screen-owned hook coordinates layout, scrolling, accessibility, haptics, and persisted completion. Existing users migrate as walkthrough-complete, while new users see the walkthrough once.

**Tech Stack:** Expo SDK 54, React Native 0.81, React 19, TypeScript 5.9, Zustand with MMKV persistence, React Native Reanimated 4, Expo Haptics, React Navigation 7, Jest 29.

## Global Constraints

- Do not run `expo prebuild`; `ios/AURORA.xcworkspace` remains authoritative.
- The walkthrough starts only after the existing three-step setup.
- Use the user's real Summary state and never create sample data or other records.
- The walkthrough has exactly four approved teaching moments and no replay entry point.
- Existing version 3 users with completed onboarding migrate as walkthrough-complete.
- Use the approved soft spring cascade: about 14 pt upward travel, `0.97 → 1` scale, about 80 ms item stagger, and less than one second per stage.
- Keep the coach surface opaque; do not add a scrim, spotlight, blur, or glass effect.
- Skip is always available; Skip and Finish persist completion before dismissing the coach card.
- Disable Summary controls, manual scrolling, and non-Summary tabs while the walkthrough is active.
- Reduce Motion removes translation, scale, spring, stagger, animated scrolling, and haptics.
- Preserve current navigation routes, Health permissions, data import, and all Summary calculations.
- Any persisted field change must update `normalizePersistedState` and `tests/state/store.persistence.spec.ts`.
- Use `@testing-library/react-native@14.0.1`, `test-renderer@1.2.0`, and `jest-expo@54.0.17` only as development dependencies.
- React Native Testing Library 14 uses async APIs: await `render`, `renderHook`, user events, and `act`.
- Every production UI or hook change in Tasks 3–6 must be preceded by an automated UI test that is run and observed failing for the intended missing behavior.
- Keep the existing pure-test project isolated from the new `jest-expo` UI-test project; `npm test -- --runInBand` must execute both.
- Preserve the user's untracked `docs/design-audit.md` and local `.superpowers/` workspace.

## Testing References

- Expo unit testing: `https://docs.expo.dev/develop/unit-testing/`
- React Native Testing Library 14: `https://www.npmjs.com/package/@testing-library/react-native`
- Reanimated Jest setup: `https://docs.swmansion.com/react-native-reanimated/docs/guides/testing/`

## File Structure

### New files

- `src/features/summaryWalkthrough/model.ts` — approved step copy, reveal groups, pure reducer, tab gating, and scroll visibility helpers.
- `src/features/summaryWalkthrough/motion.ts` — pure motion-plan selection for standard and Reduce Motion behavior.
- `src/features/summaryWalkthrough/WalkthroughReveal.tsx` — layout-preserving reveal wrapper.
- `src/features/summaryWalkthrough/SummaryWalkthroughCoach.tsx` — accessible fixed coach card.
- `src/features/summaryWalkthrough/useSummaryWalkthrough.ts` — lifecycle, measurement, scrolling, timers, accessibility, and haptic orchestration.
- `src/features/summaryWalkthrough/index.ts` — public feature exports.
- `src/components/appScreenLayout.ts` — pure bottom-padding calculation for fixed overlays.
- `tests/features/summaryWalkthrough/model.spec.ts` — step, reducer, tab, and scroll-helper tests.
- `tests/features/summaryWalkthrough/motion.spec.ts` — motion and Reduce Motion tests.
- `tests/state/store.walkthrough.spec.ts` — default, action, migration, and setup-flow persistence tests.
- `tests/components/AppScreen.layout.spec.ts` — fixed-overlay padding tests.
- `tests/ui/setup.ts` — `jest-expo` UI-test setup and Reanimated Jest initialization.
- `tests/ui/testingLibrary.smoke.spec.tsx` — React 19 async renderer smoke test.
- `tests/ui/summaryWalkthrough.presentation.spec.tsx` — reveal and coach accessibility/interaction tests.
- `tests/ui/AppScreen.spec.tsx` — controlled scrolling, interaction lock, header transform, and overlay tests.
- `tests/ui/useSummaryWalkthrough.spec.tsx` — timer, scrolling, completion, accessibility, haptic, and Reduce Motion hook tests.
- `tests/ui/RootTabs.walkthrough.spec.tsx` — persisted non-Summary tab gating tests.
- `tests/ui/DashboardScreen.walkthrough.spec.tsx` — real Summary composition and interaction-lock tests.

### Modified files

- `src/state/store.ts` — persisted walkthrough flag, completion action, and version 4 migration.
- `tests/state/store.persistence.spec.ts` — non-default persisted walkthrough fixture.
- `tests/state/store.demo.spec.ts` — reset fixtures and version 3 migration expectations.
- `tests/state/app.spec.ts` — new-user walkthrough state expectations.
- `tests/components/AlertnessRing.spec.tsx` — complete the onboarding fixture shape.
- `src/components/AppScreen.tsx` — optional refs, interaction lock, header transform, scroll callbacks, and fixed overlay.
- `src/navigation/RootTabs.tsx` — disable non-Summary tabs while the walkthrough is pending.
- `src/screens/DashboardScreen.tsx` — compose the controller, anchors, reveal groups, and coach card around current content.
- `package.json` and `package-lock.json` — React Native component-test development dependencies.
- `jest.config.ts` — separate pure and `jest-expo` UI projects under one Jest command.

---

### Task 1: Persist the one-time walkthrough lifecycle

**Files:**

- Create: `tests/state/store.walkthrough.spec.ts`
- Modify: `src/state/store.ts:25-54,76-99,103-111,138-186,198-204`
- Modify: `tests/state/store.persistence.spec.ts:8-60`
- Modify: `tests/state/store.demo.spec.ts:5-24,142-211`
- Modify: `tests/state/app.spec.ts:4-65`
- Modify: `tests/components/AlertnessRing.spec.tsx:4-13`

**Interfaces:**

- Produces: `onboarding.summaryWalkthroughCompleted: boolean`
- Produces: `completeSummaryWalkthrough(): void`
- Produces: persisted store version `4`
- Consumes: existing `completeOnboarding()` and `loadDemoData()` actions without changing their data behavior

- [ ] **Step 1: Write the failing lifecycle and migration tests**

Create `tests/state/store.walkthrough.spec.ts`:

```ts
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
```

Add `summaryWalkthroughCompleted: true` to the non-default `onboarding` fixture
in `tests/state/store.persistence.spec.ts`, and change that round-trip
fixture's serialized version from `3` to `4`. Add
`summaryWalkthroughCompleted: false` to every full onboarding reset fixture in
`tests/state/store.demo.spec.ts`, `tests/state/app.spec.ts`, and
`tests/components/AlertnessRing.spec.tsx`.

In `tests/state/store.demo.spec.ts`, rename the version 3 hydration test to
`migrates completed version 3 onboarding as walkthrough-complete` and add:

```ts
expect(state.onboarding.summaryWalkthroughCompleted).toBe(true);
```

In its version 1 migration test, add:

```ts
expect(state.onboarding.summaryWalkthroughCompleted).toBe(false);
```

- [ ] **Step 2: Run the focused tests to verify they fail**

Run:

```bash
npm test -- --runInBand tests/state/store.walkthrough.spec.ts tests/state/store.persistence.spec.ts
```

Expected: FAIL because `summaryWalkthroughCompleted` and
`completeSummaryWalkthrough` do not exist and the persisted fixture no longer
matches the store shape.

- [ ] **Step 3: Implement the store field, action, normalization, and migration**

In `src/state/store.ts`, extend `Onboarding` and `State`:

```ts
type Onboarding = {
  completed: boolean;
  source: OnboardingSource;
  permissionStatus: HealthPermissionStatus;
  completedAt?: number;
  summaryWalkthroughCompleted: boolean;
};

type State = {
  doses: Dose[];
  sleeps: SleepSession[];
  vigilanceSessions: VigilanceSession[];
  prefs: Prefs;
  onboarding: Onboarding;
  healthSync: HealthSync;
  demoMode: boolean;
  appearanceMode: AppearanceMode;
  addDose: (d: Dose) => void;
  updateDose: (id: string, patch: Partial<Omit<Dose, 'id'>>) => void;
  removeDose: (id: string) => void;
  addSleep: (s: SleepSession) => void;
  upsertSleepSessions: (items: SleepSession[]) => void;
  addVigilanceSession: (session: VigilanceSession) => void;
  setPrefs: (p: Partial<Prefs>) => void;
  setOnboarding: (p: Partial<Onboarding>) => void;
  setHealthSync: (p: Partial<HealthSync>) => void;
  setAppearanceMode: (mode: AppearanceMode) => void;
  loadDemoData: () => void;
  clearDemoData: () => void;
  completeOnboarding: (p?: Partial<Onboarding>) => void;
  completeSummaryWalkthrough: () => void;
};
```

Update the default:

```ts
const defaultOnboarding: Onboarding = {
  completed: false,
  source: 'healthkit',
  permissionStatus: 'idle',
  summaryWalkthroughCompleted: false,
};
```

Add the action after `completeOnboarding`:

```ts
completeSummaryWalkthrough: () =>
  set((s) => ({
    onboarding: {
      ...s.onboarding,
      summaryWalkthroughCompleted: true,
    },
  })),
```

Change the persistence version and migration:

```ts
version: 4,
migrate: (persistedState, version) => {
  let nextState = (persistedState ?? {}) as Partial<PersistedState>;

  if (version < 2) {
    nextState = { ...nextState, vigilanceSessions: [] };
  }

  if (version < 4) {
    const legacyOnboarding = nextState.onboarding as
      | Partial<Onboarding>
      | undefined;
    nextState = {
      ...nextState,
      onboarding: {
        ...legacyOnboarding,
        summaryWalkthroughCompleted:
          legacyOnboarding?.completed === true,
      } as Onboarding,
    };
  }

  return normalizePersistedState(nextState);
},
```

Keep the existing `normalizePersistedState` spread:

```ts
onboarding: { ...defaultOnboarding, ...persistedState?.onboarding },
```

This line is required because it supplies `false` for new and incomplete
same-version state.

- [ ] **Step 4: Run the store tests and type-check**

Run:

```bash
npm test -- --runInBand tests/state/store.walkthrough.spec.ts tests/state/store.persistence.spec.ts tests/state/store.demo.spec.ts tests/state/app.spec.ts tests/components/AlertnessRing.spec.tsx
npm run type-check
```

Expected: all selected suites PASS and TypeScript exits with code 0.

- [ ] **Step 5: Commit the persisted lifecycle**

```bash
git add src/state/store.ts tests/state/store.walkthrough.spec.ts tests/state/store.persistence.spec.ts tests/state/store.demo.spec.ts tests/state/app.spec.ts tests/components/AlertnessRing.spec.tsx
git commit -m "feat: persist Summary walkthrough completion"
```

---

### Task 2: Define the walkthrough model and state machine

**Files:**

- Create: `src/features/summaryWalkthrough/model.ts`
- Create: `tests/features/summaryWalkthrough/model.spec.ts`

**Interfaces:**

- Consumes: `onboarding.completed` and `onboarding.summaryWalkthroughCompleted`
- Produces: `SUMMARY_WALKTHROUGH_STEPS`
- Produces: `SummaryWalkthroughStageId`, `SummaryRevealGroup`, `SummaryAnchorId`
- Produces: `initialWalkthroughState` and `reduceWalkthrough(state, event)`
- Produces: `getRevealedGroups(stageIndex, options)`
- Produces: `isSummaryWalkthroughPending(onboarding)`
- Produces: `isWalkthroughTabDisabled(routeName, pending)`
- Produces: `isTargetFullyVisible(...)` and `getTargetScrollY(...)`

- [ ] **Step 1: Write the failing pure-model tests**

Create `tests/features/summaryWalkthrough/model.spec.ts`:

```ts
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
```

- [ ] **Step 2: Run the model test to verify it fails**

Run:

```bash
npm test -- --runInBand tests/features/summaryWalkthrough/model.spec.ts
```

Expected: FAIL because `model.ts` does not exist.

- [ ] **Step 3: Implement the pure model**

Create `src/features/summaryWalkthrough/model.ts`:

```ts
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
export const WALKTHROUGH_REVEAL_SETTLE_MS = 700;
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
    case 'FINISH':
      return { ...state, phase: 'complete' };
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
  return (
    onboarding.completed && !onboarding.summaryWalkthroughCompleted
  );
}

export function isWalkthroughTabDisabled(
  routeName: string,
  pending: boolean,
) {
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
  return (
    targetY >= visibleTop &&
    targetY + targetHeight <= visibleBottom
  );
}
```

- [ ] **Step 4: Run the model tests**

Run:

```bash
npm test -- --runInBand tests/features/summaryWalkthrough/model.spec.ts
npm run type-check
```

Expected: the model suite PASSes and TypeScript exits with code 0.

- [ ] **Step 5: Commit the pure model**

```bash
git add src/features/summaryWalkthrough/model.ts tests/features/summaryWalkthrough/model.spec.ts
git commit -m "feat: define Summary walkthrough stages"
```

---

### Task 3: Build the reveal and coach presentation components

**Files:**

- Create: `src/features/summaryWalkthrough/motion.ts`
- Create: `src/features/summaryWalkthrough/WalkthroughReveal.tsx`
- Create: `src/features/summaryWalkthrough/SummaryWalkthroughCoach.tsx`
- Create: `src/features/summaryWalkthrough/index.ts`
- Create: `tests/features/summaryWalkthrough/motion.spec.ts`
- Create: `tests/ui/setup.ts`
- Create: `tests/ui/testingLibrary.smoke.spec.tsx`
- Create: `tests/ui/summaryWalkthrough.presentation.spec.tsx`
- Modify: `package.json`
- Modify: `package-lock.json`
- Modify: `jest.config.ts`

**Interfaces:**

- Consumes: `SummaryWalkthroughStep` from Task 2
- Produces: `getRevealMotionPlan(reduceMotion, staggerIndex)`
- Produces: `<WalkthroughReveal active revealed reduceMotion staggerIndex>`
- Produces: `<SummaryWalkthroughCoach step locked headingRef onSkip onPrimary>`
- Produces: separate `unit` and `ui` Jest projects executed together by `npm test`

- [ ] **Step 1: Install the React 19-compatible UI test dependencies**

Run:

```bash
npm install --save-dev @testing-library/react-native@14.0.1 test-renderer@1.2.0 jest-expo@54.0.17
```

Expected: `package.json` and `package-lock.json` add only development
dependencies. Do not install or import `react-test-renderer` directly.

- [ ] **Step 2: Split Jest into isolated pure and UI projects**

Replace `jest.config.ts` with:

```ts
import type { Config } from 'jest';

const shared = {
  moduleNameMapper: {
    '^~/(.*)$': '<rootDir>/src/$1',
  },
};

const unitProject: Config = {
  displayName: 'unit',
  roots: ['<rootDir>/tests'],
  testMatch: ['**/?(*.)+(spec|test).+(ts|tsx|js)'],
  testPathIgnorePatterns: ['<rootDir>/tests/ui/'],
  transform: {
    '^.+\\.(ts|tsx)$': [
      'ts-jest',
      {
        tsconfig: {
          target: 'ES2020',
          module: 'commonjs',
          jsx: 'react-jsx',
          strict: true,
          esModuleInterop: true,
          skipLibCheck: true,
        },
      },
    ],
  },
  ...shared,
  testEnvironment: 'node',
  setupFilesAfterEnv: ['<rootDir>/tests/setup.ts'],
};

const uiProject: Config = {
  displayName: 'ui',
  preset: 'jest-expo',
  roots: ['<rootDir>/tests/ui'],
  testMatch: ['**/?(*.)+(spec|test).+(ts|tsx|js)'],
  ...shared,
  setupFilesAfterEnv: ['<rootDir>/tests/ui/setup.ts'],
  transformIgnorePatterns: [
    'node_modules/(?!((jest-)?react-native|@react-native(-community)?)|expo(nent)?|@expo(nent)?/.*|@react-navigation/.*|react-native-reanimated|react-native-worklets|react-native-svg)',
  ],
};

const config: Config = {
  projects: [unitProject, uiProject],
};

export default config;
```

Create `tests/ui/setup.ts`:

```ts
require('react-native-reanimated').setUpTests();
```

Create `tests/ui/testingLibrary.smoke.spec.tsx`:

```tsx
import React from 'react';
import { render, screen } from '@testing-library/react-native';
import { Text } from 'react-native';

describe('React Native component test harness', () => {
  it('renders React 19 host components through the async API', async () => {
    await render(<Text accessibilityRole="header">Aurora UI test</Text>);

    expect(
      screen.getByRole('header', { name: 'Aurora UI test' }),
    ).toBeOnTheScreen();
  });
});
```

- [ ] **Step 3: Verify both Jest projects before production UI changes**

Run:

```bash
npm test -- --runInBand
```

Expected: the existing 15 suites and 47 tests PASS in the `unit` project, and
the new UI smoke test PASSes in the `ui` project.

- [ ] **Step 4: Write the failing motion and presentation tests**

Create `tests/features/summaryWalkthrough/motion.spec.ts`:

```ts
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
```

Create `tests/ui/summaryWalkthrough.presentation.spec.tsx`:

```tsx
import React, { createRef } from 'react';
import { render, screen, userEvent } from '@testing-library/react-native';
import { Text } from 'react-native';

import {
  SUMMARY_WALKTHROUGH_STEPS,
  SummaryWalkthroughCoach,
  WalkthroughReveal,
} from '~/features/summaryWalkthrough';

jest.mock('~/hooks/useAppScheme', () => ({
  __esModule: true,
  default: () => 'light',
}));

describe('Summary walkthrough presentation', () => {
  it('hides unrevealed content from touch and accessibility', async () => {
    await render(
      <WalkthroughReveal
        active
        revealed={false}
        reduceMotion={false}
        testID="walkthrough-reveal"
      >
        <Text>Hidden metric</Text>
      </WalkthroughReveal>,
    );

    expect(screen.getByTestId('walkthrough-reveal')).toHaveProp(
      'accessibilityElementsHidden',
      true,
    );
    expect(screen.getByTestId('walkthrough-reveal')).toHaveProp(
      'importantForAccessibility',
      'no-hide-descendants',
    );
    expect(screen.getByTestId('walkthrough-reveal')).toHaveProp(
      'pointerEvents',
      'none',
    );
  });

  it('exposes approved coach copy and working actions', async () => {
    const onSkip = jest.fn();
    const onPrimary = jest.fn();
    const user = userEvent.setup();

    await render(
      <SummaryWalkthroughCoach
        step={SUMMARY_WALKTHROUGH_STEPS[0]}
        locked={false}
        headingRef={createRef()}
        onSkip={onSkip}
        onPrimary={onPrimary}
      />,
    );

    expect(
      screen.getByRole('header', { name: 'Your day at a glance' }),
    ).toBeOnTheScreen();
    expect(screen.getByText('1 of 4')).toBeOnTheScreen();
    await user.press(screen.getByRole('button', { name: 'Skip' }));
    await user.press(screen.getByRole('button', { name: 'Next' }));
    expect(onSkip).toHaveBeenCalledTimes(1);
    expect(onPrimary).toHaveBeenCalledTimes(1);
  });

  it('disables both actions while a transition is locked', async () => {
    await render(
      <SummaryWalkthroughCoach
        step={SUMMARY_WALKTHROUGH_STEPS[1]}
        locked
        headingRef={createRef()}
        onSkip={jest.fn()}
        onPrimary={jest.fn()}
      />,
    );

    expect(screen.getByRole('button', { name: 'Skip' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Next' })).toBeDisabled();
  });
});
```

- [ ] **Step 5: Run both new tests and verify RED**

Run:

```bash
npm test -- --runInBand tests/features/summaryWalkthrough/motion.spec.ts tests/ui/summaryWalkthrough.presentation.spec.tsx
```

Expected: FAIL because `motion.ts`, `WalkthroughReveal`, and
`SummaryWalkthroughCoach` do not exist. Confirm the UI harness itself does not
fail.

- [ ] **Step 6: Implement the pure motion plan**

Create `src/features/summaryWalkthrough/motion.ts`:

```ts
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
```

- [ ] **Step 7: Implement the layout-preserving reveal wrapper**

Create `src/features/summaryWalkthrough/WalkthroughReveal.tsx`:

```tsx
import React, { useEffect } from 'react';
import type { StyleProp, ViewStyle } from 'react-native';
import Animated, {
  useAnimatedStyle,
  useSharedValue,
  withDelay,
  withSpring,
  withTiming,
} from 'react-native-reanimated';

import { getRevealMotionPlan } from './motion';

type Props = {
  active: boolean;
  revealed: boolean;
  reduceMotion: boolean;
  staggerIndex?: number;
  children: React.ReactNode;
  style?: StyleProp<ViewStyle>;
  testID?: string;
};

export default function WalkthroughReveal({
  active,
  revealed,
  reduceMotion,
  staggerIndex = 0,
  children,
  style,
  testID,
}: Props) {
  const progress = useSharedValue(active ? 0 : 1);
  const plan = getRevealMotionPlan(reduceMotion, staggerIndex);

  useEffect(() => {
    if (!active) {
      progress.value = 1;
      return;
    }

    if (revealed) {
      const animation =
        plan.mode === 'timing'
          ? withTiming(1, { duration: plan.durationMs })
          : withSpring(1, {
              damping: 22,
              stiffness: 220,
              mass: 0.65,
              overshootClamping: true,
            });
      progress.value = withDelay(plan.delayMs, animation);
      return;
    }

    progress.value = 0;
  }, [
    active,
    plan.delayMs,
    plan.durationMs,
    plan.mode,
    progress,
    revealed,
  ]);

  const animatedStyle = useAnimatedStyle(() => ({
    opacity: progress.value,
    transform: [
      {
        translateY:
          plan.initialTranslateY * (1 - progress.value),
      },
      {
        scale:
          plan.initialScale +
          (1 - plan.initialScale) * progress.value,
      },
    ],
  }));

  const hidden = active && !revealed;

  return (
    <Animated.View
      testID={testID}
      accessibilityElementsHidden={hidden}
      importantForAccessibility={
        hidden ? 'no-hide-descendants' : 'auto'
      }
      pointerEvents={hidden ? 'none' : 'auto'}
      style={[style, animatedStyle]}
    >
      {children}
    </Animated.View>
  );
}
```

- [ ] **Step 8: Implement the accessible coach card**

Create `src/features/summaryWalkthrough/SummaryWalkthroughCoach.tsx`:

```tsx
import React from 'react';
import type { RefObject } from 'react';
import type { Text as TextInstance } from 'react-native';
import { Text, View } from 'react-native';

import Button from '~/components/Button';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import {
  fontScaling,
  radii,
  spacing,
  typeRamp,
} from '~/theme/tokens';
import type { SummaryWalkthroughStep } from './model';

type Props = {
  step: SummaryWalkthroughStep;
  locked: boolean;
  headingRef: RefObject<TextInstance | null>;
  onSkip: () => void;
  onPrimary: () => void;
};

export default function SummaryWalkthroughCoach({
  step,
  locked,
  headingRef,
  onSkip,
  onPrimary,
}: Props) {
  const palette = getAppPalette(useAppScheme());

  return (
    <View
      accessibilityViewIsModal
      style={{
        width: '100%',
        maxWidth: 560,
        alignSelf: 'center',
        gap: spacing.sm,
        padding: spacing.md,
        borderRadius: radii.hero,
        backgroundColor: palette.card,
        borderWidth: 1,
        borderColor: palette.cardBorder,
        shadowColor: '#000000',
        shadowOpacity: 0.14,
        shadowRadius: 18,
        shadowOffset: { width: 0, height: 8 },
        elevation: 6,
      }}
    >
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.footnote,
          fontWeight: '600',
          color: palette.tint,
        }}
      >
        {step.progress}
      </Text>
      <Text
        ref={headingRef}
        accessibilityRole="header"
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.title3,
          color: palette.textPrimary,
        }}
      >
        {step.title}
      </Text>
      <Text
        maxFontSizeMultiplier={fontScaling.body}
        style={{
          ...typeRamp.body,
          color: palette.textSecondary,
        }}
      >
        {step.body}
      </Text>
      <View
        style={{
          flexDirection: 'row',
          justifyContent: 'flex-end',
          alignItems: 'center',
          gap: spacing.sm,
        }}
      >
        <Button
          title="Skip"
          variant="plain"
          disabled={locked}
          onPress={onSkip}
        />
        <Button
          title={step.primaryAction}
          variant="primary"
          disabled={locked}
          onPress={onPrimary}
        />
      </View>
    </View>
  );
}
```

Create `src/features/summaryWalkthrough/index.ts`:

```ts
export { default as SummaryWalkthroughCoach } from './SummaryWalkthroughCoach';
export { default as WalkthroughReveal } from './WalkthroughReveal';
export * from './model';
export * from './motion';
```

- [ ] **Step 9: Run presentation tests, type-check, and lint the feature**

Run:

```bash
npm test -- --runInBand tests/features/summaryWalkthrough/motion.spec.ts tests/ui/summaryWalkthrough.presentation.spec.tsx tests/ui/testingLibrary.smoke.spec.tsx
npm run type-check
npx eslint src/features/summaryWalkthrough tests/features/summaryWalkthrough tests/ui
```

Expected: the pure motion and UI presentation suites PASS, TypeScript exits
with code 0, and ESLint reports no errors.

- [ ] **Step 10: Commit the test harness and presentation layer**

```bash
git add package.json package-lock.json jest.config.ts tests/ui/setup.ts tests/ui/testingLibrary.smoke.spec.tsx tests/ui/summaryWalkthrough.presentation.spec.tsx src/features/summaryWalkthrough tests/features/summaryWalkthrough/motion.spec.ts
git commit -m "feat: add Summary walkthrough presentation"
```

---

### Task 4: Extend AppScreen for controlled walkthrough content

**Files:**

- Create: `src/components/appScreenLayout.ts`
- Create: `tests/components/AppScreen.layout.spec.ts`
- Create: `tests/ui/AppScreen.spec.tsx`
- Modify: `src/components/AppScreen.tsx:1-136`

**Interfaces:**

- Produces: `getAppScreenBottomPadding(safeInset, overlayHeight)`
- Produces optional `AppScreen` props:
  - `scrollRef`
  - `contentRef`
  - `scrollEnabled`
  - `interactionEnabled`
  - `bottomOverlay`
  - `headerTransform`
  - `onScroll`
  - `onViewportLayout`
- Preserves all existing `AppScreen` behavior when these props are omitted

- [ ] **Step 1: Write the failing layout and AppScreen behavior tests**

Create `tests/components/AppScreen.layout.spec.ts`:

```ts
import { getAppScreenBottomPadding } from '~/components/appScreenLayout';

describe('AppScreen overlay layout', () => {
  it('keeps the existing base and safe-area padding without an overlay', () => {
    expect(getAppScreenBottomPadding(20, 0)).toBe(52);
  });

  it('reserves measured space for a Dynamic Type coach card', () => {
    expect(getAppScreenBottomPadding(20, 180)).toBe(244);
  });
});
```

Create `tests/ui/AppScreen.spec.tsx`:

```tsx
import React from 'react';
import {
  fireEvent,
  render,
  screen,
} from '@testing-library/react-native';
import { StyleSheet, Text, View } from 'react-native';

import AppScreen from '~/components/AppScreen';

jest.mock('~/hooks/useAdaptiveLayout', () => ({
  __esModule: true,
  default: () => ({
    isWideLayout: false,
    topChromeBuffer: 0,
    horizontalPadding: 16,
    contentMaxWidth: 600,
  }),
}));
jest.mock('~/hooks/useAppScheme', () => ({
  __esModule: true,
  default: () => 'light',
}));
jest.mock('~/navigation', () => ({ navigate: jest.fn() }));
jest.mock('react-native-safe-area-context', () => ({
  useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 20, left: 0 }),
}));

describe('AppScreen walkthrough controls', () => {
  it('locks content, transforms the header, and reserves overlay space', async () => {
    await render(
      <AppScreen
        title="Summary"
        trailing={<Text>Settings</Text>}
        interactionEnabled={false}
        bottomOverlay={<Text>Coach</Text>}
        headerTransform={(header) => (
          <View testID="transformed-header">{header}</View>
        )}
      >
        <Text>Main content</Text>
      </AppScreen>,
    );

    await fireEvent(
      screen.getByTestId('app-screen-overlay'),
      'layout',
      {
        nativeEvent: {
          layout: { x: 0, y: 0, width: 320, height: 180 },
        },
      },
    );

    expect(screen.getByTestId('app-screen-content')).toHaveProp(
      'pointerEvents',
      'none',
    );
    expect(screen.getByTestId('transformed-header')).toBeOnTheScreen();
    expect(screen.getByText('Coach')).toBeOnTheScreen();

    const styles = StyleSheet.flatten(
      screen.getByTestId('app-screen-scroll').props
        .contentContainerStyle,
    );
    expect(styles.paddingBottom).toBe(244);
  });
});
```

- [ ] **Step 2: Run the layout test to verify it fails**

Run:

```bash
npm test -- --runInBand tests/components/AppScreen.layout.spec.ts tests/ui/AppScreen.spec.tsx
```

Expected: FAIL because `appScreenLayout.ts` and the AppScreen walkthrough props
and test IDs do not exist.

- [ ] **Step 3: Implement the pure padding calculation**

Create `src/components/appScreenLayout.ts`:

```ts
import { spacing } from '~/theme/tokens';

export function getAppScreenBottomPadding(
  safeInset: number,
  overlayHeight: number,
) {
  return (
    spacing.xxl +
    Math.max(0, safeInset) +
    Math.max(0, overlayHeight)
  );
}
```

- [ ] **Step 4: Add the optional AppScreen control surface**

Update `src/components/AppScreen.tsx` imports to include:

```ts
import React, { useState } from 'react';
import type { RefObject } from 'react';
import {
  LayoutChangeEvent,
  NativeScrollEvent,
  NativeSyntheticEvent,
  Pressable,
  ScrollView,
  StyleProp,
  Text,
  View,
  ViewStyle,
} from 'react-native';
import { getAppScreenBottomPadding } from './appScreenLayout';
```

Extend `Props`:

```ts
type Props = {
  title: string;
  subtitle?: string;
  children: React.ReactNode;
  trailing?: React.ReactNode;
  contentStyle?: StyleProp<ViewStyle>;
  centered?: boolean;
  showsVerticalScrollIndicator?: boolean;
  topInset?: number;
  scrollRef?: RefObject<ScrollView | null>;
  contentRef?: RefObject<View | null>;
  scrollEnabled?: boolean;
  interactionEnabled?: boolean;
  bottomOverlay?: React.ReactNode;
  headerTransform?: (header: React.ReactNode) => React.ReactNode;
  onScroll?: (
    event: NativeSyntheticEvent<NativeScrollEvent>,
  ) => void;
  onViewportLayout?: (event: LayoutChangeEvent) => void;
};
```

Destructure the new props with safe defaults and track overlay height:

```ts
scrollRef,
contentRef,
scrollEnabled = true,
interactionEnabled = true,
bottomOverlay,
headerTransform,
onScroll,
onViewportLayout,
```

```ts
const [overlayHeight, setOverlayHeight] = useState(0);
const bottomPadding = getAppScreenBottomPadding(
  insets.bottom,
  bottomOverlay ? overlayHeight + spacing.sm : 0,
);
```

Extract the current header JSX into a `header` constant without changing its
contents:

```tsx
const header = (
  <View style={{ gap: spacing.sm }}>
    <View
      style={{
        flexDirection: 'row',
        alignItems: 'flex-start',
        gap: spacing.sm,
      }}
    >
      <View style={{ flex: 1, gap: spacing.xxs }}>
        <Text
          maxFontSizeMultiplier={fontScaling.body}
          style={{
            ...typeRamp.largeTitle,
            letterSpacing: 0,
            color: palette.textPrimary,
          }}
        >
          {title}
        </Text>
        {subtitle ? (
          <Text
            maxFontSizeMultiplier={fontScaling.body}
            style={{
              ...typeRamp.subheadline,
              color: palette.textSecondary,
            }}
          >
            {subtitle}
          </Text>
        ) : null}
      </View>
      {trailing ?? (
        <Pressable
          accessibilityRole="button"
          accessibilityLabel="Open settings"
          onPress={() => navigate('Settings')}
          style={({ pressed }) => ({
            minWidth: 44,
            minHeight: 44,
            borderRadius: radii.capsule,
            alignItems: 'center',
            justifyContent: 'center',
            backgroundColor: pressed
              ? palette.pressed
              : palette.cardMuted,
            borderWidth: 1,
            borderColor: palette.cardBorder,
          })}
        >
          <AppIcon
            name={appIcons.settings}
            size={iconSizes.button}
            color={palette.textPrimary}
          />
        </Pressable>
      )}
    </View>
  </View>
);
```

Replace the return value with a fixed-overlay shell:

```tsx
return (
  <View
    testID="app-screen-root"
    onLayout={onViewportLayout}
    style={{ flex: 1, backgroundColor: palette.groupedBackground }}
  >
    <ScrollView
      testID="app-screen-scroll"
      ref={scrollRef}
      contentInsetAdjustmentBehavior="automatic"
      showsVerticalScrollIndicator={showsVerticalScrollIndicator}
      scrollEnabled={scrollEnabled}
      onScroll={onScroll}
      scrollEventThrottle={16}
      style={{ flex: 1, backgroundColor: palette.groupedBackground }}
      contentContainerStyle={[
        {
          paddingTop: topInset + layout.topChromeBuffer,
          paddingBottom: bottomPadding,
          paddingHorizontal: layout.horizontalPadding,
          alignItems:
            centered || layout.isWideLayout ? 'center' : undefined,
        },
        contentStyle,
      ]}
    >
      <View
        testID="app-screen-content"
        ref={contentRef}
        pointerEvents={interactionEnabled ? 'auto' : 'none'}
        style={{
          width: '100%',
          maxWidth: layout.contentMaxWidth,
          gap: spacing.md,
        }}
      >
        {headerTransform ? headerTransform(header) : header}
        {children}
      </View>
    </ScrollView>
    {bottomOverlay ? (
      <View
        testID="app-screen-overlay"
        pointerEvents="box-none"
        onLayout={(event) =>
          setOverlayHeight(event.nativeEvent.layout.height)
        }
        style={{
          position: 'absolute',
          left: layout.horizontalPadding,
          right: layout.horizontalPadding,
          bottom: spacing.sm,
        }}
      >
        {bottomOverlay}
      </View>
    ) : null}
  </View>
);
```

- [ ] **Step 5: Run focused tests and compile the unchanged callers**

Run:

```bash
npm test -- --runInBand tests/components/AppScreen.layout.spec.ts tests/ui/AppScreen.spec.tsx
npm run type-check
npx eslint src/components/AppScreen.tsx src/components/appScreenLayout.ts tests/components/AppScreen.layout.spec.ts tests/ui/AppScreen.spec.tsx
```

Expected: the pure layout and AppScreen UI suites PASS, all existing callers
compile unchanged, and ESLint reports no errors.

- [ ] **Step 6: Commit the AppScreen extension**

```bash
git add src/components/AppScreen.tsx src/components/appScreenLayout.ts tests/components/AppScreen.layout.spec.ts tests/ui/AppScreen.spec.tsx
git commit -m "feat: support guided AppScreen overlays"
```

---

### Task 5: Implement walkthrough orchestration

**Files:**

- Modify: `src/features/summaryWalkthrough/model.ts`
- Modify: `tests/features/summaryWalkthrough/model.spec.ts`
- Create: `src/features/summaryWalkthrough/useSummaryWalkthrough.ts`
- Modify: `src/features/summaryWalkthrough/index.ts`
- Create: `tests/ui/useSummaryWalkthrough.spec.tsx`

**Interfaces:**

- Consumes: Task 2 reducer and Task 4 `scrollRef` and `contentRef`
- Consumes: `completeSummaryWalkthrough(): void` through an injected `onComplete`
- Produces: `useSummaryWalkthrough(options)`
- Produces: anchor measurement, viewport and scroll callbacks, reveal queries, coach state, and Skip/Next/Finish actions

- [ ] **Step 1: Add failing reducer and hook lifecycle tests**

Extend `tests/features/summaryWalkthrough/model.spec.ts`:

```ts
it('treats a target hidden behind the coach card as not fully visible', () => {
  expect(
    isTargetFullyVisible({
      targetY: 500,
      targetHeight: 120,
      scrollY: 100,
      viewportHeight: 600,
      topClearance: 24,
      bottomClearance: 180,
    }),
  ).toBe(false);
});

it('ignores duplicate settle and finish events', () => {
  const coaching = { stageIndex: 1, phase: 'coaching' } as const;
  expect(
    reduceWalkthrough(coaching, { type: 'SETTLED' }),
  ).toEqual(coaching);

  const complete = { stageIndex: 3, phase: 'complete' } as const;
  expect(
    reduceWalkthrough(complete, { type: 'FINISH' }),
  ).toBe(complete);
});
```

Create `tests/ui/useSummaryWalkthrough.spec.tsx`:

```tsx
import type { RefObject } from 'react';
import {
  act,
  renderHook,
} from '@testing-library/react-native';
import {
  AccessibilityInfo,
  type LayoutChangeEvent,
  type ScrollView,
  type View,
} from 'react-native';
import * as Haptics from 'expo-haptics';

import useSummaryWalkthrough from '~/features/summaryWalkthrough/useSummaryWalkthrough';

jest.mock('expo-haptics', () => ({
  selectionAsync: jest.fn().mockResolvedValue(undefined),
}));

const scrollRef = {
  current: { scrollTo: jest.fn() },
} as unknown as RefObject<ScrollView | null>;
const contentRef = {
  current: {},
} as RefObject<View | null>;

function viewportEvent(height = 640) {
  return {
    nativeEvent: {
      layout: { x: 0, y: 0, width: 390, height },
    },
  } as LayoutChangeEvent;
}

describe('useSummaryWalkthrough', () => {
  beforeEach(() => {
    jest.useFakeTimers();
    jest.spyOn(
      AccessibilityInfo,
      'isReduceMotionEnabled',
    ).mockResolvedValue(false);
    jest.spyOn(
      AccessibilityInfo,
      'addEventListener',
    ).mockReturnValue({ remove: jest.fn() });
    jest.spyOn(
      AccessibilityInfo,
      'announceForAccessibility',
    ).mockImplementation(() => {});
    jest.spyOn(
      AccessibilityInfo,
      'setAccessibilityFocus',
    ).mockImplementation(() => {});
  });

  afterEach(() => {
    jest.useRealTimers();
    jest.restoreAllMocks();
  });

  it('waits for layout, reveals stage one, and exposes its coach', async () => {
    const onComplete = jest.fn();
    const result = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: true,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete,
      }),
    );

    await act(async () => {
      result.current.onViewportLayout(viewportEvent());
      await Promise.resolve();
      jest.advanceTimersByTime(300);
      jest.runOnlyPendingTimers();
      jest.advanceTimersByTime(700);
    });

    expect(result.current.coachVisible).toBe(true);
    expect(result.current.step.id).toBe('orientation');
    expect(result.current.isRevealed('header')).toBe(true);
    expect(
      AccessibilityInfo.announceForAccessibility,
    ).toHaveBeenCalledWith(
      'Your day at a glance. Aurora brings caffeine, sleep, and alertness together.',
    );
    expect(Haptics.selectionAsync).toHaveBeenCalledTimes(1);
  });

  it('persists completion before dismissing on Skip', async () => {
    const onComplete = jest.fn();
    const result = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete,
      }),
    );

    await act(async () => {
      result.current.onSkip();
    });

    expect(onComplete).toHaveBeenCalledTimes(1);
    expect(result.current.active).toBe(false);
    expect(result.current.isRevealed('recent')).toBe(true);
  });

  it('removes haptics and long settling when Reduce Motion is enabled', async () => {
    jest.mocked(
      AccessibilityInfo.isReduceMotionEnabled,
    ).mockResolvedValue(true);
    const result = await renderHook(() =>
      useSummaryWalkthrough({
        enabled: true,
        hasAlert: false,
        isWideLayout: false,
        scrollRef,
        contentRef,
        onComplete: jest.fn(),
      }),
    );

    await act(async () => {
      result.current.onViewportLayout(viewportEvent());
      await Promise.resolve();
      jest.advanceTimersByTime(300);
      jest.runOnlyPendingTimers();
      jest.advanceTimersByTime(120);
    });

    expect(result.current.coachVisible).toBe(true);
    expect(result.current.reduceMotion).toBe(true);
    expect(Haptics.selectionAsync).not.toHaveBeenCalled();
  });
});
```

- [ ] **Step 2: Run the model test and observe the duplicate-Finish failure**

Run:

```bash
npm test -- --runInBand tests/features/summaryWalkthrough/model.spec.ts tests/ui/useSummaryWalkthrough.spec.tsx
```

Expected: FAIL because the current reducer returns a new completed state for a
duplicate Finish event and `useSummaryWalkthrough.ts` does not exist.

- [ ] **Step 3: Make completion idempotent**

Update the `SKIP` and `FINISH` reducer branch:

```ts
case 'SKIP':
case 'FINISH':
  return state.phase === 'complete'
    ? state
    : { ...state, phase: 'complete' };
```

- [ ] **Step 4: Implement the screen-owned orchestration hook**

Create `src/features/summaryWalkthrough/useSummaryWalkthrough.ts` with these
public types and behavior:

```ts
import { useCallback, useEffect, useMemo, useReducer, useRef, useState } from 'react';
import type { RefObject } from 'react';
import {
  AccessibilityInfo,
  findNodeHandle,
  LayoutChangeEvent,
  NativeScrollEvent,
  NativeSyntheticEvent,
  ScrollView,
  Text,
  View,
} from 'react-native';
import * as Haptics from 'expo-haptics';

import {
  getRevealedGroups,
  getTargetScrollY,
  initialWalkthroughState,
  isTargetFullyVisible,
  reduceWalkthrough,
  SUMMARY_WALKTHROUGH_STEPS,
  SummaryAnchorId,
  SummaryRevealGroup,
  WALKTHROUGH_REDUCED_MOTION_SETTLE_MS,
  WALKTHROUGH_REVEAL_SETTLE_MS,
  WALKTHROUGH_SCROLL_SETTLE_MS,
  WALKTHROUGH_START_DELAY_MS,
  WALKTHROUGH_TOP_CLEARANCE,
} from './model';

type AnchorMeasurement = { y: number; height: number };

type Options = {
  enabled: boolean;
  hasAlert: boolean;
  isWideLayout: boolean;
  scrollRef: RefObject<ScrollView | null>;
  contentRef: RefObject<View | null>;
  onComplete: () => void;
};

export default function useSummaryWalkthrough({
  enabled,
  hasAlert,
  isWideLayout,
  scrollRef,
  contentRef,
  onComplete,
}: Options) {
  const [state, dispatch] = useReducer(
    reduceWalkthrough,
    initialWalkthroughState,
  );
  const [reduceMotion, setReduceMotion] = useState<boolean | null>(null);
  const [viewportHeight, setViewportHeight] = useState(0);
  const [scrollY, setScrollY] = useState(0);
  const [anchors, setAnchors] = useState<
    Partial<Record<SummaryAnchorId, AnchorMeasurement>>
  >({ top: { y: 0, height: 1 } });
  const coachHeadingRef = useRef<Text | null>(null);
  const settleTimerRef = useRef<ReturnType<typeof setTimeout> | null>(
    null,
  );
  const startTimerRef = useRef<ReturnType<typeof setTimeout> | null>(
    null,
  );

  useEffect(() => {
    let alive = true;
    AccessibilityInfo.isReduceMotionEnabled()
      .then((value) => {
        if (alive) setReduceMotion(value);
      })
      .catch(() => {
        if (alive) setReduceMotion(true);
      });
    const subscription = AccessibilityInfo.addEventListener(
      'reduceMotionChanged',
      setReduceMotion,
    );
    return () => {
      alive = false;
      subscription.remove();
    };
  }, []);

  useEffect(() => {
    if (
      !enabled ||
      reduceMotion === null ||
      viewportHeight <= 0 ||
      state.phase !== 'waiting'
    ) {
      return;
    }

    startTimerRef.current = setTimeout(() => {
      dispatch({ type: 'START' });
    }, WALKTHROUGH_START_DELAY_MS);

    return () => {
      if (startTimerRef.current) clearTimeout(startTimerRef.current);
    };
  }, [enabled, reduceMotion, state.phase, viewportHeight]);

  const currentStep = SUMMARY_WALKTHROUGH_STEPS[state.stageIndex];

  useEffect(() => {
    if (!enabled || state.phase !== 'positioning' || reduceMotion === null) {
      return;
    }

    const target = anchors[currentStep.anchor];
    let shouldAnimateScroll = false;
    if (target && viewportHeight > 0) {
      const visible = isTargetFullyVisible({
        targetY: target.y,
        targetHeight: target.height,
        scrollY,
        viewportHeight,
        topClearance: WALKTHROUGH_TOP_CLEARANCE,
        bottomClearance: 180,
      });
      if (!visible) {
        shouldAnimateScroll = !reduceMotion;
        scrollRef.current?.scrollTo({
          y: getTargetScrollY(
            target.y,
            WALKTHROUGH_TOP_CLEARANCE,
          ),
          animated: !reduceMotion,
        });
      }
    }

    settleTimerRef.current = setTimeout(
      () => dispatch({ type: 'POSITIONED' }),
      shouldAnimateScroll ? WALKTHROUGH_SCROLL_SETTLE_MS : 0,
    );

    return () => {
      if (settleTimerRef.current) clearTimeout(settleTimerRef.current);
    };
  }, [
    anchors,
    currentStep.anchor,
    enabled,
    reduceMotion,
    scrollRef,
    scrollY,
    state.phase,
    viewportHeight,
  ]);

  useEffect(() => {
    if (!enabled || state.phase !== 'revealing' || reduceMotion === null) {
      return;
    }

    settleTimerRef.current = setTimeout(
      () => dispatch({ type: 'SETTLED' }),
      reduceMotion
        ? WALKTHROUGH_REDUCED_MOTION_SETTLE_MS
        : WALKTHROUGH_REVEAL_SETTLE_MS,
    );

    return () => {
      if (settleTimerRef.current) clearTimeout(settleTimerRef.current);
    };
  }, [enabled, reduceMotion, state.phase]);

  useEffect(() => {
    if (state.phase !== 'coaching') return;

    try {
      AccessibilityInfo.announceForAccessibility(
        `${currentStep.title}. ${currentStep.body}`,
      );
      const handle = findNodeHandle(coachHeadingRef.current);
      if (handle) AccessibilityInfo.setAccessibilityFocus(handle);
    } catch {}
    if (reduceMotion === false) {
      Haptics.selectionAsync().catch(() => {});
    }
  }, [currentStep.body, currentStep.title, reduceMotion, state.phase]);

  useEffect(
    () => () => {
      if (settleTimerRef.current) clearTimeout(settleTimerRef.current);
      if (startTimerRef.current) clearTimeout(startTimerRef.current);
    },
    [],
  );

  const measureAnchor = useCallback(
    (id: SummaryAnchorId, node: View | null) => {
      if (!node || !contentRef.current) return;
      node.measureLayout(
        contentRef.current,
        (_x, y, _width, height) => {
          setAnchors((current) => ({
            ...current,
            [id]: { y, height },
          }));
        },
        () => {},
      );
    },
    [contentRef],
  );

  const onViewportLayout = useCallback((event: LayoutChangeEvent) => {
    setViewportHeight(event.nativeEvent.layout.height);
  }, []);

  const onScroll = useCallback(
    (event: NativeSyntheticEvent<NativeScrollEvent>) => {
      setScrollY(event.nativeEvent.contentOffset.y);
    },
    [],
  );

  const finish = useCallback(
    (type: 'SKIP' | 'FINISH') => {
      onComplete();
      dispatch({ type });
    },
    [onComplete],
  );

  const revealedGroups = useMemo(() => {
    const allGroups: SummaryRevealGroup[] = [
      'header',
      'alert',
      'pinned',
      'today',
      'logging',
      'recent',
    ];
    if (!enabled || state.phase === 'complete') return allGroups;
    if (state.phase === 'waiting') return [];

    const revealedStageIndex =
      state.phase === 'positioning'
        ? state.stageIndex - 1
        : state.stageIndex;
    return getRevealedGroups(revealedStageIndex, {
      hasAlert,
      isWideLayout,
    });
  }, [enabled, hasAlert, isWideLayout, state.phase, state.stageIndex]);

  const active = enabled && state.phase !== 'complete';
  const locked = state.phase !== 'coaching';

  return {
    active,
    locked,
    reduceMotion: reduceMotion ?? true,
    step: currentStep,
    coachVisible: active && state.phase === 'coaching',
    coachHeadingRef,
    isRevealed: (group: SummaryRevealGroup) =>
      revealedGroups.includes(group),
    measureAnchor,
    onViewportLayout,
    onScroll,
    onSkip: () => finish('SKIP'),
    onPrimary: () => {
      if (locked) return;
      if (currentStep.primaryAction === 'Finish') {
        finish('FINISH');
      } else {
        dispatch({ type: 'NEXT' });
      }
    },
  };
}
```

Add the hook export to `src/features/summaryWalkthrough/index.ts`:

```ts
export { default as useSummaryWalkthrough } from './useSummaryWalkthrough';
```

- [ ] **Step 5: Run model tests, type-check, and lint the hook**

Run:

```bash
npm test -- --runInBand tests/features/summaryWalkthrough/model.spec.ts tests/ui/useSummaryWalkthrough.spec.tsx
npm run type-check
npx eslint src/features/summaryWalkthrough tests/features/summaryWalkthrough tests/ui/useSummaryWalkthrough.spec.tsx
```

Expected: the model and hook suites PASS, TypeScript exits with code 0, and
ESLint reports no errors.

- [ ] **Step 6: Commit the controller**

```bash
git add src/features/summaryWalkthrough/model.ts src/features/summaryWalkthrough/useSummaryWalkthrough.ts src/features/summaryWalkthrough/index.ts tests/features/summaryWalkthrough/model.spec.ts tests/ui/useSummaryWalkthrough.spec.tsx
git commit -m "feat: orchestrate Summary walkthrough"
```

---

### Task 6: Integrate the walkthrough with Summary and tab navigation

**Files:**

- Modify: `src/navigation/RootTabs.tsx:1-68`
- Modify: `src/screens/DashboardScreen.tsx:1-361`
- Modify: `tests/state/store.walkthrough.spec.ts`
- Create: `tests/ui/RootTabs.walkthrough.spec.tsx`
- Create: `tests/ui/DashboardScreen.walkthrough.spec.tsx`

**Interfaces:**

- Consumes: all feature exports from Tasks 2–5
- Consumes: `completeSummaryWalkthrough()` from Task 1
- Produces: real Summary content revealed in four stages
- Produces: temporarily disabled Sleep, Log, and Insights tabs

- [ ] **Step 1: Write failing navigation and Summary composition tests**

Append to `tests/state/store.walkthrough.spec.ts`:

```ts
import {
  isSummaryWalkthroughPending,
  isWalkthroughTabDisabled,
} from '~/features/summaryWalkthrough';
```

```ts
it('re-enables non-Summary tabs as soon as completion is persisted', () => {
  useStore.getState().completeOnboarding();

  const pendingBefore = isSummaryWalkthroughPending(
    useStore.getState().onboarding,
  );
  expect(isWalkthroughTabDisabled('Sleep', pendingBefore)).toBe(true);

  useStore.getState().completeSummaryWalkthrough();

  const pendingAfter = isSummaryWalkthroughPending(
    useStore.getState().onboarding,
  );
  expect(isWalkthroughTabDisabled('Sleep', pendingAfter)).toBe(false);
});
```

Create `tests/ui/RootTabs.walkthrough.spec.tsx`. Mock the four screen modules
and `AppIcon` to lightweight React Native `Text` components, mock safe-area
insets and the color scheme, then render the real `RootTabs` inside a
`NavigationContainer` with the real Zustand store. Assert that Summary stays
enabled while Sleep, Log, and Insights are disabled. Persist completion inside
`act`, then assert that Sleep becomes enabled.

Create `tests/ui/DashboardScreen.walkthrough.spec.tsx`. Render the real
`DashboardScreen`, `AppScreen`, reveal wrappers, coach component, and Zustand
store. Mock only the algorithm-heavy hooks, graph, navigation, adaptive
layout, safe-area insets, and `useSummaryWalkthrough`. The orchestration mock
must return an active first step with `coachVisible: true`,
`isRevealed: () => true`, stable refs, and no-op callbacks. Assert that:

- the real first-step coach heading, `Your day at a glance`, is present;
- real empty-state Summary content such as `Pinned` is present; and
- `app-screen-content` has `pointerEvents="none"`.

The implementer may adjust mock shapes to the actual component interfaces,
but must not weaken the assertions proving real tab gating, real Summary
composition, coach rendering, and the interaction lock.

- [ ] **Step 2: Run the new UI tests and observe the intended red state**

Run:

```bash
npm test -- --runInBand tests/state/store.walkthrough.spec.ts tests/ui/RootTabs.walkthrough.spec.tsx tests/ui/DashboardScreen.walkthrough.spec.tsx
```

Expected: the pure store regression PASS, while both UI suites FAIL because
`RootTabs` does not disable non-Summary tabs and `DashboardScreen` does not
compose the active coach or interaction lock. Record the failing assertions
before editing either production component.

- [ ] **Step 3: Disable non-Summary tab buttons while pending**

Update `src/navigation/RootTabs.tsx` imports:

```tsx
import type { BottomTabBarButtonProps } from '@react-navigation/bottom-tabs';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { PlatformPressable } from '@react-navigation/elements';
import {
  isSummaryWalkthroughPending,
  isWalkthroughTabDisabled,
} from '~/features/summaryWalkthrough';
import { useStore } from '~/state/store';
```

Add this focused button wrapper:

```tsx
function WalkthroughTabButton({
  walkthroughDisabled,
  accessibilityState,
  ...props
}: BottomTabBarButtonProps & { walkthroughDisabled: boolean }) {
  return (
    <PlatformPressable
      {...props}
      disabled={walkthroughDisabled}
      accessibilityState={{
        ...accessibilityState,
        disabled: walkthroughDisabled,
      }}
    />
  );
}
```

Inside `RootTabs`, derive pending state:

```ts
const walkthroughPending = useStore((state) =>
  isSummaryWalkthroughPending(state.onboarding),
);
```

Inside `screenOptions`, derive the route-specific state and return the custom
button only when needed:

```tsx
const walkthroughDisabled = isWalkthroughTabDisabled(
  route.name,
  walkthroughPending,
);
```

Add to the returned options:

```tsx
tabBarButton: (props) => (
  <WalkthroughTabButton
    {...props}
    walkthroughDisabled={walkthroughDisabled}
  />
),
```

Keep the existing icon selection, colors, labels, order, and tab bar styling.

- [ ] **Step 4: Compose the controller at the top of Dashboard**

Update `src/screens/DashboardScreen.tsx` imports:

```tsx
import React, { useMemo, useRef } from 'react';
import type { LayoutChangeEvent } from 'react-native';
import { ScrollView, Text, View } from 'react-native';
import {
  isSummaryWalkthroughPending,
  SummaryWalkthroughCoach,
  useSummaryWalkthrough,
  WalkthroughReveal,
} from '~/features/summaryWalkthrough';
```

Inside `DashboardScreen`, after the existing store selectors, add:

```tsx
const onboarding = useStore((state) => state.onboarding);
const completeSummaryWalkthrough = useStore(
  (state) => state.completeSummaryWalkthrough,
);
const scrollRef = useRef<ScrollView>(null);
const contentRef = useRef<View>(null);
const pinnedAnchorRef = useRef<View>(null);
const loggingAnchorRef = useRef<View>(null);
const walkthroughEnabled =
  isSummaryWalkthroughPending(onboarding);
```

After `alertCard` is calculated, initialize the hook:

```tsx
const walkthrough = useSummaryWalkthrough({
  enabled: walkthroughEnabled,
  hasAlert: alertCard !== null,
  isWideLayout: layout.isWideLayout,
  scrollRef,
  contentRef,
  onComplete: completeSummaryWalkthrough,
});

const measurePinned = (_event: LayoutChangeEvent) => {
  walkthrough.measureAnchor('pinned', pinnedAnchorRef.current);
};

const measureLogging = (_event: LayoutChangeEvent) => {
  walkthrough.measureAnchor('logging', loggingAnchorRef.current);
};
```

Keep hooks unconditionally ordered: move the hook above render-only constants
if the final edit would otherwise call it after a conditional return.

- [ ] **Step 5: Wrap the existing semantic groups without changing their data**

Use this exact wrapper pattern for the optional alert:

```tsx
const revealedAlert = alertCard ? (
  <WalkthroughReveal
    active={walkthrough.active}
    revealed={walkthrough.isRevealed('alert')}
    reduceMotion={walkthrough.reduceMotion}
  >
    {alertCard}
  </WalkthroughReveal>
) : null;
```

Wrap the Pinned heading with stagger index `0`. Wrap the five existing
`HealthMetricCard` elements in their current order with stagger indices `1`
through `5`. Do not change their labels, values, detail copy, colors, or
navigation callbacks:

```tsx
const pinnedCards = (
  <>
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('pinned')}
      reduceMotion={walkthrough.reduceMotion}
      staggerIndex={0}
    >
      <SectionHeader
        prominence="prominent"
        title="Pinned"
        actionLabel="Edit"
      />
    </WalkthroughReveal>
    <View style={{ gap: spacing.md }}>
      {pinnedMetricCards.map((card, index) => (
        <WalkthroughReveal
          key={card.key}
          active={walkthrough.active}
          revealed={walkthrough.isRevealed('pinned')}
          reduceMotion={walkthrough.reduceMotion}
          staggerIndex={index + 1}
        >
          {card.element}
        </WalkthroughReveal>
      ))}
    </View>
  </>
);
```

Define `pinnedMetricCards` immediately before `pinnedCards`, using the five
existing card expressions unchanged:

```tsx
const pinnedMetricCards = [
  {
    key: 'caffeine',
    element: (
      <HealthMetricCard
        icon="cafe"
        label="Caffeine"
        labelColor={palette.caffeineAccent}
        dateLabel="Today"
        value={`${Math.round(todaySummary.todayTotal)} mg`}
        detail={todaySummary.deltaText}
        onPress={() => navigate('Insights', { section: 'summary' })}
      />
    ),
  },
  {
    key: 'active-caffeine',
    element: (
      <HealthMetricCard
        icon="pulse"
        label="Active Caffeine"
        labelColor={palette.activeCaffeineAccent}
        dateLabel="Now"
        value={`${Math.round(mgActive ?? 0)} mg`}
        detail={`Alertness ${Math.round(nowScore ?? 0)}`}
        onPress={() => navigate('Insights', { section: 'trends' })}
      />
    ),
  },
  {
    key: 'sleep',
    element: (
      <HealthMetricCard
        icon="bed"
        label="Sleep"
        labelColor={palette.sleepAccent}
        dateLabel={fmtDay(latestSleep?.end)}
        value={
          latestSleep
            ? fmtDuration(latestSleep.end - latestSleep.start)
            : 'No Data'
        }
        detail={
          latestSleep
            ? `${sleepCount} session${sleepCount === 1 ? '' : 's'} available`
            : 'Connect Health or use demo data'
        }
        onPress={() => navigate('Sleep')}
      />
    ),
  },
  {
    key: 'vigilance',
    element: (
      <HealthMetricCard
        icon="speedometer"
        label="Vigilance"
        labelColor={palette.vigilanceAccent}
        dateLabel={
          latestVigilanceSession
            ? fmtDay(latestVigilanceSession.completedAt)
            : 'Today'
        }
        value={
          latestVigilanceSession
            ? `${latestVigilanceSession.score}`
            : 'No Data'
        }
        detail={
          latestVigilanceSession
            ? `${latestVigilanceSession.rating} • ${latestVigilanceSession.medianReactionMs ?? '—'} ms median`
            : 'Run a 60-second test'
        }
        onPress={() => navigate('VigilanceTest')}
      />
    ),
  },
  {
    key: 'cutoff',
    element: (
      <HealthMetricCard
        icon="moon"
        label="Caffeine Cutoff"
        labelColor={palette.cutoffAccent}
        dateLabel="Today"
        value={fmtTime(cutoff?.nextCutoff)}
        detail={`Bed ${fmtTime(sleepGuidance?.bedtime)} • Wake ${fmtTime(sleepGuidance?.wake)}`}
        onPress={() => navigate('Sleep')}
      />
    ),
  },
];
```

Replace the existing `logSection` constant with a staggered version that keeps
the same labels, amounts, and callbacks:

```tsx
const quickAddOptions = [
  ['Espresso', 60],
  ['Drip', 95],
  ['Matcha', 70],
  ['Energy', 160],
] as const;

const revealedLogSection = (
  <>
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('logging')}
      reduceMotion={walkthrough.reduceMotion}
    >
      <SectionHeader title="Log" />
    </WalkthroughReveal>
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('logging')}
      reduceMotion={walkthrough.reduceMotion}
      staggerIndex={1}
    >
      <SectionCard>
        <View
          style={{
            flexDirection: 'row',
            flexWrap: 'wrap',
            gap: spacing.sm,
          }}
        >
          {quickAddOptions.map(([label, mg], index) => (
            <WalkthroughReveal
              key={label}
              active={walkthrough.active}
              revealed={walkthrough.isRevealed('logging')}
              reduceMotion={walkthrough.reduceMotion}
              staggerIndex={index + 2}
            >
              <Button
                title={`${label} ${mg}mg`}
                variant="plain"
                onPress={() => quickAdd(mg, label)}
              />
            </WalkthroughReveal>
          ))}
        </View>
        <WalkthroughReveal
          active={walkthrough.active}
          revealed={walkthrough.isRevealed('logging')}
          reduceMotion={walkthrough.reduceMotion}
          staggerIndex={6}
        >
          <Button
            title="Custom Entry"
            variant="plain"
            onPress={() => navigate('Log')}
          />
        </WalkthroughReveal>
      </SectionCard>
    </WalkthroughReveal>
  </>
);
```

Wrap Recent Activity as group `recent` and the wide-layout Today panel as group
`today`. Keep their existing content and callbacks unchanged:

```tsx
const revealedRecentSection = (
  <WalkthroughReveal
    active={walkthrough.active}
    revealed={walkthrough.isRevealed('recent')}
    reduceMotion={walkthrough.reduceMotion}
    staggerIndex={1}
  >
    {recentSection}
  </WalkthroughReveal>
);

const revealedTodayPanel = (
  <WalkthroughReveal
    active={walkthrough.active}
    revealed={walkthrough.isRevealed('today')}
    reduceMotion={walkthrough.reduceMotion}
    staggerIndex={1}
  >
    {todayPanel}
  </WalkthroughReveal>
);
```

- [ ] **Step 6: Add anchors, header reveal, and the fixed coach card**

Build the overlay:

```tsx
const walkthroughCoach = walkthrough.coachVisible ? (
  <WalkthroughReveal
    key={walkthrough.step.id}
    active
    revealed
    reduceMotion={walkthrough.reduceMotion}
  >
    <SummaryWalkthroughCoach
      step={walkthrough.step}
      locked={walkthrough.locked}
      headingRef={walkthrough.coachHeadingRef}
      onSkip={walkthrough.onSkip}
      onPrimary={walkthrough.onPrimary}
    />
  </WalkthroughReveal>
) : null;
```

Pass the walkthrough surface to `AppScreen`:

```tsx
<AppScreen
  title="Summary"
  scrollRef={scrollRef}
  contentRef={contentRef}
  scrollEnabled={!walkthrough.active}
  interactionEnabled={!walkthrough.active}
  bottomOverlay={walkthroughCoach}
  onScroll={walkthrough.onScroll}
  onViewportLayout={walkthrough.onViewportLayout}
  headerTransform={(header) => (
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('header')}
      reduceMotion={walkthrough.reduceMotion}
    >
      {header}
    </WalkthroughReveal>
  )}
>
```

In both compact and wide branches, use `revealedAlert`. Wrap the Pinned and Log
regions in measurable views:

```tsx
<View
  ref={pinnedAnchorRef}
  collapsable={false}
  onLayout={measurePinned}
  style={{ gap: spacing.md }}
>
  {pinnedCards}
</View>
<View
  ref={loggingAnchorRef}
  collapsable={false}
  onLayout={measureLogging}
  style={{ gap: spacing.md }}
>
  {revealedLogSection}
  {revealedRecentSection}
</View>
```

Use `revealedTodayPanel` in the wide right column. Close `AppScreen` without
changing the existing adaptive column widths.

- [ ] **Step 7: Run focused tests and repository static checks**

Run:

```bash
npm test -- --runInBand tests/state/store.walkthrough.spec.ts tests/features/summaryWalkthrough/model.spec.ts tests/features/summaryWalkthrough/motion.spec.ts tests/components/AppScreen.layout.spec.ts tests/ui/RootTabs.walkthrough.spec.tsx tests/ui/DashboardScreen.walkthrough.spec.tsx
npm run type-check
npm run lint
```

Expected: all focused suites PASS, TypeScript exits with code 0, and ESLint
reports no errors.

- [ ] **Step 8: Commit the integrated walkthrough**

```bash
git add src/navigation/RootTabs.tsx src/screens/DashboardScreen.tsx tests/state/store.walkthrough.spec.ts tests/ui/RootTabs.walkthrough.spec.tsx tests/ui/DashboardScreen.walkthrough.spec.tsx
git commit -m "feat: guide new users through Summary"
```

---

### Task 7: Verify behavior, accessibility, exports, and release gates

**Files:**

- Modify only if a verification command exposes a walkthrough-specific defect:
  - `src/features/summaryWalkthrough/*`
  - `src/components/AppScreen.tsx`
  - `src/navigation/RootTabs.tsx`
  - `src/screens/DashboardScreen.tsx`
  - corresponding focused test file

**Interfaces:**

- Consumes: the completed feature from Tasks 1–6
- Produces: evidence that the approved acceptance criteria and repository gates pass

- [ ] **Step 1: Run the complete JavaScript test suite**

Run:

```bash
npm test -- --runInBand
```

Expected: all 15 existing suites plus the new pure and `jest-expo` UI suites
PASS in their isolated Jest projects.

- [ ] **Step 2: Run type-check and lint**

Run:

```bash
npm run type-check
npm run lint
```

Expected: both commands exit with code 0 and report no errors.

- [ ] **Step 3: Verify the iOS JavaScript export**

Run:

```bash
npx expo export --platform ios
```

Expected: Expo completes the iOS export without bundling or Reanimated errors.

- [ ] **Step 4: Verify the standalone website remains unaffected**

Run:

```bash
npm run site:type-check
npm run site:build
```

Expected: both website commands exit with code 0.

- [ ] **Step 5: Perform the first-run iPhone walkthrough**

Use an iPhone simulator or physical iPhone with app data removed:

1. Complete setup with Manual selected and no sample data.
2. Confirm Summary controls and Sleep, Log, and Insights tabs are disabled.
3. Confirm stage 1 reveals the header and current-state alert.
4. Press Next and confirm Pinned cards reveal in order.
5. Press Next and confirm Aurora scrolls to Log, then reveals Log and Recent Activity.
6. Press Next and confirm the final bottom-navigation explanation.
7. Press Finish and confirm normal interaction returns immediately.
8. Relaunch and confirm the walkthrough does not replay.

Expected: real empty-state values remain unchanged and no dose, sleep, or
vigilance record is created.

- [ ] **Step 6: Verify Skip and interrupted-session behavior**

Repeat with app data removed:

1. Skip from stage 1 and confirm all content and tabs become interactive.
2. Relaunch and confirm no replay.
3. Remove app data again, advance to stage 2, and terminate the app without Skip or Finish.
4. Relaunch, complete setup if required, and confirm the walkthrough starts again at stage 1.

Expected: only Skip and Finish persist completion; partial stage state does not.

- [ ] **Step 7: Verify adaptive and accessible behavior**

Run the walkthrough on iPad landscape and on iPhone with:

- Light appearance
- Dark appearance
- Dynamic Type at XL
- Dynamic Type at an accessibility size
- VoiceOver
- Reduce Motion

Expected:

- iPad keeps its two-column layout and scrolls only when a target is outside the usable viewport.
- Coach copy grows without truncation.
- VoiceOver announces each heading and hidden groups are absent from the accessibility tree.
- Disabled tabs expose a disabled state.
- Reduce Motion uses a short fade, immediate scrolling, no scale or translation, no stagger, and no haptics.

- [ ] **Step 8: Run native simulator build gates when stable Xcode 26.6 is available**

Run:

```bash
npm run ios:build:debug
npm run ios:build:release
```

Expected: unsigned Debug and Release simulator builds succeed. If the machine
does not have stable Xcode 26.6 with the iOS 26 SDK, record that environmental
limitation without changing native project files.

- [ ] **Step 9: Commit only walkthrough-specific fixes found by verification**

If Tasks 7.1–7.8 required code changes, stage the exact corrected source and
matching test files, then run the focused test that reproduced the defect
before committing:

```bash
git add src/features/summaryWalkthrough src/components/AppScreen.tsx src/navigation/RootTabs.tsx src/screens/DashboardScreen.tsx tests/features/summaryWalkthrough tests/components/AppScreen.layout.spec.ts tests/state/store.walkthrough.spec.ts
git commit -m "fix: harden Summary walkthrough"
```

If verification required no code changes, do not create an empty commit.
