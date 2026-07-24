# Apple Health-Style Secondary Pages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild Sleep, Log, and Insights with the approved Apple Health-like
hierarchy and extend Aurora's one-time walkthrough into a persisted ten-step
guided journey across all four tabs.

**Architecture:** Keep React Native screens and Aurora's real Zustand/MMKV
state as the source of truth. Shared Health-style presentation components and
pure selectors provide the visual/data foundation; focused stack history
routes hold detailed data management; a pure walkthrough model plus one shared
coordinator owns cross-tab progress, motion, accessibility, and completion.

**Tech Stack:** Expo SDK 54, React Native 0.81, React 19, TypeScript 5.9,
Zustand/MMKV, React Navigation 7, React Native Reanimated 4,
`react-native-svg`, `expo-symbols ~1.0.8`, Expo Haptics, Jest 29, React Native
Testing Library 14.

## Global Constraints

- Do not run `expo prebuild`; `ios/AURORA.xcworkspace` remains authoritative.
- Work only in the isolated `codex/health-style-secondary-pages` worktree.
- Keep the implementation React Native and previewable in Expo Go; do not add `@expo/ui`.
- Use native SF Symbols through one wrapper, retain Aurora branding, and do not copy Apple's Health icon.
- Preserve HealthKit as read-only and add no analytics, telemetry, or synthetic walkthrough data.
- Use exactly these shared Quick Add presets: Espresso 60 mg, Drip 95 mg, Matcha 70 mg, Energy 160 mg.
- Sleep range W means 7 days; M means 30 days; Health refresh covers exactly the most recent 30 days.
- Insights range W means 7 days, 2W means 14 days, M means 30 days, and 2W is the default.
- Manual sleep requires start before end, duration at most 24 hours, end not in the future, and IDs prefixed `manual:sleep:`.
- Only manual sleep records can be edited or deleted; Health-imported sleep records are always read-only.
- The walkthrough has exactly ten approved steps: Summary 1–4, Sleep 5–6, Log 7–8, Insights 9–10.
- Skip completes the whole walkthrough; Finish completes it at step 10; no replay entry point is added.
- During the walkthrough, use real state and disable all underlying data-changing controls.
- Existing users who completed the old Summary walkthrough migrate as globally complete.
- Reduce Motion removes nonessential animation, animated scrolling, stagger, haptics, and transform motion.
- Every persisted-field change must update `normalizePersistedState`, migration coverage, and `tests/state/store.persistence.spec.ts`.
- Every production behavior must be preceded by a focused automated test that is run and observed failing for the expected missing behavior.
- Use semantic React Native Testing Library assertions and pure selector tests; do not add snapshot-heavy tests or another end-to-end framework.
- Run focused tests while iterating and the full suite once before each task commit.

## Target File Structure

### Shared foundation

- `src/components/AppSymbol.tsx` — SF Symbol wrapper with Ionicons fallback.
- `src/components/health/` — focused chart card, highlight card, grouped
  list/row, range control, form sheet, empty state, and barrel exports.
- `src/features/caffeine/presets.ts` — typed shared Quick Add presets.

### Walkthrough

- `src/features/appWalkthrough/` — pure ten-step model, motion plan, reveal
  wrapper, coach, coordinator hook/context, and public exports.
- Remove the obsolete `src/features/summaryWalkthrough/` module after all
  consumers and tests move.

### Sleep

- `src/features/sleep/presentation.ts` — range chart points, headline,
  highlights, source labeling, and accessibility summaries.
- `src/features/sleep/manualSleep.ts` — manual ID, editability, defaults, and
  validation.
- `src/screens/SleepHistoryScreen.tsx` — full-screen history and manual
  edit/delete.

### Insights

- `src/features/insights/presentation.ts` — range windows, period comparison,
  adherence, daypart, source mix, and chart summaries.
- `src/screens/CaffeineHistoryScreen.tsx` — focused wrapper around existing
  history behavior.

---

### Task 1: Build the shared Health-style foundation

**Files:**

- Modify: `package.json`
- Modify: `package-lock.json`
- Create: `src/components/AppSymbol.tsx`
- Create: `src/components/health/HealthChartCard.tsx`
- Create: `src/components/health/HealthHighlightCard.tsx`
- Create: `src/components/health/HealthGroupedList.tsx`
- Create: `src/components/health/HealthRangeControl.tsx`
- Create: `src/components/health/HealthFormSheet.tsx`
- Create: `src/components/health/HealthEmptyState.tsx`
- Create: `src/components/health/index.ts`
- Create: `src/features/caffeine/presets.ts`
- Create: `tests/features/caffeine/presets.spec.ts`
- Create: `tests/ui/AppSymbol.spec.tsx`
- Create: `tests/ui/healthComponents.spec.tsx`
- Modify: `tests/setup.ts`
- Modify: `tests/ui/setup.ts`

**Interfaces:**

```ts
export type CaffeinePreset = {
  id: 'espresso' | 'drip' | 'matcha' | 'energy';
  label: string;
  mg: number;
  symbol: AppSymbolName;
};

export const CAFFEINE_PRESETS: readonly CaffeinePreset[];
```

`AppSymbol` accepts a typed SF Symbol name, size, tint, accessibility props,
and an Ionicons fallback name. Health components own presentation and
accessibility only; they never read Zustand or navigate directly.

- [ ] **Step 1: Write the failing foundation tests**
  - Assert the four presets and exact amounts/order.
  - Assert `AppSymbol` forwards the iOS symbol and renders the fallback in the
    mocked non-iOS environment.
  - Assert range options expose selected state and 44-point targets.
  - Assert grouped rows expose button/disclosure semantics only when
    pressable.
  - Assert chart cards expose one concise accessibility summary and an honest
    empty state.
  - Assert the form sheet exposes modal semantics, heading, Cancel, and Save.

- [ ] **Step 2: Run tests and verify RED**

```bash
npm test -- --runInBand tests/features/caffeine/presets.spec.ts tests/ui/AppSymbol.spec.tsx tests/ui/healthComponents.spec.tsx
```

Expected: FAIL because the modules and `expo-symbols` mock do not exist.

- [ ] **Step 3: Install and implement the minimal foundation**

```bash
npx expo install expo-symbols
```

Use the SDK 54-compatible `~1.0.8` version. Build focused components using the
existing palette, tokens, `AppScreen`, and accessibility conventions. Do not
introduce a second theme or native sheet dependency.

- [ ] **Step 4: Run focused GREEN and regressions**

```bash
npm test -- --runInBand tests/features/caffeine/presets.spec.ts tests/ui/AppSymbol.spec.tsx tests/ui/healthComponents.spec.tsx
npm run type-check
npm test -- --runInBand
```

Expected: all commands exit 0 with no test warnings.

- [ ] **Step 5: Commit**

```bash
git add package.json package-lock.json src/components/AppSymbol.tsx src/components/health src/features/caffeine/presets.ts tests/features/caffeine/presets.spec.ts tests/ui/AppSymbol.spec.tsx tests/ui/healthComponents.spec.tsx tests/setup.ts tests/ui/setup.ts
git commit -m "feat: add Health-style UI foundation"
```

---

### Task 2: Generalize persisted walkthrough state and the pure model

**Files:**

- Modify: `src/state/store.ts`
- Create: `src/features/appWalkthrough/model.ts`
- Create: `src/features/appWalkthrough/index.ts`
- Create: `tests/features/appWalkthrough/model.spec.ts`
- Modify: `src/features/summaryWalkthrough/model.ts` only for the temporary
  persisted-state compatibility seam
- Modify: `src/screens/DashboardScreen.tsx`
- Modify: `src/navigation/RootTabs.tsx`
- Modify: `tests/state/store.walkthrough.spec.ts`
- Modify: `tests/state/store.persistence.spec.ts`
- Modify: `tests/state/store.demo.spec.ts`
- Modify: every full onboarding fixture that currently names `summaryWalkthroughCompleted`

**Interfaces:**

```ts
type Onboarding = {
  completed: boolean;
  source: OnboardingSource;
  permissionStatus: HealthPermissionStatus;
  completedAt?: number;
  appWalkthroughCompleted: boolean;
  appWalkthroughStep: number;
};

advanceAppWalkthrough: () => void;
completeAppWalkthrough: () => void;
```

The pure model exports `APP_WALKTHROUGH_STEPS`, route ownership, reveal groups,
anchors, reducer helpers, `isAppWalkthroughPending`, step clamping, and tab
gating. Step indexes are 0–9 and use the exact copy in the approved design.

- [ ] **Step 1: Write failing store/model tests**
  - Assert ten ordered steps, exact route grouping 4/2/2/2, exact copy,
    cumulative local reveals, and Next/Skip/Finish transitions.
  - Assert advancing clamps at 9 and completing does not change user data.
  - Assert fresh state is incomplete at step 0.
  - Assert normalization clamps negative, fractional, and greater-than-9
    cursors.
  - Assert version 4 `summaryWalkthroughCompleted: true` migrates complete.
  - Assert an incomplete legacy user migrates incomplete at step 0.
  - Assert setup/demo completion does not complete the walkthrough.

- [ ] **Step 2: Run tests and verify RED**

```bash
npm test -- --runInBand tests/features/appWalkthrough/model.spec.ts tests/state/store.walkthrough.spec.ts tests/state/store.persistence.spec.ts
```

Expected: FAIL because the app-wide model and state fields do not exist.

- [ ] **Step 3: Implement version 5 migration and pure model**
  - Remove `summaryWalkthroughCompleted` from current state after migration.
  - Normalize the cursor with an integer clamp.
  - Keep existing version 1–4 migrations functional before applying version
    5 conversion.
  - Update Dashboard, RootTabs, and the Summary pending helper to consume the
    new completion field/action while retaining the current four-step
    Summary controller until Task 6.
  - Leave the existing Summary motion/controller files in place so this
    intermediate commit remains fully runnable; Task 6 moves and generalizes
    them after every target screen exists.

- [ ] **Step 4: Run focused GREEN and regressions**

```bash
npm test -- --runInBand tests/features/appWalkthrough/model.spec.ts tests/features/summaryWalkthrough/motion.spec.ts tests/state/store.walkthrough.spec.ts tests/state/store.persistence.spec.ts tests/state/store.demo.spec.ts
npm run type-check
npm test -- --runInBand
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/state/store.ts src/features/appWalkthrough src/features/summaryWalkthrough/model.ts src/screens/DashboardScreen.tsx src/navigation/RootTabs.tsx tests/features/appWalkthrough tests/state tests/components tests/ui
git commit -m "feat: persist app walkthrough progress"
```

---

### Task 3: Rebuild Sleep and add manual sleep history

**Files:**

- Modify: `src/domain/models.ts`
- Modify: `src/state/store.ts`
- Modify: `src/screens/SleepScreen.tsx`
- Create: `src/screens/SleepHistoryScreen.tsx`
- Create: `src/features/sleep/presentation.ts`
- Create: `src/features/sleep/manualSleep.ts`
- Modify: `src/navigation/RootNavigator.tsx`
- Modify: `src/navigation/types.ts`
- Modify: `src/navigation/linking.ts`
- Modify: `tests/services/platform/health/appleHealth.spec.ts`
- Modify: `tests/state/store.persistence.spec.ts`
- Create: `tests/features/sleep/presentation.spec.ts`
- Create: `tests/features/sleep/manualSleep.spec.ts`
- Create: `tests/state/store.sleep.spec.ts`
- Create: `tests/ui/SleepScreen.spec.tsx`
- Create: `tests/ui/SleepHistoryScreen.spec.tsx`

**Interfaces:**

```ts
export type SleepSession = {
  id: string;
  start: number;
  end: number;
  type: 'sleep' | 'nap';
  note?: string;
};

updateManualSleep: (
  id: string,
  patch: Partial<Pick<SleepSession, 'start' | 'end' | 'note'>>
) => void;
removeManualSleep: (id: string) => void;

RootStackParamList['SleepHistory'] = undefined;
```

Both store actions must no-op unless the ID begins `manual:sleep:`. Presentation
selectors accept explicit `now` and range arguments so tests are deterministic.

- [ ] **Step 1: Write failing pure/store tests**
  - Validate default eight-hour draft and every validation boundary.
  - Assert manual ID prefix and source labeling.
  - Assert 7-/30-day chart windows, no-data state, last-night summary, and
    accessible chart description.
  - Assert manual update/remove succeeds and imported update/remove no-ops.
  - Assert optional notes survive persistence.

- [ ] **Step 2: Run pure/store tests and verify RED**

```bash
npm test -- --runInBand tests/features/sleep/manualSleep.spec.ts tests/features/sleep/presentation.spec.ts tests/state/store.sleep.spec.ts tests/state/store.persistence.spec.ts
```

Expected: FAIL because manual helpers, note, and guarded actions do not exist.

- [ ] **Step 3: Implement pure/store behavior, then write failing UI tests**
  - Add the W/M chart hierarchy, Add Data trigger, Highlights, Next Best
    Actions, and Options.
  - Test compact and mocked-wide layouts.
  - Test unavailable, denied, zero-result, connected, error, manual, and demo
    states.
  - Test Add Data validation/save/announcement.
  - Test Data Sources & Access actions and exact 30-day query bounds.
  - Test SleepHistory manual edit/delete and imported read-only behavior.

- [ ] **Step 4: Run UI tests and verify RED**

```bash
npm test -- --runInBand tests/ui/SleepScreen.spec.tsx tests/ui/SleepHistoryScreen.spec.tsx
```

Expected: FAIL against the existing Sleep page and missing history route.

- [ ] **Step 5: Implement the screens and navigation**
  - Preserve existing cutoff, 200 mg plan, 14-night caution, stable Health
    IDs, haptics, and only-first-recommendation logging.
  - Use `HealthFormSheet` and shared Health components.
  - Keep Health records visibly read-only in history.

- [ ] **Step 6: Run GREEN and regressions**

```bash
npm test -- --runInBand tests/features/sleep tests/state/store.sleep.spec.ts tests/ui/SleepScreen.spec.tsx tests/ui/SleepHistoryScreen.spec.tsx tests/services/platform/health/appleHealth.spec.ts
npm run type-check
npm test -- --runInBand
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit**

```bash
git add src/domain/models.ts src/state/store.ts src/features/sleep src/screens/SleepScreen.tsx src/screens/SleepHistoryScreen.tsx src/navigation tests/features/sleep tests/state tests/ui/SleepScreen.spec.tsx tests/ui/SleepHistoryScreen.spec.tsx tests/services/platform/health/appleHealth.spec.ts
git commit -m "feat: redesign Sleep and add manual history"
```

---

### Task 4: Rebuild Log around shared Quick Add and Custom Entry

**Files:**

- Modify: `src/screens/DashboardScreen.tsx`
- Modify: `src/screens/LogIntakeScreen.tsx`
- Create: `src/features/caffeine/logging.ts`
- Create: `src/screens/CaffeineHistoryScreen.tsx`
- Modify: `src/navigation/RootNavigator.tsx`
- Modify: `src/navigation/types.ts`
- Modify: `src/navigation/linking.ts`
- Create: `tests/features/caffeine/logging.spec.ts`
- Create: `tests/ui/LogIntakeScreen.spec.tsx`
- Create: `tests/ui/CaffeineHistoryScreen.spec.tsx`
- Modify: affected Summary walkthrough/component tests

**Interfaces:**

`logging.ts` exports deterministic helpers for today's total, remaining limit,
custom draft defaults, validation, and dose construction. Both Dashboard and
Log map `CAFFEINE_PRESETS` rather than declaring local arrays.

- [ ] **Step 1: Write failing pure/UI tests**
  - Assert today's total and remaining limit use local-day boundaries.
  - Assert 1 and 1999 mg valid; 0 and 2000 invalid.
  - Assert future custom times invalid.
  - Assert Quick Add uses now and exact preset source.
  - Assert the approved Today, Quick Add, Recent, and Add Details hierarchy in
    compact and mocked-wide layouts.
  - Assert Custom Entry saves timestamp/note, announces success, and resets
    only after save.
  - Assert haptic rejection does not prevent a saved dose.
  - Assert Summary and Log expose the same four presets.
  - Assert Show All Caffeine Data opens the full-screen history route and the
    route preserves current search, edit, delete, and export behavior.

- [ ] **Step 2: Run tests and verify RED**

```bash
npm test -- --runInBand tests/features/caffeine/logging.spec.ts tests/ui/LogIntakeScreen.spec.tsx tests/ui/CaffeineHistoryScreen.spec.tsx tests/ui/DashboardScreen.walkthrough.spec.tsx
```

Expected: FAIL because Log still owns divergent presets and inline form UI.

- [ ] **Step 3: Implement the minimal redesign**
  - Use shared Health components and a custom-entry sheet.
  - Preserve existing generated IDs, source choices, time picker, note,
    haptics, and store action.
  - Add a visible accessibility live-region confirmation.
  - Add `RootStackParamList['CaffeineHistory'] = undefined`, register the
    full-screen route, and wrap the existing `HistoryContent` without
    duplicating its mutation logic.

- [ ] **Step 4: Run GREEN and regressions**

```bash
npm test -- --runInBand tests/features/caffeine tests/ui/LogIntakeScreen.spec.tsx tests/ui/CaffeineHistoryScreen.spec.tsx tests/ui/DashboardScreen.walkthrough.spec.tsx tests/ui/DashboardScreen.walkthrough.wiring.spec.tsx
npm run type-check
npm test -- --runInBand
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit**

```bash
git add src/features/caffeine src/screens/DashboardScreen.tsx src/screens/LogIntakeScreen.tsx src/screens/CaffeineHistoryScreen.tsx src/navigation tests/features/caffeine tests/ui
git commit -m "feat: redesign caffeine logging"
```

---

### Task 5: Rebuild Insights and add focused caffeine history

**Files:**

- Modify: `src/screens/InsightsScreen.tsx`
- Modify: `src/screens/CaffeineHistoryScreen.tsx`
- Create: `src/features/insights/presentation.ts`
- Modify: `src/components/HistoryContent.tsx` only where required for the
  focused screen contract and accessibility
- Modify: `src/navigation/RootNavigator.tsx`
- Modify: `src/navigation/types.ts`
- Modify: `src/navigation/linking.ts`
- Create: `tests/features/insights/presentation.spec.ts`
- Create: `tests/ui/InsightsScreen.spec.tsx`
- Modify: `tests/ui/CaffeineHistoryScreen.spec.tsx`
- Modify: navigation tests affected by removal of the Insights `section`
  parameter

**Interfaces:**

```ts
export type InsightsRange = '7' | '14' | '30';
RootStackParamList['CaffeineHistory'] = undefined;
RootTabParamList['Insights'] = undefined;
```

Pure selectors accept doses, vigilance sessions, daily limit, chosen range,
and explicit `now`; they return current/previous windows, chart points,
headline, delta, adherence, streak, daypart, source mix, empty state, and one
chart accessibility description.

- [ ] **Step 1: Write failing selector tests**
  - Assert W/2W/M map to 7/14/30 and default behavior is 14.
  - Assert local-day buckets and equal previous windows.
  - Assert range changes every aggregate, not only the chart.
  - Assert zero-data periods return an explicit empty result.
  - Assert source normalization, daypart bins, adherence, streak, and
    vigilance baseline rules remain unchanged.

- [ ] **Step 2: Run selector tests and verify RED**

```bash
npm test -- --runInBand tests/features/insights/presentation.spec.ts
```

Expected: FAIL because the pure presentation module does not exist.

- [ ] **Step 3: Implement selectors, then write failing UI tests**
  - Assert the approved single category-detail hierarchy and no top-level
    Summary/Trends/History control.
  - Assert 2W selected by default and range changes headline, chart, and
    trend content.
  - Assert honest empty state and chart accessibility summary.
  - Assert Share and export failure status.
  - Assert Show All Data opens the existing `CaffeineHistory` route.
  - Re-run history coverage to ensure search, edit, delete, and export remain
    intact after the Insights integration.
  - Assert compact and mocked-wide layouts.

- [ ] **Step 4: Run UI tests and verify RED**

```bash
npm test -- --runInBand tests/ui/InsightsScreen.spec.tsx tests/ui/CaffeineHistoryScreen.spec.tsx
```

Expected: FAIL against the existing segmented Insights page and missing route.

- [ ] **Step 5: Implement screens, routes, and history wrapper**
  - Preserve current share/export payloads and all domain rules.
  - Keep `HistoryContent` focused; do not duplicate its mutation logic.
  - Reuse the Task 4 history route from both Log and Insights.

- [ ] **Step 6: Run GREEN and regressions**

```bash
npm test -- --runInBand tests/features/insights tests/ui/InsightsScreen.spec.tsx tests/ui/CaffeineHistoryScreen.spec.tsx tests/services/storage/export.spec.ts
npm run type-check
npm test -- --runInBand
```

Expected: all commands exit 0.

- [ ] **Step 7: Commit**

```bash
git add src/features/insights src/screens/InsightsScreen.tsx src/screens/CaffeineHistoryScreen.tsx src/components/HistoryContent.tsx src/navigation tests/features/insights tests/ui
git commit -m "feat: redesign Insights and data history"
```

---

### Task 6: Integrate the ten-step cross-screen walkthrough and accessibility

**Files:**

- Move/modify: remaining `src/features/summaryWalkthrough/` UI/controller
  files into `src/features/appWalkthrough/`
- Modify: `src/navigation/RootTabs.tsx`
- Modify: `src/screens/DashboardScreen.tsx`
- Modify: `src/screens/SleepScreen.tsx`
- Modify: `src/screens/LogIntakeScreen.tsx`
- Modify: `src/screens/InsightsScreen.tsx`
- Move/modify: remaining Summary walkthrough UI tests to
  `tests/ui/appWalkthrough.*`
- Modify: `tests/ui/RootTabs.walkthrough.spec.tsx`
- Create: `tests/ui/AppWalkthrough.journey.spec.tsx`
- Modify: `tests/ui/AppScreen.spec.tsx` only if the generic coordinator needs a
  narrowly scoped host seam

**Interfaces:**

The coordinator reads `APP_WALKTHROUGH_STEPS`, persisted step/completion, and
current route. Each screen adapter registers local anchors/reveal groups and
renders the shared coach through `AppScreen.bottomOverlay`.

Next within a page advances locally. Next across page boundaries persists the
new step and programmatically navigates to the owning tab. Manual tab presses
remain disabled until global Skip or Finish.

- [ ] **Step 1: Write failing journey/model-host tests**
  - Assert Summary starts only after setup and begins at persisted step.
  - Assert exact automatic route sequence Summary → Sleep → Log → Insights.
  - Assert progress labels 1 of 10 through 10 of 10.
  - Assert every Next is locked while positioning/revealing.
  - Assert Skip from Summary, Sleep, Log, and Insights completes globally and
    unlocks all tabs.
  - Assert Finish at step 10 completes globally.
  - Assert relaunch at steps 5, 7, and 9 selects the correct tab and resumes.
  - Assert data-changing controls are inaccessible while the tour is active.
  - Assert missing anchors fall back without stalling.
  - Assert Reduce Motion and VoiceOver announcement/focus behavior.
  - Assert existing migrated-complete users never start the new tour.

- [ ] **Step 2: Run tests and verify RED**

```bash
npm test -- --runInBand tests/ui/AppWalkthrough.journey.spec.tsx tests/ui/RootTabs.walkthrough.spec.tsx tests/ui/useSummaryWalkthrough.spec.tsx
```

Expected: FAIL because the existing hook is Summary-only and other tabs are
permanently gated rather than coordinator-controlled.

- [ ] **Step 3: Implement generic coordinator and screen adapters**
  - Reuse existing reveal/coach/motion behavior where it satisfies the new
    contract.
  - Rename public symbols and tests from Summary to App where responsibility
    is now global.
  - Delete obsolete Summary-only files only after all imports move.
  - Preserve the existing Summary layout/calculations.
  - Use page-local anchor fallback and wide-layout remeasurement.

- [ ] **Step 4: Run focused GREEN and complete UI regressions**

```bash
npm test -- --runInBand tests/ui/AppWalkthrough.journey.spec.tsx tests/ui/RootTabs.walkthrough.spec.tsx tests/ui/appWalkthrough.presentation.spec.tsx tests/ui/DashboardScreen.walkthrough.spec.tsx tests/ui/SleepScreen.spec.tsx tests/ui/LogIntakeScreen.spec.tsx tests/ui/InsightsScreen.spec.tsx
npm run type-check
npm test -- --runInBand
```

Expected: all commands exit 0 with no warnings.

- [ ] **Step 5: Run repository-level verification**

```bash
npm run lint
npx expo export --platform ios
npm run site:type-check
npm run site:build
```

When stable Xcode 26.6 is selected and native dependencies are bootstrapped:

```bash
npm run ios:bootstrap
npm run ios:build:debug
npm run ios:build:release
```

Do not weaken the build gate or run `expo prebuild` if Xcode is unavailable or
incorrectly selected; report the environment limitation.

- [ ] **Step 6: Commit**

```bash
git add src/features/appWalkthrough src/features/summaryWalkthrough src/navigation/RootTabs.tsx src/screens tests/ui
git commit -m "feat: guide first run across Aurora"
```

## Final Acceptance

- The whole branch receives a broad code review against this plan and the
  approved design.
- All Critical and Important findings are fixed and re-reviewed.
- Fresh full verification runs after the final fix commit.
- Manual smoke testing covers Expo Go, iPhone, iPad, light/dark, large Dynamic
  Type, VoiceOver, Reduce Motion, and empty/manual/Health-connected states.
