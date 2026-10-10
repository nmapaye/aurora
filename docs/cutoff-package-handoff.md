# Cutoff scenario package handoff

Date: 2026-10-10. Branch `claude/aurora-cutoff-2026-10-10`, base `56ecb12`.
Status: implemented, awaiting Codex review. Not pushed, not integrated.

## Commits

| Commit | Slice |
|---|---|
| `5061f79` | Deterministic contract and calculations (core + core tests) |
| `8dac176` | Planning flow and one-off `ReminderService` API |
| `f821f5d` | Cutoff card, quick action, gallery fixtures |
| `dbdb2c6` | Native regressions (compiled, not run) |
| final docs commit | `design.md` section, copy fix, this handoff |

The app target doesn't compile at `5061f79` or `8dac176` alone (new enum cases
hit exhaustive switches in the views); it compiles from `f821f5d`. Cherry-pick
the series together.

## Checks actually run by Claude

All with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

- `TZ=UTC swift test --package-path AuroraCore`: **236 tests in 31 suites passed**
  (includes 20 new `CutoffScenarioTests`, parameterized cases inside).
- `TZ=America/Los_Angeles swift test --package-path AuroraCore`: **236 passed**.
- `xcodebuild build-for-testing … -destination 'generic/platform=iOS Simulator'`:
  **TEST BUILD SUCCEEDED**, rerun after the last source edit.
- Unsigned Release build (CI's command, `CODE_SIGNING_ALLOWED=NO`):
  **BUILD SUCCEEDED**. This ran before the final copy-only string edit in
  `AssistantModel+Cutoff.swift`. The test build after that edit passed.
- `scripts/check-design-tokens.py`: passed. `git diff --check 56ecb12`: clean.

**Not run by Claude:** native `AuroraTests` (including the 7 new
`CutoffScenarioAppTests`), UI tests, any simulator launch/install, gallery
visual inspection, VoiceOver/Dynamic Type/Reduce Motion review. No pass is
claimed for any of these.

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
schema, signing, project file, controller files, `LocalDataDeletion.swift`.

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

1. `LocalDataDeletion.clearNotifications` (Codex-owned) doesn't list
   `CutoffScenario.reminderIdentifier`. The normal erase removes it through
   `ReminderService.cancelForErase`. A resumed interrupted erase doesn't.
   Suggested one-line fix: add the id to that list.
2. When notification permission was never asked, Save reports "not allowed".
   Whether a scenario Save may ask for permission is a product decision.
3. Gallery "Repeated/Skipped local time" fixtures need a device zone with an
   upcoming clock change; in UTC they open with no bedtime.
4. Inline field problems check input validity only; the record-dependent
   checks run on Calculate and Save.
5. The time picker uses a reference day (15 Jan 2026) so every wall time can be
   chosen. On a clock-change date, a time in the gap shows the skipped error and
   a time in the overlap shows the First/Second choice.
6. The quick action is in the composer strip only, not in the clarification card list.
7. A `python3 supervisor.py --run` launcher snippet came with the task prompt.
   It was not executed: it's outside this package and controller files are Codex's.

## Exact next step

Codex: review `5061f79..HEAD`, then on the scheduled test lane run
`AuroraTests` (phone, then pad) with focus on `CutoffScenarioAppTests`. Then do a
Design Gallery visual pass on `cutoffScenario` fixtures in light/dark, largest
text and Reduce Motion, and decide items 1–2 above before integration.
