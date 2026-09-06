# Planning batch review

Scope: features 21–30, plus the Sleep Routines navigation dispatch correction found during integration. Implementation and independent domain/UI fix-reviews passed. Physical device acceptance remains pending.

## Review findings

- An accidental insertion in the existing drink save action referenced an undefined persistence variable. The insertion was removed. Independent regression coverage now saves a valid personal drink and verifies that plans remain intact.
- Switching to a shorter scenario could leave the projection cursor beyond the available points. The visible point was clamped, but the Previous handler used the stale index. A UI regression reproduced repeated taps without movement.
- The chart interpolated from the previous hour to a future dose peak, visually introducing caffeine before intake. A domain regression now requires a point immediately before intake as well as the point at intake.
- Sleep Routines was registered in the root navigator but omitted from the shared standalone-route dispatch. Integration includes a dispatch regression for every standalone route, because earlier screen tests mocked navigation.

The threshold estimate deliberately reports a time at or below the selected level after the last hypothetical dose. This scope is stated in the UI; it does not claim the earliest prior crossing or a safe-to-sleep threshold.

## Independent evidence

The root regression suites cover analytical decay with carryover, relative scenario timing, unchanged recorded intake, DST reduction dates, sample exclusion, confirmed zero versus missing records, all customized planning fields through persistence, and malformed check-in hydration. The domain reviewer passed 48 focused tests and Node 24 type-check after the store correction.

Both chart fixes passed final UI re-review. The cursor handlers now use the clamped index, and the curve includes immediately-before-dose points with explicit event labels in its text alternative.

Final Node 24 gate passed type-check, lint, and 73 Jest suites (371 tests passed, one timezone-specific test skipped). The separate America/New_York gate passed 30 tests including the DST-specific case. Root iOS Expo export passed with 1656 modules. Full Jest output is retained in ../evidence/planning-jest.txt. Diff whitespace and verification-script syntax checks passed. Website checks were unchanged from the passed sleep gate.

Physical device layout, large text, VoiceOver, Reduce Motion, and native build acceptance remain pending.
