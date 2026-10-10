# Premium night package 2: welcome and onboarding — 2026-10-10

Branch `claude/aurora-onboarding-night-2026-10-10`, worktree
`/Users/nmapaye/Developer/aurora-onboarding-night-2026-10-10`, base accepted `33e63bc`.
Claude, isolated. Provisional until Codex reviews and runs the native/UI lane. Local
commits only. No pushes, installs, simulator runs, resets, signing or account changes.

## Commits

| Commit | Source | Content |
|---|---|---|
| `5dea303` | adapted from `56f30bd` | Core only: optional fields, `Welcome`, `SetupStep`, `FirstRun`, `SetupCopy`, `WelcomeTests` |
| `6d15da5` | adapted from `47cd239` | Views, RootView integration, sky tokens, AppModel setters, test helper, native/UI tests, `design.md` |
| (this file) | — | Handoff |

Both source commits were reviewed separately with `git show` and re-applied by normal
edits. Nothing was cherry-picked. The original `claude/aurora-welcome-onboarding`
worktree is untouched: still at `47cd239`, with the untracked
`AuroraUITests/ZZCaptureTests.swift` still there.

`state.json` / `task.md` package files: not found under this worktree,
`aurora-assistant`, `~/.codex` or `/private/tmp/aurora-*`. I did not create or archive
them. Codex should update its own copies.

## Core (`5dea303`)

- `Prefs.displayName`, `Prefs.favoriteDrinkIDs`, `Onboarding.setupStep`: all optional.
  Older files decode them as nil, and they aren't written while nil. There's no schema
  bump or record change.
- `FirstRun(onboarding)`: `.done` whenever `completed`, so existing completed users never
  see setup. `.story` before setup starts. `.setup(step)` resumes from the stored step.
- `SetupStep` keeps stored raw values: name 0, sleepTarget 2, health 4, calendar 5,
  finish 6. Retired source values 1 (favorite drinks) and 3 (sleep source) resume at
  the next question still asked, and out-of-range values clamp.
- `Welcome.evidence`: at most one *captured* record. Sleep that ended in the last
  6 h comes first, then caffeine recorded today. Each has a date ("Ended today, 6:42
  AM" / "Last today, …"), a source (Health / Manual / Sample Data, joined when mixed)
  and a `sample` flag. Dropped from the source: calendar commitments, which go stale,
  and the modeled active-caffeine line, which is an estimate. With no record the result
  is nil, so the welcome shows "Ready when you are." and never 0 mg.
- `Welcome.Presentation`: shown only when setup is done and VoiceOver is off.
  `skip()` is a synchronous state change.
- `SetupCopy`: scenes, questions, a model-unavailable finish line, Health answer/note
  (never "granted"; covers denied, empty-read, unavailable and Sample Data) and the
  Sample Data note. All of it is checked against `CopyRules`.
- `CaffeinePreset.ordered(favorites:)` is kept, but no UI uses it yet (see Limitations).

## UI (`6d15da5`)

- **RootView**: `Launch.*Visible` signposts are kept. The welcome is decided once, the
  first time storage reaches `.ready`, so it never appears after finishing setup or
  after an erase. The overlay's `allowsHitTesting` and the conversation's
  `accessibilityHidden` both come from `Welcome.Presentation`. A tap calls `skip()`,
  which releases both in the same update. The 0.25 s opacity fade then runs on a
  non-interactive layer that is removed on completion. Reduce Motion removes it
  immediately. Auto-end comes after `holdSeconds` (1.2 s). Debug-only
  `-AuroraWelcomeHold` keeps it up until tapped.
- **Sky** (`Aurora/Screens/Welcome/AuroraSky.swift`, `Sky` in `Palette.swift`):
  gradients use only existing Brand ivory/ink/sea values, and ribbons use only aurora
  teal/mint/indigo. The source's `auroraDawn` and extra hex values are gone.
  `TimelineView` is paused when `scenePhase != .active` and static under Reduce Motion.
  `auroraGlass` uses `glassEffect` on iOS 26+ and `.regularMaterial` with a card
  border on iOS 17–25.
- **Story**: three scenes, with Skip always shown and Continue / Begin setup.
- **Setup conversation**: name → sleep target → Health → calendar → finish. Every
  question has "Not now", and "Skip to the end" (`setup-skip-all`) is always present.
  - Health shows Read sleep / Read caffeine / Add my caffeine to Health as separate
    toggles calling `AppModel.setHealthChoice`, the same path as `HealthConnectionView`.
    The old `requestHealthForOnboarding` (sleep-only) is no longer called; it is still
    defined in AppModel. Background updates stay in Settings.
  - Leaving Health without Read sleep sets the source to manual, unless a declined
    request already did.
  - Calendar opens the existing `CalendarConnectionsView`. Nothing is connected or
    selected automatically.
  - Finish: "Start with Aurora" or the separate "Explore with Sample Data", with the
    labeled note.
- **AppModel**: two narrow setters, `setDisplayName` and `setSetupStep`. The Health,
  Energy, storage, calendar and classification code is unchanged.

### Interaction contract change for Codex review

`RootView` runs `model.foregroundSync()` once when `onboarding.completed` becomes true.
Otherwise a Health read turned on during setup (for example Read caffeine, whose
`.explicit` refresh is skipped before completion) would wait for the next foreground.
This is the same call every activation makes: reminder sync, observers,
`refresher.request(.foreground)`, and calendars/suggestions only under their existing
opt-ins. If you don't want it, remove the `.onChange` in `RootView`. Then caffeine read
during setup imports at the next activation.

### Test helper change

`AuroraUITests.finishSetup()` now taps `onboarding-skip-story` → `setup-skip-all` →
`setup-finish`, which requests no Health or calendar access, and adds `tapWhenReady`.
The erase test now expects `onboarding-skip-story` instead of `onboarding-continue`.
No other assertion was removed or weakened.

## Tests added

| Suite | Test | Covers |
|---|---|---|
| Core `WelcomeTests` (19, both zones where time-dependent) | daypart, greeting/name cleaning, no-records → nil (never zero), sleep source/date, yesterday date, naps/old/future ignored, caffeine total/sources (no estimate in evening), mixed Sample Data labeled, CopyRules for all copy, VoiceOver/incomplete never show, **instant skip** releases touches and accessibility in one mutation, setup order, retired-step resume, `FirstRun` keeps completed users out, **old file migration/defaults**, unset fields not written + round-trip, favorites order, Health copy (denied/empty/unavailable/sample, never "granted"), **model-unavailable** finish line | |
| Native `SetupProgressAppTests` (compiled only) | resume after relaunch + completed stays done + no Health requests from answers; no-records/Sample Data evidence; setup Health choices request only their own permission; declined sleep → manual/denied + honest note | |
| UI (compiled only) | `testStoryLeadsIntoSetupThatSkipsEachStepAndResumesAfterRelaunch`, `testWelcomeGreetsByNameAndATapSkipsAtOnce` | |

## Checks actually run (this worktree)

| Check | Result |
|---|---|
| Core `swift test`, TZ=UTC (`--scratch-path build/core`) | 208/208 passed (189 + 19) |
| Core `swift test`, TZ=America/Los_Angeles | 208/208 passed |
| `build-for-testing`, generic iOS Simulator, `CODE_SIGN_IDENTITY=-`, DerivedData `build/dd` | App, AuroraTests (incl. `SetupProgressAppTests.o`), AuroraUITests compiled; no errors/warnings under `-quiet` |
| Unsigned Release, generic iOS Simulator, `CODE_SIGNING_ALLOWED=NO`, DerivedData `build/dd-release` | Built; no errors/warnings under `-quiet` |
| `python3 -I scripts/check-design-tokens.py` | "Aurora brand-token check passed" |
| `git diff --check` | clean |

**Not run** (Codex's lane): native AuroraTests, every UI test, any install/launch,
visual or VoiceOver/Reduce Motion checks, iPad, and anything on a physical device.
I make no runtime claim about any of them.

## Limitations and unresolved gates

1. **Welcome on relaunch in existing UI tests.** Tests that relaunch a completed app
   (`launchArguments = []`) now get the welcome for about 1.2 s. During that time the
   conversation is hidden from accessibility, so queries wait through it with
   `waitForExistence`. A test that taps without waiting could fail. That would be a
   test-timing fix, not a reason to remove the welcome.
2. **Removal transition and hit-testing.** The release is guaranteed by
   `allowsHitTesting(false)` set in the same update, not by SwiftUI transition
   behavior. Runtime confirmation is `testWelcomeGreetsByNameAndATapSkipsAtOnce`
   (Send exists within 1 s of the tap and Log caffeine is hittable).
3. **Favorite drinks.** The field and `CaffeinePreset.ordered` are kept, but the
   setup question was dropped. Quick Add (`LogView`) is only reachable through
   `MainTabs`, which RootView doesn't show, so "I'll put those first" would be untrue.
   Bring it back when a reachable caffeine picker uses favorites.
4. **VoiceOver** users get no welcome at all, by design, to avoid a duplicate
   announcement and a focus trap. Setup posts one announcement per new question. That
   isn't verified by ear.
5. **Glass fallback** on iOS 17–25 and sky performance haven't been seen on device.
6. **Dropped from the source:** `ReturnGlow`, `Haptics.soft` and the `auroraDawn` color.
   That keeps Services and the palette unchanged.
7. `requestHealthForOnboarding` and `OnboardingCopy.stepCopy`/`nextAction` are now
   unused by the UI. They are left in place (Codex lane) and could be removed in a
   cleanup.
8. Release gates remain: physical-device onboarding with Health allow/deny, VoiceOver,
   Dynamic Type AX sizes, Reduce Motion, iPad split, signing, TestFlight.

## Corrections after Codex review (`onboarding-review.md`)

| Commit | Content |
|---|---|
| `f8152d5` | Core: `Onboarding.setupOutcomes`, `AppState.recordSetup/skipSetupToEnd/settleSetupSleepSource`, `SetupTranscript`, 8 new core tests |
| `aac442b` | App: atomic AppModel helpers, setup view transcript/skip/errors, native failure-injection tests, UI regressions and screenshots, `design.md` |

1. **Truthful transcript.** The new optional `Onboarding.setupOutcomes: [String: String]?`
   maps a `SetupStep` raw value to `answered` or `skipped`.
   - Why it's needed: progress alone can't tell a skipped question from one never
     asked.
   - Old files decode it as nil, and it isn't written while nil. Plain strings mean an
     unknown value from another build is ignored instead of failing the `AppState`
     decode.
   - No record or schema change.
   - What the transcript shows:
     - Only questions with a recorded outcome, plus the current question.
     - "You" for typed or chosen answers and for an explicit "Not now".
     - A sleep target kept by "Not now" as an Aurora note ("Sleep target stays at…").
     - Nothing for questions passed over by Skip to the end.
   - Progress from `807039d`-era files (no outcomes) still shows a stored name as
     answered, since a name only comes from that question. It shows nothing else.
2. **Sleep target "Not now".** The stepper edits a local draft. Continue saves the
   target and `answered` together. "Not now" saves only `skipped` and the next step, so
   the stored target stays. Every optional question now has its own "Not now".
3. **Atomic saves and visible errors.**
   - New helpers: `AppModel.recordSetup(step, outcome, answer:)`, `skipSetupToEnd()` and
     `finishSetup(withSampleData:)`. Each is one `update`.
   - `completeOnboarding()` and `setSetupStep()` now return `Bool`
     (`@discardableResult`). `setDisplayName` is removed.
   - On failure, `update` already restores the previous state. The view then stays on
     the question and shows the real `mutationFailure` in error tone with its symbol
     (`setup-save-failure`, or `story-save-failure` on the story). It also posts an
     announcement and leaves the controls ready for a retry.
   - Sample Data plus completion is now one change, so a failure loads nothing.
   - `update`, erase generation, Health/Energy/calendar/intelligence code paths and
     record formats are unchanged. `loadSampleData` only had its body extracted into
     a shared static helper; its behavior is unchanged.

Tests added:
- **Core:** skip-to-end (from the start and mid-setup), per-step skip keeping settings,
  explicit answers, resume round-trip plus an old-progress file, unknown outcome values,
  completed old users, settle keeps a declined status.
- **Native (compiled only):** failed name save stays on the question and retry saves
  name and step together; failed skips, skip-to-end and setSetupStep don't advance or
  record; failed finish (with Sample Data) leaves setup open with no samples, then a
  retry completes; skip-to-end invents no answers. Failures are injected by replacing
  `state.json` with a directory, the same technique as `failedSaveRestoresPreviousRecords`.
  No sleeps or timing.
- **UI (compiled only):**
  - `testSkipToEndShowsNoAnswersForQuestionsNotAsked`
  - `testSleepTargetNotNowKeepsTheSettingAsAuroraNote`
  - `testHealthSetupAtLargestTextRequestsNothing`
  - The story test now also asserts "You: 8 hours" after an explicit Continue.
- **Screenshot attachments:** "First story scene", "Health setup at largest text",
  "Held welcome".

Runtime-unverified selectors: `app.steppers["setup-sleep-target"].buttons.element(boundBy: 1)`
as the Increment button, and `staticTexts["setup-retained-sleepTarget"]`.

Checks run for the corrections:

| Check | Result |
|---|---|
| Core `swift test` TZ=UTC / America/Los_Angeles | 216/216 each |
| `build-for-testing`, ad-hoc simulator signing | App, AuroraTests, AuroraUITests compiled, no errors/warnings (`-quiet`) |
| Unsigned Release, `CODE_SIGNING_ALLOWED=NO` | Built, no errors/warnings |
| `scripts/check-design-tokens.py` | passed |
| `git diff --check` | clean |

Not run: native AuroraTests, UI tests, installs, visual review. The failure-path UI (error
banner layout and announcement) has not been seen at runtime.

## Next steps for Codex

1. Review `5dea303` (core) separately from `6d15da5`, then `f8152d5` and `aac442b`.
2. Run core in both zones, then native AuroraTests (including `SetupProgressAppTests`),
   then serial iPhone/iPad UI, especially the two new UI tests, the erase test and any
   test that relaunches a completed app.
3. Visually inspect story, setup (light/dark, AX XXXL, iPad), welcome with no records,
   sample and Health evidence, and Reduce Motion.
4. Decide on the completion `foregroundSync` contract note above.
