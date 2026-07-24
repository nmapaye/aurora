# Apple Health-Style Secondary Pages Design

Date: 2026-07-24  
Status: Approved for implementation

## Summary

Aurora will rebuild Sleep, Log, and Insights around the information hierarchy
and interaction language used by Apple Health category-detail pages: large
titles, compact range controls, a dominant metric and chart, concise
highlights, grouped disclosure rows, top-level Add Data or Share actions, and
focused Show All Data destinations.

The work remains React Native and Expo Go-compatible. `expo-symbols` supplies
SF Symbols on iOS, while Aurora retains its own navy and blue brand, copy,
algorithms, and app mark. The implementation must not copy Apple's Health app
icon or pretend to be an Apple-provided Health surface.

Aurora's existing one-time Summary walkthrough becomes a ten-step guided
journey through Summary, Sleep, Log, and Insights. It operates on real empty,
manual, sample, or Health-connected state and never adds data.

## Goals

- Make Sleep, Log, and Insights feel consistent with Summary and familiar to
  iPhone and iPad Health users.
- Preserve existing caffeine, sleep, vigilance, export, and HealthKit
  behavior unless this specification explicitly changes it.
- Add a complete manual sleep workflow with safe correction and deletion.
- Keep Expo Go preview available.
- Use compact single-column layouts on iPhone and balanced two-column layouts
  on wide iPad windows.
- Meet Dynamic Type, VoiceOver, Reduce Motion, light appearance, and dark
  appearance requirements.
- Follow strict test-driven development for every production behavior.

## Non-goals

- Rebuilding the app with SwiftUI or `@expo/ui`.
- Copying the Apple Health icon, wordmark, or protected trade dress.
- Writing sleep data back to HealthKit.
- Adding Android-specific product behavior; Aurora remains iPhone and iPad
  only.
- Adding analytics, telemetry, replay controls, synthetic walkthrough data,
  or an additional end-to-end testing framework.
- Redesigning Summary beyond shared Quick Add presets and walkthrough
  integration.

## Visual Language

- Use the existing grouped system-like background, opaque card surfaces,
  semantic palette, large-title header, tabular numerals, and restrained
  dividers.
- Use native SF Symbols through an `AppSymbol` wrapper. Tests and unsupported
  platforms receive an Ionicons fallback.
- Charts place a numeric headline and date range above the plot. Empty ranges
  show explicit no-data copy instead of a zero-valued line.
- Grouped rows use 44-point minimum targets and disclosure indicators only
  when they navigate or reveal another view.
- Aurora's tint remains the primary action color. Sleep may use the existing
  purple semantic accent and caffeine the existing orange/purple accents.
- Preserve the approved adaptive rule: the dominant chart/metric remains
  primary; supporting highlights and actions move beside it only on wide
  layouts.

## Sleep

### Information architecture

1. Large title `Sleep` with trailing `Add Data`.
2. W/M control mapping to 7 and 30 days.
3. Dominant Time Asleep metric and duration chart.
4. Highlights:
   - Last-night duration, wake time, and target difference.
   - Caffeine Impact, withholding correlation claims until 14 nights.
5. Next Best Actions:
   - Existing suggested caffeine plan and its existing 200 mg/cutoff rules.
   - Only the first valid planned dose remains loggable.
6. Options:
   - Data Sources & Access.
   - Show All Data.

### Health data

- Health import remains read-only.
- Refresh the most recent 30 days instead of three days.
- Preserve stable Health-derived IDs, filtering, sorting, and upsert
  deduplication.
- Keep unavailable, denied, connected with zero results, successful import,
  and refresh error as distinct visible states.
- Data Sources & Access owns Connect/Refresh Health, current authorization,
  imported count, last sync, last message, and sample-data load/clear.

### Manual Add Data

- The sheet opens with `end = now` and `start = now - 8 hours`.
- It accepts start, end, and an optional note.
- Save is disabled and an inline message appears unless:
  - start is before end;
  - duration is no more than 24 hours;
  - end is not in the future.
- Manual IDs begin with `manual:sleep:`.
- Manual sessions save with `type: 'sleep'`.
- Successful save dismisses the sheet and announces confirmation.

### Sleep history

- Show All Data opens a full-screen `SleepHistory` route.
- Rows clearly label Manual or Health source.
- Manual rows can be edited with the same validation or deleted after
  confirmation.
- Health-imported rows remain read-only and cannot expose edit/delete actions.

## Log

1. Large title `Log` with trailing `Add Data`.
2. Caffeine Today metric showing total and remaining daily limit.
3. Quick Add grid using one shared preset definition:
   - Espresso, 60 mg.
   - Drip, 95 mg.
   - Matcha, 70 mg.
   - Energy, 160 mg.
4. Recent entries list.
5. Add Details grouped rows:
   - Custom Entry.
   - Show All Caffeine Data.

Quick Add stores the current time and preset source. Custom Entry uses a
sheet for amount, source, time, and note. Amount must be 1–1999 mg and time
cannot be in the future. Successful logging keeps haptics best-effort, shows
an accessible live-region confirmation, and resets the custom form only after
the save succeeds.

Summary consumes the same preset definition so the two pages cannot diverge.

## Insights

Insights becomes one scrolling category-detail page rather than a second
Summary/Trends/History switcher.

1. Large title `Insights` with trailing `Share`.
2. W/2W/M control mapping to 7, 14, and 30 days; default 2W.
3. Dominant Caffeine Intake metric and daily-total chart.
4. Highlights for period comparison, adherence, and streak.
5. Trends for daypart and source mix.
6. Alertness and sleep guidance using existing vigilance and guidance rules.
7. Options:
   - Show All Data.
   - Export Daily Totals.

The chosen range controls the headline, previous-window comparison, chart,
adherence, daypart, source mix, and guidance inputs together. Every chart has
a concise accessibility summary.

Show All Data opens a full-screen `CaffeineHistory` route and preserves
search, edit, delete, and export. Share and export failures produce visible
inline status.

## One-Time Guided Journey

### Persisted lifecycle

Replace the Summary-only persisted fields with:

```ts
appWalkthroughCompleted: boolean;
appWalkthroughStep: number;
```

The cursor is an integer from 0 through 9. New installations begin at 0 and
incomplete. Completion is set only by global Skip or final Finish.

Persisted store version 5 migrates the old
`summaryWalkthroughCompleted === true` state to global completion. Users who
already finished the Summary tour never receive a second first-run
experience. Other eligible users begin at step 0. Invalid cursors clamp to
0–9 during normalization.

### Exact steps

1. Summary — `Your day at a glance`: `Aurora brings caffeine, sleep, and alertness together.`
2. Summary — `See what shapes alertness`: `These signals show how caffeine, sleep, and vigilance shape your day.`
3. Summary — `Log in a tap`: `Use a common amount, or open Custom Entry when you need more detail.`
4. Summary — `Next: your sleep`: `See where rest data comes from and how timing shapes tomorrow.`
5. Sleep — `Understand your sleep`: `Use Week or Month to review your real sleep history and recent highlights.`
6. Sleep — `Add or connect sleep`: `Aurora can read Health data or save a manual sleep session.`
7. Log — `Log in one tap`: `Use the same quick amounts here and on Summary.`
8. Log — `Add details when they matter`: `Custom Entry records amount, source, time, and an optional note.`
9. Insights — `See patterns over time`: `Change the range to compare caffeine, timing, and alertness.`
10. Insights — `Keep learning from your trends`: `Review highlights or open Show All Data whenever you need the details.`

Steps 1–4, 5–6, 7–8, and 9–10 belong to Summary, Sleep, Log, and Insights
respectively. Next advances the persisted cursor; crossing a page boundary
programmatically selects the next tab. The tab bar remains visible, but all
manual tab presses are disabled while the tour is active. Skip completes the
entire tour from every coach card.

Each page registers semantic reveal groups and layout anchors with the shared
coordinator. Unrevealed content remains in layout but hidden visually and
from the accessibility tree. All underlying data-changing controls remain
disabled during the tour.

The current soft spring reveal remains the motion language. Reduce Motion
removes translation, scale, stagger, animated scrolling, haptics, and other
nonessential motion. VoiceOver announces and focuses every coach. Missing
measurements fall back to the page top and never block progress. Relaunch
resumes the stored step and replays only that step's local reveal.

## Architecture

- `AppSymbol` isolates `expo-symbols` from fallbacks and tests.
- Focused `components/health` primitives own presentation only.
- Shared caffeine presets provide one typed source of truth.
- Pure Sleep and Insights presentation selectors calculate chart points,
  period summaries, empty states, and accessibility descriptions.
- Zustand/MMKV remains the source of truth for doses, sleep sessions,
  onboarding, Health status, and walkthrough progress.
- Screen-local sheets own draft form state.
- Stack routes own full-screen history experiences.
- A pure app-walkthrough model defines steps, routing, reveal groups, and
  state transitions. A shared hook handles geometry, motion,
  accessibility, and navigation.

## Error and Accessibility Rules

- Never display a successful Health connection or import when authorization,
  query, or parsing failed.
- Never fabricate chart points for an empty range.
- Failed sharing/export stays on screen and exposes a readable status.
- Haptic failure never blocks a successful save.
- Modal sheets use modal accessibility semantics, focus their heading on
  open, and restore focus to the trigger on close.
- Controls maintain 44-point targets, meaningful labels, and selected,
  disabled, or expanded accessibility state where applicable.
- Chart accessibility descriptions include metric, date range, data
  availability, and high-level direction without requiring the SVG to be
  explored mark by mark.

## Verification

Every production change follows a witnessed red–green–refactor cycle. Use
React Native Testing Library semantic queries and pure selectors; do not add
snapshot-heavy tests or another end-to-end framework.

Required automated gates:

- `npm run type-check`
- `npm run lint`
- `npm test -- --runInBand`
- `npx expo export --platform ios`
- `npm run site:type-check`
- `npm run site:build`
- Available unsigned Debug and Release simulator builds

Final manual acceptance covers Expo Go, iPhone, iPad, compact and wide
windows, light and dark appearance, large Dynamic Type, VoiceOver, Reduce
Motion, and real empty/manual/Health-connected states.
