# Energy UI handoff (Package 3)

Branch `claude/aurora-energy-native`, accepted base `9653d0f`. Local commits only;
nothing pushed. No signing, team, entitlement, account, dependency or global setting
changes. No simulator, UI-test runner, device or live account was used. Provisional
until Codex review.

| Commit | Scope |
|---|---|
| `458dd4b` | Health visual correction (release-review finding), separate from Energy |
| `1b2b561` | Energy implementation |
| this commit | This handoff |

## Verification (2026-10-09)

Logs are under `build/logs/` in this worktree (git-ignored). `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` for every command.

| Command | Result | Log |
|---|---|---|
| `TZ=UTC swift test --package-path AuroraCore` (base, before work) | 164 tests in 24 suites passed | `baseline-utc.log` |
| same, after the Health correction | 165 in 24 passed (UTC and America/Los_Angeles) | `health-fix-core-{utc,la}.log` |
| `TZ=UTC swift test --package-path AuroraCore` | 183 tests in 27 suites passed | `energy-core-utc.log` |
| `TZ=America/Los_Angeles swift test --package-path AuroraCore` | 183 tests in 27 suites passed | `energy-core-la.log` |
| `swift test … --filter "EnergySnapshotTests\|EnergyCheckInFlowTests\|EnergyIntentTests\|AssistantCardTests\|AssistantTests" --maximum-repetitions 50 --repeat-until fail` | 46 tests in 6 suites, 50 repetitions, no failure | `energy-core-repeat.log` |
| `python3 scripts/check-design-tokens.py` | passed (after each commit's changes) | console |
| `xcodebuild build -project Aurora.xcodeproj -scheme Aurora -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd CODE_SIGNING_ALLOWED=NO` | BUILD SUCCEEDED, no warnings besides the AppIntents metadata note | `health-fix-build.log`, `energy-build.log` |
| same with `build-for-testing` | TEST BUILD SUCCEEDED | `health-fix-build-for-testing.log`, `energy-build-for-testing.log` |

The 164 → 165 change is the test `9653d0f` added, not this work.

**Not run (Codex lane):** `AuroraTests` (new `EnergyCheckInAppTests`, 6 tests, compile
only) and `AuroraUITests` (new `testEnergyCurveShowsModeledLabelsWithoutRecords`,
`testCheckInNeedsARatingSaveAndUndo`, `testEnergyGalleryOffersSyntheticVariants`;
extended Health largest-text and gallery tests; all compile only). No screenshots were
captured: that needs a simulator run. Website checks not run (no website change).

## Health correction (`458dd4b`)

- `HealthConnectionView`: at accessibility sizes the choice title takes the full row
  width and the native switch sits underneath; the spinner is beside the switch, not in
  the title. The switch keeps its identifier, its title as its accessibility label, its
  value, the independent choice and the same disabled rule. The visual title is hidden
  from VoiceOver so it is announced once. Standard sizes are unchanged. Disclosure text
  is not capped.
- Copy: `HealthChoice.backgroundUpdates.requestedNote`, the `HealthKitService` comment
  and the Health handoff now treat `.hourly` as a requested frequency; iOS controls
  timing. Settings' Privacy Policy row describes separate sleep and caffeine reads and
  optional caffeine writes. No behavior change.
- Gallery: "Show Health choices" opens the sheet (largest text by default) against
  `GalleryHealth`, a provider with no capabilities, so every choice is refused before
  HealthKit is asked. The whole gallery now uses it instead of `HealthKitService`.
- UI tests: the largest-text test also asserts each switch label; the gallery test opens
  the Health sheet.

## Energy (`1b2b561`)

**Core.**
- `EnergySnapshot` (v1, Codable): the `EnergyEstimate` at capture, the optional
  `EnergyProjection`, the window start, observations (sleep and caffeine records known
  at capture, with source), check-ins and Reaction Tests in the window. The estimate uses
  the same records as `Summary.estimateAlertness`, so the score keeps baseline parity
  (tested for every fixture probe in both zones). The projection and observations use
  only records known at capture. No constant, weight or validation changed.
- `AssistantCard` gains `energyProjection` and `energyCheckIn` kinds and optional
  `energy` and `checkIn` fields, so older saved conversations decode unchanged (tested).
  The energy card's alertness metric is labeled "Modeled alertness", its value is the
  bare number, and its source says 0 to 100 model scale, not a percentage. A new
  "Estimated active caffeine" metric is added. The briefing shares the new label.
- Intents: `energyProjection` and `energyCheckIn` join the finite catalog and the model
  instructions. Deterministic routing covers the quick-action text; a request matching
  both is `unsupported`. `checkInRating` reads only "N out of 5" or "N/5" on the scale.
  `checkInCorrection` accepts only short corrections ("actually 4", "make it 2") and
  reports off-scale numbers.
- `EnergyCheckInDraft`: no rating preselected, id fixed when the review opens.
  `AppState.replaceEnergyCheckIn(_:expecting:now:)` and `removeEnergyCheckIn(_:)` act
  only while the stored record is exactly the expected one. `Export.energyCheckInsCSV`.
- Storage: check-ins use the existing `AppState.energyCheckIns` (schema 2); no schema
  bump, migration or format change.

**App.**
- `AppModel`: `addEnergyCheckIn`, `replaceEnergyCheckIn`, `removeEnergyCheckIn`
  (validate on a copy, then the existing `update`). This is a shared file; the change is
  additive.
- `AssistantModel`: `pendingCheckIn`; `saveCheckIn` (repeat taps find no open review; a
  failed write keeps the review open for retry with the same id); `undoCheckIn` (removes
  a new check-in or restores the corrected one, only if unchanged); `editCheckIn`. Open
  check-in reviews expire on relaunch; Clear, Discard and erase drop them. Refresh
  prompts for the new kinds.
- `EnergyCardViews.swift`: contributions with signed points and the records behind each
  (recorded sleep, active caffeine and half-life, generic time-of-day curve, wake time),
  sample and missing status, and a separate "Recorded by you" list that says ratings and
  tests aren't part of the model or compared with it.
- `EnergyTimelineChart`: modeled points solid before capture, dashed after, a current
  rule and marker, recorded sleep as bands (overlaps drawn once) and caffeine as
  triangles. Runs break where there's no score. Tap or drag to read a point; VoiceOver
  gets a summary and an adjustable value. The legend uses shapes and dashes, not only
  color. Below it: the future assumption and the recorded records list.
- `AssistantCardView`: projection and check-in cards, check-in receipt with Undo and
  Edit, energy limitations in "What this means", an "Earlier snapshot · Refresh for
  current" badge on energy snapshots more than an hour old (results never change), and
  the check-in CSV in the export card.
- Quick actions "Show my energy curve" and "Check in my energy", plus clarification rows.
- Gallery: the energy kinds have an "Energy fixture" picker: Populated (made-up manual
  records), Missing records, Sample Data, Earlier snapshot (captured 3 hours earlier),
  Failed request, and Local model unavailable (the real unavailable message plus the
  quick-action card).

## Decisions and limits

- No hypothetical scenarios are built. Projections always assume no further sleep or
  caffeine; cutoff scenarios belong to Planning.
- Check-ins and Reaction Tests are never plotted on the model curve, fitted or used for
  accuracy.
- The history card and Settings export section don't include check-ins yet; the
  assistant export card does. Delete All and full erase clear them (existing core).
- If a record is dated after capture (e.g. a sleep still in progress), the headline
  score counts it as the baseline estimate does, while the curve and observations
  don't. That keeps parity, but the two can differ in that edge case.
- The projection grid stays epoch-aligned (foundation contract), so :45 zones aren't on
  local half-hours.
- `Summary.describe` and the Summary screen still say "Estimated alertness"; they're
  baseline copy and weren't changed.

## Unverified gates (Codex)

- `EnergyCheckInAppTests` and all new and changed UI tests on phone and pad simulators.
- Visual critique: gallery variants in light and dark, largest text, VoiceOver order,
  chart selection without page movement, Reduce Motion, and iPad width. The Health
  stacked layout at largest text.
- Segmented rating control at accessibility sizes (it uses digits; not visually checked).
- No accuracy, physical performance or App Store readiness claims.
