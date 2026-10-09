# Energy Health handoff (Package 2)

Branch `claude/aurora-health-native`, base `3952667` (accepted foundation). One local
commit; nothing pushed. No signing, team, entitlement, account or global configuration
changes, no new keys, no personal records. Claude implemented core, services and the
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
- **No HealthKit background delivery.** It needs the
  `com.apple.developer.healthkit.background-delivery` entitlement, which is a signing
  decision. Observers run while the process is alive; BGAppRefresh is the background
  path.
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
- `ownCaffeineSample` lookup when caffeine read is not allowed (relies on apps seeing
  their own samples).
- HealthKit's sync-version replacement behavior.
- Kill the app mid-write, relaunch, and Retry.
- Erase, and confirm exports remain.
- Observer delivery after relaunch, and BGAppRefresh with Health choices on.
- App Store privacy label, TestFlight.
