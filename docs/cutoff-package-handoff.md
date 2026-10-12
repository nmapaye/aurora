# Cutoff scenario package handoff

Date: 2026-10-10. Branch `claude/aurora-cutoff-2026-10-10`, base `56ecb12`.
Status: review round 1 corrections done (`0200a81..`), awaiting Codex review.
Not pushed, not integrated.

## Commits

| Commit | Slice |
|---|---|
| `5061f79` | Deterministic contract and calculations (core + core tests) |
| `8dac176` | Planning flow and one-off `ReminderService` API |
| `f821f5d` | Cutoff card, quick action, gallery fixtures |
| `dbdb2c6` | Native regressions (compiled, not run) |
| `7c2f7bb` | `design.md` section, copy fix, first handoff |
| `0200a81` | Round 1 #1: resumed erase clears the scenario reminder |
| `eeeee8a` | Round 1 #2, #3, #5: Save operation identity, ordered writes, capture sync, not-allowed copy |
| `75f5040` | Round 1 #4: UI regressions (compiled, not run) |
| docs commit | This handoff update |

The app target doesn't compile at `5061f79` or `8dac176` alone (new enum cases
hit exhaustive switches in the views); it compiles from `f821f5d`. Cherry-pick
the series together.

## Checks actually run by Claude (after the final source change, `75f5040`)

All with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

- `TZ=UTC swift test --package-path AuroraCore`: **236 tests in 31 suites passed**.
- `TZ=America/Los_Angeles swift test --package-path AuroraCore`: **236 passed**.
- `xcodebuild build-for-testing … -destination 'generic/platform=iOS Simulator'`:
  **TEST BUILD SUCCEEDED**. Object files exist for both `CutoffScenarioAppTests`
  (AuroraTests) and `CutoffScenarioUITests` (AuroraUITests).
- Unsigned Release build (CI's command, `CODE_SIGNING_ALLOWED=NO`): **BUILD SUCCEEDED**.
- `scripts/check-design-tokens.py`: passed. `git diff --check 56ecb12`: clean.

**Not run by Claude:** native `AuroraTests` (`CutoffScenarioAppTests` now has
14 test functions, some parameterized, plus
`LocalDataDeletionTests.resumedEraseClearsScenarioReminderToo`), the 4 new
`CutoffScenarioUITests`, any simulator launch, gallery visual inspection, and
VoiceOver/Dynamic Type/Reduce Motion review. No pass is claimed for these.

## Round 2 corrections (2026-10-12, Claude-only night)

| Commit | Finding |
|---|---|
| `4ab67da` | P1: erase generation captured at enqueue, checked before any notification I/O; `NotificationBackend` injection; `ReminderServiceTests` (gated backend) |
| `9224704` | P2: `AssistantModel.cutoffZone` follows the live system zone (pinned in tests) |
| `92c5740` | P2: entered precision (`0.4 mg`); half-life error shows saved value + Open Settings; P3: header states the real reminder outcome |

Actual checks (Claude ran them):
- Focused native run on disposable "Aurora Night QA iPhone" (iPhone 17,
  iOS 27, `E7D5FEBF…`): `ReminderServiceTests`, `CutoffScenarioAppTests`, and
  `LocalDataDeletionTests` gave **27 tests (31 runs) passed, 0 failed**
  (`build/logs/focused-r2.xcresult`). Most of the 13 minutes went to waiting
  for the new simulator to boot (booted manually with `simctl boot`).
- Core 239/239 in UTC and America/Los_Angeles after `92c5740`.

### Later the same night (Claude-only, all runners Claude's, serial)

| Commit | What |
|---|---|
| `6770573` | Notification calls run on one serial background queue (`LiveNotificationBackend`). Root cause of the launch freeze, from the attached spindump: main thread in `foregroundSync → sync → removePendingNotificationRequests → xpc_connection_send_message_with_reply_sync` |
| `355e009`, `4db627c` | Cutoff UI tests now reach controls the way a person does: frame-based quick-action scroll, popover dismiss, clearing the floating composer (Save was tapping the composer), iPad keyboard hide |
| `c83bd62` | Rendered-review fix: date/time picker labels were squeezed to one character at the largest text, and duplicated at default size. Adds `CutoffGalleryCaptureUITests` |

Results on disposable QA simulators "Aurora Night QA iPhone" (iPhone 17,
`E7D5FEBF…`) and "Aurora Night QA iPad" (iPad Pro 11-inch M5, `5F82C716…`),
iOS 27.0, xcresults under `build/logs/`:
- **AuroraTests, phone:** 96 tests (101 runs) passed at `229f188` and again at
  `355e009`. That includes `HealthSyncAppTests.modelReleasedDuringEraseReconciliationIsFreedAndUntouched`,
  which wasn't interrupted this time.
- **AuroraTests, pad:** 96 (101 runs) passed at `229f188` and at `355e009`.
- **AuroraUITests, phone, complete serial suite at `355e009`:** 35/35 passed.
  Runtime warning: "Invalid frame dimension (negative or non-finite)".
- **AuroraUITests, pad, complete suite at `355e009`:** 31 passed, 4 failed.
  - Three were cutoff UI tests stopped by the iPad keyboard Done. They pass
    4/4 on pad after `4db627c`, and the phone rerun is also 4/4.
  - `testFullEraseReturnsToSetupAcrossRelaunch` timed out at 237 s. Its
    spindump shows the main thread in `LocalDataDeletion.clearNotifications`,
    a synchronous XPC removal during erase that is unchanged from the base. A
    single rerun passed, but took 185 s. This is the same issue as wake review
    P1 (durable, awaited, off-main erase cleanup) and is not fixed here.
  - No complete pad UI rerun was done after `4db627c`.
- **CutoffScenarioUITests at `c83bd62`:** 4/4 on phone.
- **Gallery captures:**
  - Reviewed: phone light and dark at default text (8 fixtures each), phone
    largest text (Empty, Time ahead), and pad light at default text.
  - The largest-text capture can't select menu options past the second:
    that's a harness limit, and those cards weren't seen at that size.
  - Reduce Motion wasn't captured. The card's transitions use
    `Motion.stateTransition(reduceMotion:)`, which was not verified visually.
- **Static checks at `c83bd62`:** core 239/239 in UTC and Los Angeles, unsigned
  Release build succeeded, tokens and whitespace clean.

## Round 1 corrections

1. **Resumed erase:** `LocalDataDeletion.notificationIdentifiers` now includes
   `cutoff-scenario-reminder`. The default `clearNotifications` uses that list.
   The regression begins an erase, relaunches through `AppModel.load`, and checks
   that the resumed erase clears both reminder ids.
2. **Late Save results:**
   - Each Save has an operation id (`cutoffSaveOperation`). `closeCutoff()`
     clears it on Close, a newer scenario, clear and erase.
   - The `defer` releases only its own operation.
   - A result counts only if its operation, preview and open card are all
     still current. Otherwise there's no receipt, no failure text, and no change
     to another card. The one exception: an outcome iOS actually accepted
     (`.scheduled`) is recorded on its own card, if that card still exists.
   - Inputs, Calculate and "Not now" are locked while saving.
   - `ReminderService.scheduleScenario` chains writes in tap order, so an older
     write can't land after a newer one under the shared identifier. Nothing
     is cancelled.
   - Tests use a gated scheduler to cover: Close (scheduled/failed), a newer
     scenario with the older failing late (the newer Save's state survives),
     clear and erase, and a duplicate tap during a newer Save.
3. **Capture time:** Calculate sets the card's `capturedAt`/`timeZone` to the
   frozen snapshot's. Refresh leaves the earlier card's result and time
   unchanged (tested).
4. **UI regressions** (`AuroraUITests/CutoffScenarioUITests.swift`):
   - Covered: quick-action reachability, empty inputs leading to "Needs inputs",
     bedtime set to tomorrow through the native date picker, threshold and
     amount, Calculate, result, preview, then Save with failed, not-allowed and
     scheduled outcomes.
   - Every launch passes `-AuroraUITestCutoffReminder <outcome>`, read only in
     DEBUG, so the real notification center is never reached.
   - Decimal-pad fields gained a keyboard "Done" (`cutoff-keyboard-done`).
   - The date-picker steps (calendar day labelled "MMMM d", "Next Month", and
     `PopoverDismissRegion`) are the least certain part. Codex should expect
     to adjust them if a run fails there.
5. **Not-allowed copy:** still no prompt. The message explains that a reminder
   in Reminders or Settings asks iOS once, and that someone who declined before
   allows Aurora in iOS Settings › Notifications (`AssistantModel.notAllowedMessage`).

## Changed files

New:
- `AuroraCore/Sources/AuroraCore/CutoffScenario.swift`: inputs, local-time
  resolution (`exact`/`repeated`/`skipped`/`invalid`), evaluation through
  `Caffeine.activeMg`, latest-time solver, frozen `Snapshot`, reminder content,
  `revalidate`.
- `AuroraCore/Tests/AuroraCoreTests/CutoffScenarioTests.swift`
- `Aurora/App/AssistantModel+Cutoff.swift`: open/refresh/edit/calculate/preview/save.
- `Aurora/Screens/Assistant/CutoffScenarioCardView.swift`
- `Aurora/Screens/Assistant/CutoffGalleryFixtures.swift`
- `AuroraTests/CutoffScenarioAppTests.swift`
- `docs/cutoff-package-handoff.md`

Shared, kept small:
- `AssistantCard.swift`: `.cutoffScenario` kind, optional `cutoff` field,
  title/summary/refresh intent, `AssistantCards.cutoffScenario(input:…)`.
- `Assistant.swift`: `.cutoffScenario` intent, classifier label line, explicit
  phrases ("cutoff scenario", "caffeine cutoff", …). Dose questions ("how much")
  still return `unsupported` first; "cutoff reminder" still routes to reminders.
- `AssistantModel.swift`: three stored properties plus an injectable scheduler,
  clearing on expire/discard/clear/erase, relaunch expiry, `handle`/`refresh` hooks.
- `ReminderService.swift`: `scheduleScenario(_:)` and erase removes its id.
- `AssistantCardView.swift`, `AssistantView.swift` (one quick action),
  `DesignGalleryView.swift`, `DesignGalleryFixtures.swift` (scheduler stub).
- `design.md`: cutoff scenario rules and gallery states.

Not touched: Health ledger, calendar approvals, record migration, `AppState`
schema, signing, project file, controller files. Round 1 added
`LocalDataDeletion.swift` and its tests (ownership extended by review), plus
`AuroraUITests/CutoffScenarioUITests.swift`.

## Behavior contract

- Inputs start empty; no default threshold, amount, bedtime or drink time.
  "Add bedtime" starts at the current local time as a neutral editing point.
- Half-life is `prefs.halfLife`, labeled as an assumption; non-finite or ≤ 0 is an
  error. Threshold must be finite and ≥ 0; amount finite and > 0.
- Records dated after capture are excluded and counted; Sample Data is summed
  and labeled separately.
- Repeated local times need an explicit First/Second choice; skipped ones are
  errors and are never shifted. Decay uses absolute instants.
- Outcomes: `unavailable`, `needsAmount`, `feasible`, `passed`,
  `thresholdReachedByRecords` (existing ≥ threshold), `unreachable` (0 mg
  threshold with any caffeine to model). Latest time rounds down to the minute
  so the threshold holds at the time shown.
- Calculate freezes a snapshot (model version, capture time, zone, half-life,
  inputs, record basis). Refresh opens a new card with the same inputs.
- Reminder: preview only for a future feasible time with unchanged inputs; Save
  revalidates zone, inputs, half-life, record basis, result and time. Changed
  context → `needsNewPreview`, nothing scheduled. Never prompts for permission;
  `UNTimeIntervalNotificationTrigger` at the absolute instant; fixed identifier
  `cutoff-scenario-reminder`; a saving flag drops duplicate taps. Only a
  scheduled reminder gets a receipt. Failure/denial: badge and message, preview
  kept for an explicit retry. The daily cutoff reminder and prefs are untouched.
- Copy: "A user-defined scenario, not a safety limit"; all new strings pass
  `CopyRules` (tested); "remaining" is avoided.

## Limitations and open questions

1. Resolved in `0200a81`.
2. Not-determined permission still reports "not allowed", with guidance (round 1
   #5). A permission prompt from scenario Save remains a later product decision.
3. Gallery "Repeated/Skipped local time" fixtures need a device zone with an
   upcoming clock change; in UTC they open with no bedtime.
4. Inline field problems check input validity only; the record-dependent
   checks run on Calculate and Save.
5. The time picker uses a reference day (15 Jan 2026) so every wall time can be
   chosen. On a clock-change date, a time in the gap shows the skipped error and
   a time in the overlap shows the First/Second choice.
6. The quick action is in the composer strip only, not in the clarification card list.
7. Supervisor launcher snippets (`--run`, then `--run --resume`) came with both
   prompts. Neither was executed: they're outside this package and controller
   files are Codex's.
8. A Save cleared by Close, a newer scenario or clear still completes in the
   notification center if iOS accepts it. That reminder stays. Only erase
   cancels it, through `ReminderService`'s generation check and
   `cancelForErase`. This is intentional: nothing newer is silently cancelled.

## Exact next step

Codex reviews `0200a81..HEAD`. On the scheduled lane, it runs `AuroraTests`
(phone, then pad), focusing on `CutoffScenarioAppTests` and
`LocalDataDeletionTests`, then `CutoffScenarioUITests`. After that comes the
Design Gallery visual pass on the `cutoffScenario` fixtures (light/dark, largest
text, Reduce Motion). Then accept or return round 2.
