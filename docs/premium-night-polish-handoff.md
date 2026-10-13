# Premium night package 3: interaction and gallery polish — 2026-10-10

Branch `claude/aurora-polish-night-2026-10-10`, worktree
`/Users/nmapaye/Developer/aurora-polish-night-2026-10-10`, base accepted `5be6ded`.
Claude, isolated. Provisional until Codex reviews and runs the native/UI lane. Local
commits only. No pushes, installs, simulator runs, resets, signing or account changes.
Controller state/task in `/Users/nmapaye/Developer/aurora-night-2026-10-10` was not
read or edited (outside this session's allowed directories). Codex should update it.

## Commits

| Commit | Kind | Content |
|---|---|---|
| `69842e2` | interaction | Composer column, Stop in composer, quick-action press style, new-reply reveal/hold |
| `94ec4bc` | motion | Rim fade starts from the last frame |
| `b7b2fb4` | interaction | Check-in description shown once |
| `50ec451` | interaction | Setup's current question keeps its start visible at largest text |
| `c4762ed` | gallery | Fixtures and device-state isolation |
| `83ce853` | tests | Native + UI regressions |
| (this) | docs | `design.md`, this handoff |

## Findings addressed

1. **iPad composer spans the window** (Codex capture `683A3A61…png`, inspected here: cards
   in a centered ~600 pt column, composer edge to edge). Hint and composer now use the
   conversation column (`contentMaxWidth`, centered, `Metrics.lg` inset, same as the message
   list). The quick-action strip still scrolls full width, but its content margin
   (`Metrics.columnInset(containerWidth:)`, derived only from those existing tokens) puts the
   first action in line with the column. On iPhone the composer moves from 12 pt to 20 pt
   insets so it lines up with cards there too. Save/keyboard behavior from package 1 is
   unchanged (collapsing inset, keyboard spacer).
2. **Stop reachability.** Stop moved from the processing row in the transcript into the
   composer: Send becomes Stop (`assistant-stop`) the moment `processing` is true, and back
   when it ends. It is reachable while earlier messages are read. The processing row keeps
   the activity ribbon and status text. `AssistantModel.cancel()` is unchanged.
3. **Long cards inserted at their end.** Previously every count change scrolled to the
   bottom anchor, which showed a long card's last control. `ConversationReveal` (pure,
   tested) decides:
   - opening the conversation, or the person's own message → end (as before);
   - a new reply when the previous last message or the end was on screen → scroll to the
     reply's **top** (clamps to the end if it fits);
   - otherwise (reading earlier messages) → no scroll; a "New message below" capsule
     (`assistant-new-below`, announced once) scrolls to the reply's start when tapped and
     clears when the end or that reply comes on screen.
   Visibility uses `onGeometryChange` against the scroll view's named space. Chart
   selection, snapshots and dates are untouched: cards are not rebuilt, only scrolled.
4. **Rim fade.** `frozenPhase` was updated in `onChange` after the inactive render, so the
   fade started from a stale frame and jumped. The inactive branch now draws the frame at
   render time. Stop/failure/completion still set `processing = false` immediately; the rim
   fades 0.70 s with no timeline; Reduce Motion is one static frame; inactive scenes stop.
5. **Duplicate check-in sentence** (verification doc line 463). It isn't in
   `EnergyCardViews`. The card summary (`EnergyCheckIn.kindLabel`) and the open editor both
   showed it, in `AssistantCardView`. The summary is skipped only while the editor is open
   with the same sentence. Corrections keep their summary and closed cards keep it once.
   `EnergyCardViews` is not changed.
6. **Largest-text Health setup prompt cropped at top.** Setup scrolled the transcript end
   to the bottom, so a question taller than the space above the panel lost its first lines.
   It now scrolls to the current question's top (`anchor: .top`, which clamps to the end
   when it fits), and the scroll view has `safeAreaPadding(.top, Metrics.xl)` equal to the
   fade so the first line isn't faded. Text sizes, panel cap, skips and controls are
   unchanged.
7. **Quick action feedback.** A capsule style with `Motion.press` opacity, a card border
   and a visible disabled color (previously `.plain`).

`AssistantModel` change: only `healthMetric` split into a static `healthMetric(_:)` that
the instance method calls. Rows are identical. No typed action, planning, calculation,
storage, Health, calendar or approval code changed. AuroraCore is untouched.

## Gallery

- `GalleryFixture`: temp folder, `GalleryHealth` (no capabilities, refuses before
  HealthKit), `CalendarService(providers: [])` with a **private defaults suite**. The
  existing gallery used `UserDefaults.standard`, so selecting a fixture calendar could change
  the app's real selection. Fixed.
- **Reminders card** in the gallery is now disabled with a note. Its switches call the real
  `UNUserNotificationCenter`, which can prompt and also removes or reschedules the real
  cutoff reminder. `ReminderService` isn't injectable, so disabling was the bounded option.
- Setup fixture (`gallery-setup`): starts at Name, Health or Finish. "Saves fail" turns the
  fixture's `state.json` into a folder, so the **real** `setup-save-failure` shows and the
  question stays. Switch to "Saves work" and the same Continue succeeds. Calendar buttons
  are disabled through the new `SetupConversationView.connectionsEnabled` (default `true`).
- Welcome fixtures: recorded sleep (synthetic manual), Sample Data, no records. They auto-end
  after 1.2 s like the real welcome; use `-AuroraWelcomeHold` to hold.
- Cards: "Earlier snapshot (3 hours ago)" for non-energy kinds. Receipt Apple Health row:
  pending, not exported, added, unconfirmed, using `HealthExportStatus` copy.
- Processing light: rest, working, stopped, failed, plus a static toggle. The Reduce Motion
  environment value isn't writable, so `AuroraEdgeGlow`/`AuroraActivity` gained
  `allowsMotion` (default `true`).
- Requested states and their coverage: populated/missing/sample/stale (energy variants +
  earlier snapshots), expired/loading/failed (interaction picker), pending (receipt Health
  row), failure (setup save, energy failure, Health not exported). **Denied** is covered
  only by the refusing Health provider in the Health sheet and setup. No stored
  declined-permission setup state is fabricated.

## Checks actually run (this worktree)

| Check | Result |
|---|---|
| Core `swift test` TZ=UTC (`--scratch-path build/core`) | 216/216 passed |
| Core `swift test` TZ=America/Los_Angeles | 216/216 passed |
| `build-for-testing`, generic iOS Simulator, `CODE_SIGN_IDENTITY=-`, `build/dd` | TEST BUILD SUCCEEDED (app, AuroraTests incl. `ConversationPolishTests`, AuroraUITests) |
| Unsigned Release, `CODE_SIGNING_ALLOWED=NO`, `build/dd-release` | BUILD SUCCEEDED; only the standard AppIntents metadata warning |
| `python3 -I scripts/check-design-tokens.py` | passed |
| `git diff --check 5be6ded HEAD` | clean |

Screenshots: only Codex's iPad capture was inspected. I produced none.

**Not run** (Codex's lane): native AuroraTests, all UI tests, any install/launch, visual,
VoiceOver, Reduce Motion, iPad, physical device. I make no runtime claim.

## New checks (compiled, not run)

- Native `ConversationPolishTests`: reveal start/hold/end/none; `columnInset` equals the list
  column; receipt Health rows match `HealthExportStatus`; fixture save failure keeps the step
  and retry advances; fixture calendar toggle leaves standard defaults unchanged; gallery
  Health refuses all three choices.
- UI: `testComposerSharesTheCardColumn`, `testLongCardArrivesShowingItsStart`,
  `testReplyWhileReadingEarlierMessagesKeepsThePlace`,
  `testGallerySetupFixtureShowsSaveErrorThenRetries`,
  `testGalleryMotionFixtureEndsAndStaysStatic`. Each attaches screenshots. Existing tests
  are unchanged.

Runtime-unverified assumptions to watch:
- `assistant-card-<kind>` title queried via `descendants(.any)`. The composer field's
  `minX` equals the title's `minX` only if the Label frame starts at its icon.
- The held-reply test assumes that, at the draft's Save, the last card (energy) is off
  screen. On a tall iPad that may not hold, and the reply would then be revealed (correct
  behavior, failed assertion).
- `onGeometryChange` initial callbacks set visibility (relied on for `endVisible`).
- Segmented gallery pickers are tapped by segment title. The static toggle is tapped at its
  trailing edge.
- Existing tests: Stop moved out of the transcript (no test used it). New cards anchor at
  their top, so tests that waited for elements near a card's end may need the swipes they
  already have.

## Unresolved gates

Full serial phone/pad suites on the combined build; light/dark/largest-text/Reduce Motion
visuals of composer, capsule, setup Health at AX5 and gallery fixtures; VoiceOver order and
the "New message below" announcement; physical-device keyboard, motion, battery; live
Health/calendar; signing; TestFlight. Blank cold launch remains as recorded in package 1.

## Next steps for Codex

1. Review commits individually (interaction `69842e2`, `94ec4bc`, `b7b2fb4`, `50ec451`;
   gallery `c4762ed`; tests `83ce853`).
2. Run core in both zones, then native (`ConversationPolishTests`), then serial phone/pad UI,
   especially the five new tests, the keyboard Save test and the largest-text tests.
3. Capture the iPad keyboard state again to compare with `683A3A61…png`, plus setup Health
   at AX XXXL, the setup fixture error, and the processing light fixture.
