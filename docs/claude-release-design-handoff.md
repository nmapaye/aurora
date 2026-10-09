# Claude: Aurora premium release design

## Assignment

Preserve existing cards and trust boundaries. Improve native design and interactions
using `design.md`, the shared Swift theme, and the synthetic Debug Design Gallery.
Read `agents.md`, `PRODUCT.md`, `CLAUDE.md`, and the installed iOS guidance first.

Start with caffeine logging → editable review → saved receipt → Undo. Make the
hierarchy, field alignment, units, source labels, action states and transition feel
coherent in light/dark and large text. Do not invent record values or change Save,
Undo, validation, snapshot or approval behavior. Keep animation interruptible and
optional under Reduce Motion. Preserve the gentle Aurora processing rim and palette.

Then refine other existing response experiences and secondary screens against the
same tokens. Use purposeful expansion/selection/receipt motion, not the same entrance
on every card or distracting motion around readable evidence. Keep iPad max-width
layout and system sheets/date pickers. Update the guide when introducing a token.

## Ownership and execution

Use only the assigned isolated worktree on `claude/aurora-premium-release`.
Allowed edits: `Aurora/Theme`, `Aurora/Screens/Assistant/AssistantCardView.swift`,
`DesignGalleryView.swift`, visual components, and this handoff's design evidence.
Do not edit AppModel, AssistantModel, services, AuroraCore, erasure SettingsView,
tests, CI, signing, metadata, original checkouts, or agent/tool configuration.
Coordinate any interface changes with Codex. No cloud, keys, account permissions,
pushes, calendar writes, or real record deletion. Do not run simulator tests while
Codex holds the test lane. Codex will build and capture the combined result.

Deliver coherent small commits or reviewed file changes, explain what changed and
why, list unverified items, and provide a final handoff. If no screenshot tool is
available, state that honestly and request Codex's capture pass; never claim visual
QA from code review alone. Current baseline screenshots in the conversation are
references, not proof of your final implementation.

## Handoff: pass 1 (2026-10-08)

Status: **uncommitted, unbuilt, unscreenshotted.** This session had file read/edit
tools only. It had no shell, so no `xcodebuild`, simulator, `git commit`, or
screenshots. Codex: please build, run the capture pass, and commit if it holds.

### Changed files

- `Aurora/Theme/DesignTokens.swift`: `Typography.label/value/heroValue`;
  `Motion.press`, `Motion.stateChange(reduceMotion:)`, `Motion.stateTransition(reduceMotion:)`.
- `Aurora/Theme/Palette.swift`: `StatusTone.symbol`.
- `Aurora/Components/AppScreen.swift`: the secondary button now has a disabled
  state, both button styles animate press opacity, and there are new `StatusBadge`
  and `LabeledField` components.
- `Aurora/Screens/Assistant/AssistantCardView.swift`: caffeine/sleep editors use
  labeled fields with an inline `mg` unit, a "Manual · local time" source line,
  and stacked Save/Discard. Drafts have a state badge. Card state changes are
  animated in place, receipt rows use label/value alignment, and a removed entry
  is struck through. History rows show a chevron for editable rows only. Literal
  spacing has been replaced with tokens.
- `Aurora/Screens/Assistant/DesignGalleryView.swift`: a "Live" state (now the
  default) so Save → receipt → Undo runs in the disposable fixture. It renders
  the whole experience sequence, a receipt fixture with a synthetic sample row, a
  token strip (badges, enabled/disabled buttons, a labeled field) and the fixture
  failure text. The default experience is now `caffeineDraft`.
- `design.md`: documents the new tokens, components, and motion rules.

### Behavior intentionally unchanged

Save, Undo, Discard, Refresh/New review, the sheets, and the edit/delete guards
all call the same model methods. Accessibility identifiers are unchanged. Caffeine
Save stays enabled with an empty amount, so `assistant-error` still appears (UI
test line 56). Sleep Save is disabled exactly as before. The receipt summary
(including "Removed that caffeine entry") still renders.

### One visible addition to review

The caffeine editor now shows `CaffeineLog.validate` text inline once the amount is
non-empty and invalid. It is display only and reads the same validator Save calls.
Revert the `fieldProblem` call in `caffeineEditor` if that is out of scope.

### Unverified: needs Codex build and capture

1. It has not been compiled. The risks are the `DatePicker(selection:in:label:)`
   trailing-closure overloads, `let` inside the receipt `ForEach` builder, and
   `.strikethrough` on a non-Text view (iOS 16+ API).
2. Light/dark mode, AX5 large text (badge/title stacking, metric row stacking),
   iPad width, VoiceOver order of the badge versus the title, and Reduce Motion
   (expect instant state swaps).
3. Draft → saved transition smoothness, and that interrupting it (tap Undo
   mid-animation) does not glitch.
4. UI tests `testCaffeineNeedsReviewAndUndoRemovesOnlySavedEntry` and the
   sleep save test.

### Out of scope, flagged for Codex

- `AssistantView.swift:43` caps the conversation at 720 pt, but `design.md` says
  600 pt. I left it because the file is not in my allowed list.
- Receipt times use the device time zone (`Date.formatted`), not the card's
  snapshot zone, unlike the "Captured" line. I kept this to avoid changing
  snapshot behavior.
