# Energy foundation handoff (Package 1)

Branch `claude/aurora-energy-foundation`, base `85a3ddb`. Foundation commit `4b899bf`
plus a separate review-correction commit (see "Review corrections"). Local commits only;
nothing pushed. No UI changes. No Health writes, no new entitlements, no signing or global
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

## Review corrections (2026-10-09)

| Command | Result |
|---|---|
| `TZ=UTC DEVELOPER_DIR=… swift test --package-path AuroraCore` | 103 tests in 15 suites passed |
| `TZ=America/Los_Angeles DEVELOPER_DIR=… swift test --package-path AuroraCore` | 103 tests in 15 suites passed |
| `DEVELOPER_DIR=… swift test --package-path AuroraCore --filter "StateMigrationTests\|HealthCaffeineTests\|EnergyEstimateTests" --maximum-repetitions 100 --repeat-until fail` | 27 tests in 3 suites passed |
| generic unsigned `xcodebuild build` (same flags as above) | BUILD SUCCEEDED |
| generic unsigned `xcodebuild build-for-testing` | TEST BUILD SUCCEEDED |

App tests still not run on a simulator (Codex lane). No UI, Health writes, entitlements,
or constants changed; `Alertness` weights and `Summary.estimateAlertness` are untouched,
and every fixture probe still matches in both zones.

1. **Energy evidence.** `EnergyEstimate` is version 2. Missing caffeine is now truthful:
   `.caffeine` ("The model counts none") only when no entry adds any active caffeine;
   `.recentCaffeine` when nothing is in the last 24 h but earlier entries still add a
   fading amount. `includesSample` covers every contributing record, including sample
   caffeine older than 24 h (the 24 h `Summary` flag is unchanged for parity, so the
   snapshot can be true where it is false, never the reverse). New `evidence`
   (`EnergyEvidence`): `windowStart`, `activeCaffeineMg` (equals `Caffeine.activeMg`),
   per-entry caffeine (record id, source manual/health/sample, timestamp, mg, modeled
   active mg, Health sample UUID and source bundle), entries below 0.01 mg summed in
   `fadedCaffeine` (count, mg, latest time, sample flag), sleep records (id, source,
   interval, hours in the 24 h window, `inLatestEpisode`), and `lastWakeAt` when the
   wake-up term applies. Ordered by time then id, plain values only; no HealthKit
   objects, classifier, or conversation context. New limitation `unmeasuredFactors`
   names illness, stress, medication, meals and activity as outside the model, never
   as causes.
2. **Health ownership.** `HealthOrigin.isOwnExport(_:ledger:)` is true only for the exact
   Aurora bundle id or a sample UUID the ledger recorded from an Aurora save. Sync
   identifier prefixes, custom metadata, and look-alike bundle prefixes no longer hide
   third-party samples. `HealthOrigin.ownership(of:ledger:doses:)` uses the sync
   identifier only to find the local dose of a sample already proven Aurora's. Own
   samples with a local dose are skipped; own samples without one (after full erase or
   reconnecting) are kept as read-only Health records (`keptOwnWithoutLocalDose`).
   `HealthCaffeineImport.isEligible` became `isValid` (shape checks only).
3. **Migration rollback.** A failed save restores `state.json` and reads it back. If that
   restore can't be confirmed, `StateMigration.Failure.restoreFailed` is thrown (no
   more silent `try?`), naming the save and restore errors and whether the retained
   source verified. `state.v1-source.json` is never touched on that path. `StateStore`
   maps it to `verificationFailed`, so the app shows the existing recovery screen.

## APIs (AuroraCore)

- `EnergyEstimate.capture(at:doses:sleeps:inputs:)`: versioned Codable snapshot
  (`version`, `modelVersion "alertness-1"`, `capturedAt`, `timeZoneIdentifier`,
  half-life/target, `sleepHoursLast24`, `modeledScore: Int?`, `contributions`
  [baseline, timeOfDay, caffeine, sleepDebt, inertia], `missingInputs`
  [recentSleep, recentCaffeine, caffeine], `includesSample`, `limitations`, `evidence`). The score is
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
    dedup), skips Aurora's own exports only while their local dose exists (`HealthOrigin`), rejects invalid samples,
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
  remove Aurora's own exports from Health first.
  **Requirement:** after erase or reconnect, Aurora-sourced Health caffeine with no
  matching local dose must appear as existing read-only Health records (labeled,
  counted, deletable only through Health or an explicit own-delete flow), never
  silently dropped. Core already keeps them read-only; the Health package must label
  and surface them, and decide what the export CSV, `RecordSource`, and signals call
  them. Ownership must stay bundle/ledger-UUID based; never trust metadata alone. Export CSV, `RecordSource`, and
  `SummarySignals` still label any non-sample dose "Manual". No Health caffeine
  exists until import ships, but those labels must change with it.
  `retainedSourceMismatch` and `restoreFailed` keep the app in recovery until
  resolved by hand; `state.v1-source.json` is the copy to recover from. It's improbable, but it isn't handled in the UI.
- **Energy:** there's no UI for estimates, projections, evidence, or check-ins.
  Projection points still carry only score and sample flag, not per-point evidence. No `AppModel`
  methods add check-ins yet. The projection grid is epoch-aligned, so zones with
  :45 offsets aren't on local half-hours.
- **Planning:** there's no planning logic. Nothing recommends doses, bedtimes, or
  thresholds.
- **Widgets:** there's no widget target or shared container. Snapshots are Codable
  for later sharing.
