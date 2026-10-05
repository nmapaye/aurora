# Aurora: Agent Handoff

## What this is

Aurora is a native SwiftUI app for iPhone and iPad (iOS 17+). It tracks
caffeine against sleep and alertness through optional read-only HealthKit
sleep import, manual logging, a 60-second Reaction Test, and an alertness
estimate. A standalone Vite showcase site lives in `website/`.

The app was rewritten from React Native and Expo in October 2026. The rules,
copy and estimates were ported one-to-one. The core tests still compare
against fixtures the TypeScript code generated before it was removed, in UTC
and America/Los_Angeles.

The target is a paid App Store v0.1.0 release, free TestFlight beta testing,
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
  - `App/MainTabs.swift` holds the tab bar and the walkthrough coach.
  - `Services/` covers storage, HealthKit, reminders and haptics.
  - `Screens/` has one folder per screen.
- `AuroraTests/` (Swift Testing) and `AuroraUITests/` (XCTest).

`Aurora.xcodeproj` uses folder-synchronized groups. New files under
`Aurora/`, `AuroraTests/` or `AuroraUITests/` join their target without
project edits. `Info.plist` and `Aurora.entitlements` are excluded from the
app's resources in the project file.

## Rules that must hold

- Describe what was recorded. Never prescribe a dose, a bedtime, a wake time
  or a sleep-cycle schedule, and never frame caffeine against a limit,
  allowance or "remaining" amount. `CopyRules.violations(in:)` lists the
  banned phrasing, and core tests run user-facing copy through it.
- The stored `dailyLimitMg` is the user's "Personal caffeine reference". It
  is never a safe amount or a goal.
- A day with no record is "No record", never 0 mg. Averages count recorded
  days only.
- Caffeine timing before sleep shows a number only at 14 paired nights in
  the last 30 days. A Reaction Test baseline appears only at 3 tests in 30
  days. A period comparison appears only when both periods have enough
  recorded days.
- Sample Data (ids starting `demo:`) is labeled and read-only everywhere.
  Health sleep is read-only. Only manual sleep (`manual:sleep:`) and
  recorded caffeine can be edited or deleted.
- HealthKit is read-only, Sleep Analysis only. Never describe access as
  granted: HealthKit doesn't reveal read decisions.
- The walkthrough has exactly ten steps: Summary 1–4, Sleep 5–6, Log 7–8,
  Insights 9–10. While it is pending, tab selection is locked and deep links
  go to the current step's tab.
- Day math goes through `LocalClock` and number rounding through `jsRound`,
  so DST and halves behave as they did in the old build.

## Storage

`StateStore` writes `Application Support/Aurora/state.json`. The folder is
excluded from backups, and the exclusion is confirmed before anything is
read; otherwise the app shows a recovery screen. A file that fails to decode
is moved to `state.corrupt.<ms>.json`, never overwritten. `AppState` decodes
missing keys as defaults, so adding a field needs no migration. Bump
`AppState.schemaVersion` only for a change that does.

On first launch, `LegacyImport` reads the React Native build's
`Documents/mmkv/aurora` (key `aurora/state`), saves the records, and removes
the old folder. An unreadable old store is left alone.

## Checks

- `cd AuroraCore && swift test`
- `xcodebuild test -project Aurora.xcodeproj -scheme Aurora -destination 'platform=iOS Simulator,name=iPhone 17'`
- `npm run site:type-check` and `npm run site:build` for the website

CI runs Swift Core (Linux and macOS), iOS App (iPhone and iPad simulators
plus a Release build), CodeQL (Actions, JavaScript/TypeScript, Swift) and
gitleaks. Never merge on red.

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

1. Configure the Apple Developer team and the App Store Connect record for
   `com.nmapaye.aurora`.
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
