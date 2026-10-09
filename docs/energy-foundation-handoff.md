# Energy foundation handoff (Package 1)

Branch `claude/aurora-energy-foundation`, base `85a3ddb`. Local commit only; nothing
pushed. No UI changes. No Health writes, no new entitlements, no signing or global
settings changes. Claude implemented core and services for this package by explicit
user assignment.

## Verification (2026-10-09)

| Command | Result |
|---|---|
| `TZ=UTC DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path AuroraCore` | 94 tests in 15 suites passed (baseline 64) |
| `TZ=America/Los_Angeles DEVELOPER_DIR=… swift test --package-path AuroraCore` | 94 tests in 15 suites passed |
| `DEVELOPER_DIR=… swift test --package-path AuroraCore --filter "RefreshCoordinatorTests\|StateMigrationTests" --maximum-repetitions 200 --repeat-until fail` | passed |
| `DEVELOPER_DIR=… xcodebuild build -project Aurora.xcodeproj -scheme Aurora -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/aurora-foundation-build CODE_SIGNING_ALLOWED=NO` | BUILD SUCCEEDED |
| same with `build-for-testing` | TEST BUILD SUCCEEDED (app tests compile) |

**Not run:** the app test suite on a simulator. Codex owns that lane. The new and
changed tests in `AuroraTests/AppModelTests.swift` and `LocalDataDeletionTests.swift`
compile but haven't been executed. No Release build, device, or HealthKit run.

## APIs (AuroraCore)

- `EnergyEstimate.capture(at:doses:sleeps:inputs:)`: versioned Codable snapshot
  (`version`, `modelVersion "alertness-1"`, `capturedAt`, `timeZoneIdentifier`,
  half-life/target, `sleepHoursLast24`, `modeledScore: Int?`, `contributions`
  [baseline, timeOfDay, caffeine, sleepDebt, inertia], `missingInputs`
  [recentSleep, recentCaffeine], `includesSample`, `limitations`). The score is
  `Summary.estimateAlertness` unchanged: it's present only when sleep is recorded
  in the prior 24 h (the existing rule, with no new threshold), and contributions
  are empty without it. `unroundedScore` equals `Alertness.score` exactly, which
  the tests check for every fixture probe in both zones. `title` is "Modeled
  alertness". The copy never uses a percentage and passes `CopyRules`.
- `Alertness` weights are named constants with the same values and the same
  expression, so parity fixtures are unchanged.
- `EnergyProjection.build(now:doses:sleeps:inputs:)`: 12 h before to 12 h after on
  the epoch's 30-minute grid, plus the capture instant (`currentIndex`). Point
  kinds are `modeledPast`, `current`, and `projected`, and every point is model
  output. Only records known at capture count: doses at or before it, and sleep that
  ended by it. Projected points assume no further sleep or caffeine.
- `EnergyCheckIn` is a self-rated 1–5 scale with labels "Very low"…"Very high",
  `scaleLabel`, and `kindLabel` ("Your rating. Recorded by you, not modeled.").
  `rating` is stored as Int, so a bad stored value can't break decoding.
  `validate(rating:recordedAt:now:)`. `AppState.addEnergyCheckIn(_:now:)` validates,
  rejects duplicates, and keeps newest first. Check-ins never feed the model.
- Health caffeine:
  - `HealthSampleProvenance`: sample UUID (lowercased), source bundle id, name,
    sync id and version.
  - `HealthCaffeineSample`, `HealthCaffeineChanges` (added, deleted UUIDs, and the
    anchor as `Data`).
  - `RecordID.healthCaffeineID(sampleUUID:)` / `isHealthCaffeine` (prefix
    `healthkit:caffeine:`).
  - `Dose.health` is optional provenance. Manual doses encode their original keys
    unchanged.
  - `AppState.applyHealthCaffeine(_:now:)` matches only by UUID (no time+amount
    dedup), skips Aurora's own exports (`HealthOrigin`), rejects invalid samples,
    and saves the anchor.
  - `AppState.updateDose`/`removeDose` refuse Health caffeine.
  - `CaffeineLog.isEditable` is false and its label is "Health".
- `HealthSyncLedger` (v1) holds anchors, `ownExports`, `pendingActions` (one per
  dose, with an increasing sync version), and `outcomes` (last 50).
  `AppState.enqueueHealthExport` refuses Sample Data and Health records.
  `deleteAllData` clears check-ins and the ledger.
- `HealthDataProvider` protocol with a `HealthCapabilities` option set. Each
  operation is separate: authorization, sleep read, caffeine change read, own-write,
  own-delete, and observe start/stop. Undeclared operations throw
  `HealthProviderError.unsupported`.
- `RefreshCoordinator<Value>` (MainActor): `refresh()` coalesces with a running
  refresh. `invalidate()` cancels it and bumps `generation`, and a late result is
  `.discarded` even if the fetch ignores cancellation.
- `StateMigration.load(directory:files:)`: if the stored version is below 2 (a
  missing version counts as 1), it writes `state.v1-source.json` and reads it back
  byte-equal. It then checks that record counts and values carry over and that the
  encoded v2 file round-trips before writing it. It reads the saved file back and
  restores the original on any failure. A newer version raises `unsupportedVersion`
  and the file is untouched. Undecodable files raise `undecodable`. A retained
  source with different bytes raises `retainedSourceMismatch` and neither file is
  changed.

## App changes

- `StateStore.load` uses `StateMigration` with file-protected writes. Only
  undecodable files get a `state.corrupt.<ms>.json` copy. Newer or unverifiable
  files fail closed, and the app shows the existing recovery screen.
- `LocalDataDeletion.owns` includes `state.v1-source.json`, so full erase removes it.
- `HealthKitService` is the sleep-only compatibility adapter
  (`[.authorization, .readSleep]`). It refuses any authorization beyond reading
  Sleep Analysis. `AppModel.health` is `any HealthDataProvider`, so it can be
  injected in tests.

## Known gaps, by next package

- **Health:** the HealthKit caffeine anchored query, observer and background
  delivery, and own writes and deletes aren't implemented, and there's no
  `dietaryCaffeine` entitlement or usage-string change. `RefreshCoordinator` isn't
  wired into `AppModel` yet, which still uses `dataGeneration`. Anchors are archived
  `HKQueryAnchor` `Data`, and the archiving code is still to be written. Delete all
  clears the ledger, so the next anchored read re-imports Health caffeine, matching
  how Health sleep behaves today. The package must decide whether full erase should
  remove Aurora's own exports from Health first. Export CSV, `RecordSource`, and
  `SummarySignals` still label any non-sample dose "Manual". No Health caffeine
  exists until import ships, but those labels must change with it.
  `retainedSourceMismatch` would keep the app in recovery until it's resolved by
  hand. It's improbable, but it isn't handled in the UI.
- **Energy:** there's no UI for estimates, projections, or check-ins. No `AppModel`
  methods add check-ins yet. The projection grid is epoch-aligned, so zones with
  :45 offsets aren't on local half-hours.
- **Planning:** there's no planning logic. Nothing recommends doses, bedtimes, or
  thresholds.
- **Widgets:** there's no widget target or shared container. Snapshots are Codable
  for later sharing.
