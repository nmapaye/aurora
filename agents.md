# Aurora: Agent Handoff

## What this is

Aurora is a native SwiftUI app for iPhone and iPad (iOS 17+). It tracks
caffeine against sleep and alertness through optional HealthKit sleep and
caffeine import, optional export of caffeine saved in Aurora, manual logging, a 30-second Reaction Test, and an alertness
estimate. A standalone Vite showcase site lives in `website/`.

The app was rewritten from React Native and Expo in October 2026. The rules,
copy and estimates were ported one-to-one. The core tests still compare
against fixtures the TypeScript code generated before it was removed, in UTC
and America/Los_Angeles.

The target is a paid App Store v0.1.1 release, free TestFlight beta testing,
and an optional Gumroad companion guide.

## Layout

- `AuroraCore/`: a Swift package with no UIKit, which builds on Linux too.
  - `Models.swift` and `AppState.swift`: the stored records and every action
    that changes them.
  - `Algorithms.swift`: caffeine decay, circadian term, sleep debt, inertia,
    alertness.
  - `Summary.swift`, `Sleep.swift`, `Insights.swift`, `CaffeineLog.swift`:
    what each screen shows and says.
  - `Signals.swift`: the signal card contract.
  - `Export.swift`: the three CSVs.
  - `Walkthrough.swift`: the ten steps, their reducer and deep links.
  - `LegacyState.swift` and `MMKVReader.swift`: the import from the old
    build.
- `Aurora/`: the app.
  - `App/AppModel.swift` owns the state and saves after every change.
  - `App/Router.swift` holds tabs, pushed screens and modals.
  - `Screens/Assistant/AssistantView.swift` is the primary conversation surface.
  - `App/AssistantModel.swift` owns conversation, snapshots, proposals, receipts, and proactivity.
  - `AuroraCore/AssistantCard.swift` builds finite typed native responses; models never populate UI data.
  - `Services/LocalIntelligence.swift` classifies typed intents locally; no cloud AI.
  - `Services/` covers storage, HealthKit, reminders and haptics.
  - `Screens/` has one folder per screen.
- `AuroraTests/` (Swift Testing) and `AuroraUITests/` (XCTest).

`Aurora.xcodeproj` uses folder-synchronized groups. New files under
`Aurora/`, `AuroraTests/` or `AuroraUITests/` join their target without
project edits. `Info.plist`, `Info-Simulator.plist` and `Aurora.entitlements` are
excluded from the app's resources in the project file. Simulator builds use
`Info-Simulator.plist` (`INFOPLIST_FILE[sdk=iphonesimulator*]`), which adds
only `NSAllowsLocalNetworking` for the Ollama dev path; keep the two in sync.

## Rules that must hold

- Describe what was recorded. Personal suggestions (e.g. a caffeine cutoff
  from the person's own logs) are allowed only when labeled as estimates,
  explained, opt-in, and never framed as medical advice. Never frame caffeine
  against a hard limit, allowance or "remaining" amount, and never make
  health claims or use diagnosis/treatment language. `CopyRules.violations(in:)`
  lists the banned phrasing, and core tests run user-facing copy through it
  (it still needs updating to match this rule).
- No setting is silently applied. Aurora may propose a value with its stated
  reason; the person confirms it with one tap. Until then the cutoff time
  starts unset and its reminder turns on only after the person sets one
  (stored values from older builds are kept). The old "Personal caffeine
  reference" (`dailyLimitMg`) is gone; old files still decode.
- Logging saves immediately with a clear, reliable Undo; every log can be
  undone. Sleep logs may use a confirm card. Calendar changes still need
  fresh explicit approval.
- The person chooses the daily cap on notifications Aurora starts itself
  (default 1 until they change it; briefing first, then drink follow-ups);
  reminders the person set don't count. See `NotificationBudget` and
  `docs/native-assistant.md`.
- A day with no record is "No record", never 0 mg. Averages count recorded
  days only.
- Full-confidence caffeine timing before sleep needs 14 paired nights in
  the last 30 days. A full Reaction Test baseline needs 3 tests in 30
  days. Before that, an insight may appear only as an "early read" labeled
  with the data it uses (e.g. "early read, 5 nights"). A period comparison
  appears only when both periods have enough recorded days.
- Sample Data (ids starting `demo:`) is labeled and read-only everywhere.
  Health sleep and Health caffeine are read-only. Only manual sleep (`manual:sleep:`) and
  recorded caffeine can be edited or deleted.
- HealthKit has three separate opt-ins in `HealthChoices`: read Sleep
  Analysis, read dietary caffeine, and write caffeine saved in Aurora. Each
  asks Health for that permission alone. Imported Health records are
  read-only and match by sample UUID only, never time and amount. Aurora
  writes, edits and deletes only its own samples (exact bundle source, sync
  identifier `com.nmapaye.aurora.dose.<id>`). Never describe access as
  granted: HealthKit doesn't reveal read decisions, and empty reads prove
  nothing.
- Local first: a dose and its queued Health action are saved in one change
  before Health is asked. Receipts report Health's outcome on its own
  "Apple Health" row (`HealthExportStatus`), never as "saved to Health"
  until Health confirmed it. Retry is explicit and checks for an
  interrupted write first. Erase and Delete All cancel Health work and
  leave Aurora's exported samples in Health.
- Health sleep read anchored is keyed `healthkit:sleep:sample:<uuid>` with
  provenance; deletions remove exactly that UUID. Older
  `healthkit:sleep:<start>:<end>` records convert only at their exact
  interval on the first anchored read; others are kept. Equal intervals stay
  separate records; calculations merge intervals and never use ids.
- HealthKit background delivery is its own opt-in (`backgroundUpdates`),
  reconciled at launch and erase. Observers register at launch in
  `AppDelegate`.
- Foreground, background and Health observer refreshes go through
  `RefreshScheduler` and `RefreshPolicy`; Health changes never start
  calendar refreshes or suggestions by themselves.
- The assistant replaces the tab walkthrough and completes its legacy flag.
  Native history, settings, charts, and reaction tests remain reachable.
- Never add an AI API-key field, a remote/cloud model, analytics, or automatic
  calendar writes. A calendar preview must be explicitly approved and
  revalidated. On-device generated text is allowed, but every number in it
  comes from deterministic app code; models never invent values.
- Health data stays on device apart from the person's own private iCloud
  sync (CloudKit private database), allowed in principle but pending
  verification that the App Privacy label stays Data Not Collected.
- Wake reminders fire at offsets the person chose after their recorded wake-up
  (or their usual wake time, outside quiet hours), never at or after their
  own cutoff when one is set. Aurora never applies offsets itself (a
  proposal follows the one-tap rule above); copy says "your reminder", not
  why or how much.
- Day math goes through `LocalClock` and number rounding through `jsRound`,
  so DST and halves behave as they did in the old build.

## Storage

`StateStore` writes `Application Support/Aurora/state.json`. The folder is
excluded from backups, and the exclusion is confirmed before anything is
read; otherwise the app shows a recovery screen. A file that fails to decode
is moved to `state.corrupt.<ms>.json`, never overwritten. `AppState` decodes
missing keys as defaults, so adding a field needs no migration. Bump
`AppState.schemaVersion` only for a change that does. Schema 2 (energy
check-ins, Health sync ledger) is opened through `StateMigration`, which keeps
a verified `state.v1-source.json`, leaves newer or unverifiable files
untouched, and is removed only by full erase.

On first launch, `LegacyImport` reads the React Native build's
`Documents/mmkv/aurora` (key `aurora/state`), saves and verifies the records,
and retains the original folder. Native state also retains a pre-assistant
snapshot. Unreadable files enter recovery without being overwritten.
Conversation has separate version-2, protected local storage. Version-1 migration
retains and verifies the source copy; explicit Clear conversation removes that copy.
Past cards are snapshots with Refresh. Drafts and calendar reviews expire across
relaunches; receipts revalidate the exact record before Undo.
See `docs/native-assistant.md` for full behavior and release gates.

## Checks

- `cd AuroraCore && swift test`
- `xcodebuild test -project Aurora.xcodeproj -scheme Aurora -destination 'platform=iOS Simulator,name=iPhone 17'`
- `npm run site:type-check` and `npm run site:build` for the website

CI runs Swift Core (Linux and macOS), iOS App (iPhone and iPad simulators
plus a Release build), CodeQL (Actions, JavaScript/TypeScript, Swift) and
gitleaks. Never merge on red. Work on isolated branches and keep
verification evidence; nothing merges to main without the owner's explicit
approval, and main is protected (never force-push it).

## Icons and brand

- Warm ivory light surfaces (`#F6F2EA`), deep ink dark surfaces (`#0F1317`),
  and a sea-glass accent (`#1E6B64` light, `#7CC4B8` dark). Every color role
  lives in `Aurora/Theme/Palette.swift`.
- The wave mark is drawn by `AuroraMark` in `Aurora/App/AuroraApp.swift` and
  mirrored by `scripts/make-icons.mjs` and `website/public/aurora-mark.svg`.
  Keep all three in sync.
- `npm run icons` (Node 24) regenerates the icon PNGs in
  `Aurora/Assets.xcassets/AppIcon.appiconset`.

## Landmines

1. **The historical SSH-key alert was false.** The removed file only
   contained the text `REMOVED`; full-history scanning confirmed no private
   key was committed.
2. **Do not bypass FortiGate TLS errors.** If a network re-signs GitHub
   traffic, wait for a clean network or let the repository owner decide.
3. **Unsigned builds can't reach HealthKit.** Set a team to test Health.

## Remaining release work

1. Done: Apple Developer agreements are active, the App ID
   `com.nmapaye.aurora` is registered, and the App Store Connect record
   "Aurora: Energy & Daily Rhythm" exists.
2. Run the device checklist on a physical iPhone and iPad:
   - HealthKit allow, deny and import
   - the cutoff reminder
   - VoiceOver, Dynamic Type and Reduce Motion
   - chart drag versus scroll
   - migration from a phone that ran the React Native build
3. Archive in Xcode, validate in Organizer, and distribute an internal
   TestFlight build.
4. Fill the real website and metadata link placeholders once the public App
   Store and TestFlight pages exist.
