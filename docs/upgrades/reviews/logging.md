# Logging batch review

Scope: approved features 1–10. Implementation and independent state/UI fix-reviews passed. Device acceptance and the scheduled-bedtime integration remain pending.

## State and domain review

Independent reviewer: `logging_state_review`.

- Sample records affected personal Insights and overrode confirmed caffeine-free days. Dose and vigilance selectors now exclude sample IDs. Tests cover mixed records, selected export records, and confirmed zero intake.
- Persisted drafts accepted finite timestamps outside the JavaScript Date range. Normalization and draft validation now require a finite numeric timestamp and a representable date.
- Follow-up review caught Date coercion accepting null, booleans, and date strings. Four hydration cases reproduced the failure before the finite-number guard was restored.
- Reviewer confirmed both findings resolved. Root rerun passed 13 tests in the two independent regression suites.

Evidence: `tests/state/store.logging.review.spec.ts`, `tests/features/insights/sampleSeparation.spec.ts`. Includes successful undo of addition/deletion, zero-marker restoration, moving a dose across days, concurrent record preservation, malformed hydration, and incomplete form text preservation.

## UI review

Independent reviewer: `logging_ui_review`.

Resolved fix/re-review items:

- The ten-second Undo notice could be offscreen. Move it into each screen’s fixed bottom overlay and test placement.
- Resuming an edited draft between History and Log could lose note/time changes. Use the complete canonical draft for preview and save without overwriting saved fields when reopening.
- Add user-flow coverage for library editing/archiving/restoration, shared favorite order, zero-day controls, and the multi-screen draft path.

Root added `tests/ui/DrinkLibrary.review.spec.tsx`. Its two tests pass for edit/archive/restore without changing built-in presets, and favorite reorder followed by persistence rehydration.

## Verification

Final logging batch gate: 55 suites / 287 tests passed with Node 24 pinned on PATH; type-check, lint, and git diff whitespace checks passed. Root iOS Expo export passed with 1647 modules. Full Jest output is retained in ../evidence/logging-jest.txt. UI reviewer confirmed no remaining material findings after fixes.

Feature 10 still uses the temporary 22:30 projection helper. Features 11–20 must replace it with the shared weekly schedule before final acceptance.

Physical iPhone/iPad, VoiceOver, large-text and native validation remain required at whole-branch delivery.
