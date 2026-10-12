# Energy Health handoff (Package 2)

Branch `claude/aurora-health-native`, base `3952667` (accepted foundation).
Three local Claude commits; nothing pushed. The background-delivery entitlement
is declared in source as documented below; signing identities, teams and provisioning
profiles were not changed. No account/global configuration changes, new keys or personal records. Claude implemented core, services and the
Health UI for this package by explicit user assignment. Provisional until Codex review.

## Verification (2026-10-09)

| Command | Result |
|---|---|
| `TZ=UTC DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path AuroraCore` | 140 tests in 20 suites passed (baseline 103) |
| `TZ=America/Los_Angeles DEVELOPER_DIR=… swift test --package-path AuroraCore` | 140 tests in 20 suites passed |
| `DEVELOPER_DIR=… swift test --package-path AuroraCore --filter "HealthChoiceTests\|HealthCaffeineReadTests\|HealthExportTests\|HealthEraseAndRefreshTests\|RefreshCoordinatorTests\|StateMigrationTests" --maximum-repetitions 200 --repeat-until fail` | 47 tests in 6 suites passed, no failures in 200 repetitions |
| `DEVELOPER_DIR=… xcodebuild build -project Aurora.xcodeproj -scheme Aurora -destination 'generic/platform=iOS Simulator' -derivedDataPath /private/tmp/aurora-health-build CODE_SIGNING_ALLOWED=NO` | BUILD SUCCEEDED, no warnings in changed files |
| same with `build-for-testing` | TEST BUILD SUCCEEDED |

**Not run:**
- AuroraTests and AuroraUITests on a simulator. Codex owns that lane. The new
  `AuroraTests/HealthSyncAppTests.swift` (3 tests) compiles but hasn't run.
- `npm run site:type-check` / `site:build`. `node_modules` isn't installed in this
  worktree; only strings changed in `website/src/App.tsx` and `public/privacy.html`.
- Any signed build, device, or real HealthKit call.

## Review corrections (2026-10-09, separate commit)

Responds to Codex's provisional review (`aurora-overnight/health-review-findings.md`).

| Command | Result |
|---|---|
| `TZ=UTC DEVELOPER_DIR=… swift test --package-path AuroraCore` | 153 tests in 22 suites passed |
| `TZ=America/Los_Angeles DEVELOPER_DIR=… swift test --package-path AuroraCore` | 153 tests in 22 suites passed |
| `DEVELOPER_DIR=… swift test --package-path AuroraCore --filter "HealthChoiceTests\|HealthCaffeineReadTests\|HealthExportTests\|HealthEraseAndRefreshTests\|HealthSleepIdentityTests\|HealthBackgroundDeliveryTests\|RefreshCoordinatorTests\|StateMigrationTests" --maximum-repetitions 200 --repeat-until fail` | 60 tests in 8 suites passed, no failures in 200 repetitions |
| generic unsigned `xcodebuild build` / `build-for-testing` (same flags) | BUILD SUCCEEDED / TEST BUILD SUCCEEDED |

**Not run:**
- AuroraTests and UI tests on a simulator (Codex lane). `HealthSyncAppTests` now has 4
  tests, compiled only.
- The website checks.
- Any signed build or device test. The unsigned build doesn't validate entitlements
  against a profile.

1. **Revalidation after the interrupted-write lookup.** `HealthSyncEngine.attempt` now
   calls `stillCurrent` after the awaited `ownCaffeineSample` and before any new write.
   It checks that the export generation is unchanged, export is active, the dose's
   queued action has the same id, kind, sync identifier and version, and the dose is
   unchanged. A save already sent to Health may finish, but its answer is dropped if
   stale. No new write starts after an invalidation. Tests hold the lookup and then
   erase (no save), turn export off (no save; status `.uncertain`), correct the dose
   (only the version-2 write), or remove the dose (delete, no save).
2. **Sleep identity.**
   - `HealthKitService.sleepChanges(after:)` is an anchored read that keeps each
     sample's UUID, source bundle, name and sync metadata, plus deleted UUIDs.
   - Records are `healthkit:sleep:sample:<uuid>` with `SleepSession.health`
     provenance. Deletions remove exactly that UUID.
   - `HealthSleepIdentity.normalize` never renames or merges sample-identified ids.
     The window import (fallback for providers without identity) only replaces
     interval-identified records.
   - Conservative compatibility: on the first anchored read, a legacy
     `healthkit:sleep:<start>:<end>` record is replaced only by samples at exactly
     that interval (what its id was derived from). Every other legacy record is kept
     read-only until 180-day retention trims it, never matched to a nearby sample.
     The anchor saves with the records.
   - Calculations (`SleepDebt`, `unionDuration`, `SleepIntervals.merge`) merge
     intervals and don't use ids. A test confirms two same-interval samples count
     once.
   - **No schema change:** additive optional fields decode with defaults, so
     `schemaVersion` stays 2 and no retained-source migration is triggered.
     `state.v1-source.json` and the pre-assistant snapshot rules are unchanged.
   - Tests: `HealthSleepIdentityTests` (6) and `anchoredSleepKeepsSampleIdentityThroughConnect`.
3. **Background delivery.**
   - Implemented as a separate opt-in, "Update in the background"
     (`HealthChoices.backgroundUpdates`, off by default, asks for no Health
     permission, disabled until a read is chosen). It calls
     `enableBackgroundDelivery(for:frequency: .hourly)` only for kinds being read.
     `.hourly` is the requested frequency; iOS controls actual timing and
     opportunities, so no wake schedule is promised.
   - Turning a read off disables delivery for that kind. Erase, Delete All and each
     launch reconcile delivery to the stored choices, since Health keeps the setting
     across launches.
   - The entitlement `com.apple.developer.healthkit.background-delivery` is declared
     in `Aurora.entitlements`. Team, signing and profile settings are untouched.
   - Observers register at launch in the new `AppDelegate`
     (`application(_:didFinishLaunchingWithOptions:)`, which now owns `AppModel`), as
     Apple requires. Observer completion always runs. A failed enable leaves the
     choice off.
   - Without the choice, Health is read in the foreground and during iOS-granted
     BGAppRefresh opportunities only. Neither path is continuous monitoring.
   - Tests: `HealthBackgroundDeliveryTests` (3).
4. **Write-only permission and sync versions (documentation; device unverified).**
   - Apple's `HKHealthStore.authorizationStatus(for:)` docs: "If your app is given
     share permission but not read permission, you see only the data that your app
     has written to the store." So the own-sample lookup should work with write-only
     permission.
   - `HKMetadataKeySyncIdentifier` docs require `HKMetadataKeySyncVersion` (both are
     set) and say a save with a *greater* version replaces the old object. Equal and
     lower versions are undocumented, so Aurora never relies on them: a retry adopts
     an existing own sample at the same or higher version instead of saving again, and
     writes only when the lookup finds none.
   - A failed lookup records a failure and writes nothing. A confirmation is recorded
     only when Health returns a saved UUID or the lookup finds the sample.
   - Residual risk: a sample the person deleted in the Health app after an
     interrupted write would be written again on Retry.

## Final review corrections (2026-10-09, separate commit)

Responds to `aurora-overnight/health-final-review.md`.

| Command | Result |
|---|---|
| `TZ=UTC DEVELOPER_DIR=… swift test --package-path AuroraCore` | 164 tests in 24 suites passed (parity fixtures unchanged) |
| `TZ=America/Los_Angeles DEVELOPER_DIR=… swift test --package-path AuroraCore` | 164 tests in 24 suites passed |
| `DEVELOPER_DIR=… swift test --package-path AuroraCore --filter "Health\|RefreshCoordinatorTests\|StateMigrationTests\|SleepChangeSuggestionTests" --maximum-repetitions 200 --repeat-until fail` | 87 tests in 17 suites passed, no failures in 200 repetitions |
| generic unsigned `xcodebuild build` / `build-for-testing` | BUILD SUCCEEDED / TEST BUILD SUCCEEDED |
| `swift /private/tmp/aurora-anchor-check/check.swift` (macOS HealthKit, no store) | nil anchor reads as a first read; a valid archive round-trips; empty, garbage, truncated and foreign archives all throw |

**Not run:** the new native `AuroraTests/HealthAnchorCodecTests.swift` (4 tests) on a
simulator. It's Codex's lane and the tests compile only. The macOS script mirrors
their decode rules but isn't the app target. No device or live Health.

1. **Invalid anchors.**
   - The new `HealthAnchorCodec` (secure coding) returns nil only for a missing
     anchor. Empty, corrupt, truncated or non-anchor data throws
     `HealthProviderError.invalidAnchor(kind)`.
   - The read fails with: "Aurora couldn't resume where it left off in Apple Health.
     Your records here are unchanged. Choose Restart reading…". Records and the
     stored anchor are kept, `lastRead.invalidAnchor` is set, and repeated refreshes
     keep failing rather than reading from the beginning.
   - Recovery is a person-initiated "Restart reading caffeine/sleep" button
     (`restartReading`). It clears only the anchor; the re-read matches by UUID, so
     nothing duplicates.
   - **Limitation:** entries deleted in Health while the position was lost may stay
     listed until Delete All Records. No records are destroyed to recover.
2. **Bounded pages.**
   - `HKAnchoredObjectQueryDescriptor(…, limit: 500)` for both kinds.
     `hasMore = added + deleted >= 500`. A full page ending exactly at the end reads
     one more empty page, which is harmless.
   - The engine applies at most `maxPagesPerRead` (4) pages per activation. Each page
     commits with its anchor before the next fetch, and re-checks the generation, the
     choice, Sample Data and the anchor after every await.
   - `HealthCaffeineChanges` and `HealthSleepChanges` gain `hasMore` (default false).
     Results carry `pages` and `hasMore`. `HealthReadRecord` gains `hasMore`, `pages`
     and `invalidAnchor`, and older records still decode. There's a new
     `ledger.lastSleepRead`.
   - Partial sleep sets `HealthImportStatus.partial` ("Sleep partly imported", never
     "No sleep found"). It stays due for the next foreground or background
     opportunity. The caffeine summary says "partly read so far".
   - Legacy start:end sleep conversion now applies on every page, still by exact
     interval only.
   - Tests in `HealthPagingTests` (8): more data than one page, a deletion at a page
     boundary, a redelivered page after a failed save, erase or turn-off between
     pages, a failure on a later page that keeps the earlier pages and resumes,
     corrupt anchor and restart, partial sleep status, and old-record decoding.
3. **Sleep-change suggestions.**
   - `SleepChangeSuggestion` (core, deterministic, no model) compares recorded,
     non-sample sleep from the last 24 h by id and interval. It offers the existing
     sleep suggestion only when that snapshot changed, and only through
     `ProactivePolicy`: opt-in, quiet hours, two per day, dismissals, one delivery per
     key. The key format is unchanged, so earlier deliveries still count.
   - `AppModel.performRefresh` calls it after a Health-change refresh that changed
     sleep. `AssistantView`'s sleep `onChange` now uses it instead of the full
     suggestion pass, so it no longer brings up briefing or calendar suggestions.
   - **Limitation:** when Health wakes Aurora in the background before the assistant
     has started, no offer is made then. The unchanged foreground pass offers it at
     the next opportunity if it's still undelivered.
   - Tests in `SleepChangeSuggestionTests` (3): unchanged and sample-only sleep,
     update and once-only delivery, dismissal, quiet hours and the daily cap.

## What shipped

**Core (AuroraCore):**
- `HealthChoices` (stored in `AppState.healthChoices`) has three independent opt-ins:
  `readSleep`, `readCaffeine`, `writeCaffeine`. Each `HealthChoice` asks Health for its own
  permission only. A state without the key decodes `readSleep` from the old
  `permissionStatus == .granted`; no schema bump.
- `HealthSyncEngine` (MainActor), injected `HealthDataProvider`:
  - `setChoice`. Turning a choice on refuses with `.sampleData`, `.paused` (ledger newer
    than this build), `.unavailable` or `.unsupported`. Turning it off bumps a per-kind
    read generation or the export generation, stops that observer, and cancels queued
    actions (for write).
  - `readCaffeineChanges`. An anchored read applies by sample UUID only. The anchor is
    saved in the same commit as the records. If the read fails, the commit fails, or the
    result is stale, the anchor doesn't move. Read results and failures land in
    `ledger.lastCaffeineRead` as counts only.
  - `runPendingActions`. Chained, so a save and a later delete never overlap. Each action
    is marked `startedAt` (persisted) before Health is called. Retrying a started save
    first calls `ownCaffeineSample(syncIdentifier:)` and adopts a landed sample instead of
    writing twice. A result is applied only if the export generation hasn't changed.
  - Observers start for read choices only. `onChange` is awaited and the provider
    completes Health's notification after it returns. `invalidateAll()` handles erase
    and Delete All.
- Local-first queueing on `AppState`: `queueHealthSave`, `queueHealthCorrection` (only
  re-exports an already exported or queued dose), and `queueHealthRemoval` (drops a save
  that never started, otherwise deletes only Aurora's own sample). Sample Data, Health
  records, export off, and an unsupported ledger queue nothing.
- `HealthExportStatus`: notExported, pending, failed (with Health's message), exported,
  outdated, keptInHealth, removed, cancelled, and uncertain (export was turned off while
  Health was mid-write). Copy passes `CopyRules` and never says granted, denied, or
  "saved to Health" before Health confirmed it.
- `RefreshScheduler` + `RefreshPolicy` form the one coalescing refresh path. A burst
  during a run becomes at most one follow-up run, with at most 2 runs per activation. A
  Health change refreshes only the changed kind. Calendars refresh on foreground,
  background or explicit requests with a 15-minute freshness window. Suggestions run on
  foreground or background only, under the existing ProactivePolicy limits.
- `RecordSource` gains Health and its combinations, so Export CSV, Summary signals and
  cards no longer call Health caffeine "Manual". Earlier Aurora copies re-imported after
  erase or reconnecting are labeled ("Added to Health by Aurora earlier") and read-only.

**App:**
- `HealthKitService` implements sleep reads, the `HKAnchoredObjectQueryDescriptor`
  caffeine read (anchor archived with secure coding), own writes with
  `HKMetadataKeySyncIdentifier`/`SyncVersion`/`AuroraRecordID`, and own-only deletes and
  lookups (`HKSource.default()` AND the sync identifier). Writes and deletes check
  `authorizationStatus == .sharingAuthorized` first. Observer completion always runs,
  including on error.
- `AppModel`: dose save, correction, delete and Undo store the dose and its Health action
  in one `update`, then run the action. `healthStatus(forDoseID:)`,
  `retryHealthExports()`, `setHealthChoice`, `refresh(_:)`. Erase and Delete All call
  `cancelHealthWork()`. Sleep import also checks the sleep read generation.
- Receipts carry their own "Apple Health" metric row, separate from the local title, and
  it updates once Health answers. Undo receipts and history deletes report removal the
  same way. Log rows and the quick-add confirmation show "Apple Health · …".
- `HealthConnectionView` has three toggles with per-choice disclosure and a
  "Requested…" note, Refresh from Health, and the outbox summary with an explicit Retry.
  Existing accessibility identifiers are kept.
- `AuroraApp` and `AssistantView`: foreground, BGAppRefresh and observers all go through
  the scheduler. Background refresh is requested when suggestions are on or any read
  choice is on.
- Fixed: `DoseRow` labeled every read-only entry "Sample Data". `SleepView` pull-to-refresh
  now honors the sleep choice.
- Disclosures now describe only what's implemented: Info.plist share/update/clinical
  strings, `privacy.html`, `website/src/App.tsx`, app-store metadata (App Privacy must
  declare caffeine written), README, SECURITY, agents.md, and onboarding copy.

## Review notes (races, permissions, identity, receipts)

- **Late writes.** Erase or turning export off during an in-flight save: the sample may
  land in Health, but no outcome or own-export is recorded. The status reads `.uncertain`,
  never success. On read-back it's Aurora's own (bundle source) and is matched to its dose
  by sync identifier, or kept read-only if no local dose exists. Tests:
  `eraseDuringAnExport…`, `turningExportOffMidWrite…`, `aWriteKilledMidFlight…`.
- **Undo during a write.** The delete replaces the save, and the chain runs the delete
  after the save returns, leaving no Aurora sample in Health (`undoWhileTheExportIsInFlight…`).
- **Identity.** Health caffeine is matched only by its lowercased sample UUID; identical
  time and amount from different sources stays separate. Ownership is the exact bundle
  `com.nmapaye.aurora` (confirmed as the app target's `PRODUCT_BUNDLE_IDENTIFIER`) or a
  ledger UUID, never metadata alone.
- **Permissions.** Empty reads are reported as "found no changes". A write refusal keeps
  the dose and shows "Not exported" with Health's message.

## Known gaps and decisions for Codex

- **Retry is explicit.** An action interrupted by app termination shows "Export pending"
  after relaunch until Retry; there's no automatic background retry.
- **Background delivery** (superseded by the corrections above): it's an opt-in
  backed by a declared entitlement. The provisioning profile must carry the
  entitlement before it can work on a device.
- **Turning a read off keeps already-imported records** as a read-only cache. Delete All
  keeps the choices, so Health records, and Aurora's earlier copies, re-import as
  read-only.
- **Full erase never deletes Health samples.** No in-app option exists to remove Aurora's
  exports from Health; that would be a separate user-approved feature.
- **Turning sleep off** leaves `onboarding.permissionStatus` as is. The Sleep status card
  can still read "Health sleep imported" for the cached records.
- **Codex lane:** run `HealthSyncAppTests` plus the existing phone/pad suites, and
  capture the Health screen and receipt states for visual review.

## Physical-device gates (all unverified)

Signed build on a real iPhone:
- Allow all, deny all, and mixed choices.
- Revoke write in Settings after exporting.
- Import from a second source with identical time and mg.
- Export, edit, Undo, then inspect Aurora's samples in Health's Sources.
- `ownCaffeineSample` lookup with write-only permission (documented by Apple, not yet
  observed on a device).
- HealthKit's sync-version replacement behavior, including equal versions.
- Anchored sleep import from Watch plus a second app on the same night, then deleting
  one sample in Health.
- Upgrading a device that holds legacy start:end sleep records.
- With "Update in the background" on: whether a signed build carries the
  background-delivery entitlement, when and whether Health wakes the app after the hourly request while
  it's suspended or terminated, observer registration at background launch, and
  battery impact.
- Kill the app mid-write, relaunch, and Retry.
- Erase, and confirm exports remain.
- Observer delivery after relaunch, and BGAppRefresh with Health choices on.
- App Store privacy label, TestFlight.
