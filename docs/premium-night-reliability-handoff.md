# Premium night package 1: launch and interaction reliability — 2026-10-10

Branch `claude/aurora-premium-night-2026-10-10`, base `448c002`. Claude, isolated
worktree. Provisional until Codex reviews and runs the simulator lane. No pushes,
installs, simulator runs, resets, signing changes or personal-data access.

## Blank cold launch: not reproduced, cause not established

Observation (noon, 2026-10-09, `docs/native-assistant-verification.md`): the
integrated unsigned Release, newly installed on the retained-data Aurora
Assistant iPhone, first showed only its launch background; a normal
terminate/relaunch restored the conversation.

Evidence available here:

- `/private/tmp/aurora-energy-integrated-release.log` is a build log only
  (`BUILD SUCCEEDED`); it holds no launch timing or runtime output.
- `~/Library/Logs/DiagnosticReports` has no Aurora app crash or watchdog
  report. The only Aurora entries are `AuroraUITests-Runner` reports from
  2026-10-08 10:37 and 2026-10-09 01:19, before the observation.
- No unified-log capture of that launch exists. This package may not run or
  query the simulator, so the launch was not reproduced.

Source review of everything that runs before the first frame. These are
candidates to measure, not established causes:

1. **Storage opens before any frame.** `AppDelegate.didFinishLaunching` calls
   `AppModel.load()` synchronously: backup-exclusion check, `StateMigration`
   decode/verify, the one-time `state.pre-assistant.json` write, pending
   erase completion and possible legacy import. `BootView` ("Loading Aurora…")
   can only appear after the first frame, so while this work runs the launch
   background is all anyone sees. Loading UI cannot show during a slow open.
   Not moved: agents.md requires Health observers to register at launch in
   `AppDelegate`, which needs the loaded choices. Any reordering is a
   storage/Health contract decision for Codex.
2. **App init does Keychain and EventKit work.** `@State AssistantModel()` →
   `CalendarService()` → `EKEventStore()` plus `GoogleCalendarProvider.init`'s
   synchronous `SecItemCopyMatching`, before the first frame. A first launch of
   a newly installed unsigned binary is the case most likely to differ here.
3. **The first conversation frame queries the model framework.**
   `AssistantModel.intelligenceName` reads `SystemLanguageModel.default.isAvailable`
   while the first AssistantView body renders. The availability check's cost on
   a first post-install launch is unknown.
4. **Capture tooling.** Earlier sections record Device Hub showing an
   incomplete or stale app view after test runs. A stale display can't be
   ruled out without a log of the launch itself.

After the first frame, `AssistantModel.start` loads the conversation and lists
calendars on the main actor. These can delay the cards but not hide the whole UI.
Records, quick actions and cards do not wait for model readiness. Prewarm runs
only when the composer gets focus, and classification only when a message is
sent.

No app fix is made for the launch. Fixes for 1–3 would be speculative without
timings.

### Instrumentation added (content-free)

`Aurora/Services/PerformanceSignposts.swift`: `OSSignposter` (subsystem
`com.nmapaye.aurora`, Points of Interest) and a `lifecycle` Logger. Only fixed
names, route words and storage phase are recorded. No request text, records,
Health, calendar or conversation contents, counts or identifiers. Nothing is
uploaded.

| Signpost | Kind | Measures |
|---|---|---|
| `Launch.CalendarServiceInit` | interval | EventKit + Keychain lookup during App init |
| `Launch.StorageLoad` | interval | `AppModel.load()` in `didFinishLaunching` |
| `launch storage phase: …` | log notice | `ready` / `storageUnavailable` / `loading` |
| `Launch.SceneTask` | event | scene `.task` started |
| `Launch.{Boot,Recovery,Assistant,Onboarding}Visible` | event | which root view first appeared |
| `Assistant.Start` / `.ConversationLoad` / `.CalendarListRefresh` | intervals | post-frame startup |
| `Assistant.ModelAvailability` | interval | the availability read on each render |
| `Assistant.Prewarm` | interval | synchronous part of prewarm on composer focus |
| `Assistant.Classify` | interval | message `explicit`/`cached`/`on-device`/`mac-local`, `… ended` if failed or stopped |
| `Assistant.Card` | interval | deterministic card build/handling after classification |
| `Assistant.Cancel` | event | Stop pressed |

Suggested capture for Codex: run Instruments' App Launch template, or run
`xcrun simctl spawn <device> log stream --level info --predicate 'subsystem == "com.nmapaye.aurora"'`
during a fresh-install cold launch. If `Launch.AssistantVisible` fires promptly
but the screen stays blank, suspect rendering or tooling. If `Launch.StorageLoad`
or `Launch.CalendarServiceInit` is long, candidate 1 or 2 is the cause. These
are simulator timings, not physical-device performance.

## Composer and caffeine draft keyboard

Finding (evidence: the 2026-10-09 morning QA notes and the `testCaffeine…`
comments): while a card field was focused, the composer inset rode above the
keyboard with its hint, quick-action strip and composer. That pushed the
draft's Save beneath the inset, and swipes landed on the quick-action strip.
The numeric amount field has no Return key, so the user can't dismiss the
keyboard from it. Codex's earlier correction changed only the test.

Fix: `AssistantCardView` tracks focus of its own fields (amount, source,
check-in/sleep note, history search) and publishes
`AssistantModel.editingCardField`. While a card field is focused and the
composer isn't, `AssistantView` hides the hint and quick-action strip and keeps
the compact composer, so Save has the space. Both return when focus ends,
the card disappears, the scene leaves active, or after an erase. No token,
color, spacing, placeholder, Save/Discard, validation, receipt or duplicate
protection changed. `design.md` records the rule.

Not changed (noted for review): the vertical-axis composer's Return/`onSubmit`
behavior and prewarm on focus. I had no evidence of a defect in either; the
signposts now time prewarm.

Known limitation: if focus jumps directly between fields in two different cards,
the outgoing card's update may arrive after the incoming one's. The strip then
shows, which matches the old behavior; it never hides permanently.

## Files

- `Aurora/Services/PerformanceSignposts.swift` (new)
- `Aurora/App/AppDelegate.swift`, `Aurora/App/AuroraApp.swift`: launch signposts
- `Aurora/App/AssistantModel.swift`: startup/classify/card/cancel signposts, `editingCardField`
- `Aurora/Screens/Assistant/AssistantCardView.swift`: card field focus
- `Aurora/Screens/Assistant/AssistantView.swift`: collapsing inset (strip extracted unchanged)
- `AuroraUITests/AuroraUITests.swift`: `testDraftFieldKeepsSaveAboveCollapsedComposer`
- `design.md`, this handoff

AuroraCore, storage formats, record semantics, Health identities/ledger,
calendar approval, Energy UI and onboarding are untouched.

## Verification actually run (this worktree)

| Check | Result |
|---|---|
| Core `swift test`, TZ=UTC | 186/186 passed |
| Core `swift test`, TZ=America/Los_Angeles | 186/186 passed |
| Unsigned Release, generic iOS Simulator, `CODE_SIGNING_ALLOWED=NO` | Built, no warnings/errors (`-quiet`), DerivedData `/private/tmp/aurora-night-2026-10-10-release-dd` |
| `build-for-testing` with ordinary ad-hoc signing (`CODE_SIGN_IDENTITY=-`) | App, `AuroraTests.xctest` and `AuroraUITests.xctest` compiled; xctestrun at `/private/tmp/aurora-night-2026-10-10-tests-dd/Build/Products/` (rebuilt after the new UI test) |
| `git diff --check` | clean |

Core scratch path: `/private/tmp/aurora-night-2026-10-10-core-build`. Build
output wasn't saved to separate log files because writing to `/private/tmp` by
shell redirection needed permission this session didn't have.

Not run: any simulator native/UI test, install or launch (Codex's lane);
`scripts/check-design-tokens.py` (needed approval; no colors or tokens changed);
visual inspection of the collapsed inset; physical-device anything.

## Next steps for Codex

1. Review the diff. Run native tests, then serial phone/pad UI, especially
   `testDraftFieldKeepsSaveAboveCollapsedComposer`,
   `testCaffeineNeedsReviewAndUndoRemovesOnlySavedEntry`,
   `testInlineSleepSaveCreatesReceipt`, history search, AX XXXL reachability.
2. Inspect the collapsed inset with the keyboard up (light/dark, phone/pad,
   largest text) and check that the strip returns after Return, scroll
   dismissal and Save.
3. Capture signposts on a fresh-install cold launch of the unsigned Release
   on a dedicated QA device (not the retained-data demo) to classify the
   blank launch. Decide on the storage-before-first-frame ordering only with
   those timings.
4. Physical-device launch, keyboard and performance acceptance remain release gates.

The Python supervisor snippet attached to the task prompt was **not** run. It
would start a process outside this worktree, conflicting with "no
parallel/subordinate writers."
