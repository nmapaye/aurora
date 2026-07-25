# Aurora — Agent Handoff

Last updated: 2026-07-25 (branch `codex/health-style-secondary-pages`)

## What this is

Aurora is an iPhone and iPad app built with Expo SDK 54, React Native 0.81,
React 19, and TypeScript. It tracks caffeine intake against sleep and
alertness through optional read-only HealthKit sleep import, manual dose
logging, a 60-second vigilance reaction test, and the pure alertness model in
`src/domain/algorithm/`. State uses Zustand with MMKV persistence in
`src/state/store.ts`. A standalone Vite showcase site lives in `website/`.

The target is a paid App Store v0.1.0 release, free TestFlight beta testing,
and an optional Gumroad companion guide/support package.

## Active feature handoff

The current effort is the Apple Health-style rebuild of Sleep, Log, and
Insights plus a one-time ten-step walkthrough across Summary, Sleep, Log, and
Insights.

- Isolated worktree:
  `.worktrees/health-style-secondary-pages`
- Branch: `codex/health-style-secondary-pages`
- Main baseline: `2d523bbb`
- Approved design:
  `docs/superpowers/specs/2026-07-24-health-style-secondary-pages-design.md`
- Execution plan:
  `docs/superpowers/plans/2026-07-24-health-style-secondary-pages.md`
- Subagent ledger and review artifacts:
  `.superpowers/sdd/` (ignored)

Do not modify the dirty primary checkout or `.worktrees/main-merge`; their
unrelated/generated changes belong to the user.

### Progress

1. Foundation complete and reviewed through `2b63d99`: `expo-symbols`,
   `AppSymbol`, shared Health-style components, and the exact shared presets
   Espresso 60 mg, Drip 95 mg, Matcha 70 mg, Energy 160 mg.
2. Walkthrough state/model complete and reviewed through `d15e4c1`: persisted
   version 5, ten exact steps, legacy Summary completion migration, cursor
   clamping, and tab-gating helpers. The old Summary-only controller remains
   intentionally until integration task 6.
3. Sleep complete and reviewed through `8bc49de`: W/M 7-/30-day presentation,
   30-day read-only Health refresh, honest Health states, manual Add/Edit/Delete
   with notes and `manual:sleep:` IDs, `SleepHistory`, caffeine-impact
   baseline, DST-safe calendar days, native date/time controls, accessibility,
   and compact/wide coverage. The Task 3 gate passed 36 suites / 164 tests.
4. Log redesign is currently in progress from `8bc49de` with the fresh
   `task4_log_redesign` subagent. It owns the shared preset integration,
   Today/Quick Add/Recent/Add Details hierarchy, custom-entry sheet,
   confirmation behavior, and `CaffeineHistory`.
5. Remaining sequential gates: review/fix Log; implement/review Insights and
   history; integrate/review the ten-step walkthrough and accessibility; then
   final whole-branch review and full delivery verification.

Each implementation task uses a fresh subagent, strict red-green-refactor TDD,
an independent specification/code-quality review, and fix/re-review loops
before the next task begins. Keep implementation tasks sequential because they
share navigation, screens, and tests.

### Current feature constraints

- Keep everything React Native and Expo Go-previewable; do not add `@expo/ui`
  or a SwiftUI bridge.
- Keep HealthKit read-only. Add no analytics, telemetry, or synthetic
  walkthrough data.
- Manual sleep alone is editable/deletable; Health and Sample Data remain
  labeled and read-only.
- The walkthrough has exactly ten steps: Summary 1–4, Sleep 5–6, Log 7–8,
  Insights 9–10. Skip completes globally; Finish appears only at step 10.
- Disable data-changing controls during the walkthrough. Resume the persisted
  step after relaunch and honor Reduce Motion and VoiceOver.
- W/M Sleep means 7/30 days. W/2W/M Insights means 7/14/30 days and defaults
  to 2W.
- Track shared `HealthFormSheet` trigger-focus restoration for task 6's
  cross-screen accessibility pass.

### Local command note

The default shell may select Node 25, but the repository requires Node 24.
Run npm commands with:

```bash
/opt/homebrew/opt/node@24/bin/node \
  /opt/homebrew/opt/node@24/lib/node_modules/npm/bin/npm-cli.js <command>
```

## Native development model

The committed `ios/AURORA.xcworkspace` is authoritative for native
configuration, signing, builds, profiling, and releases. Aurora maintains only
the iPhone and iPad application.

- Run `npm run ios:bootstrap` after cloning or changing native dependencies.
- Start Metro with `npm start`.
- Open the workspace with `npm run ios:open` and run the shared `AURORA`
  scheme in Xcode.
- Never open the `.xcodeproj` directly.
- Never run `expo prebuild`; it can overwrite the manually owned project.
- Use `npm run ios:build:debug` and `npm run ios:build:release` for unsigned
  simulator build gates.

See `docs/xcode-development.md` for exact ownership boundaries.

## Routine checks

- `npm run type-check`
- `npm run lint`
- `npm test -- --runInBand`
- `npx expo export --platform ios`
- `npm run site:type-check`
- `npm run site:build`

The last reviewed feature checkpoint (`8bc49de`) covered 36 suites and 164
tests. Native build checks require stable Xcode 26.6 with the iOS 26 SDK; do
not use Xcode 27 beta for release work.

## Landmines and repository knowledge

1. **The Xcode project is manually owned.** Native changes belong in the
   project file, shared scheme, plists, entitlements, asset catalogs,
   storyboard, AppDelegate, and Podfile. Review SDK migrations as dedicated
   native diffs.
2. **Persistence has a guard.** Any new persisted field must be added to
   `normalizePersistedState` in `src/state/store.ts` and to the fixture in
   `tests/state/store.persistence.spec.ts`.
3. **The historical SSH-key alert was false.** The removed file only contained
   the text `REMOVED`; full-history scanning confirmed no private key was
   committed.
4. **Validate after conflict resolution.** A previous GitHub UI merge broke
   JSX on `main`; always type-check and test the resolved branch.
5. **Do not bypass FortiGate TLS errors.** If a network re-signs GitHub
   traffic, wait for a clean network or let the repository owner decide.
6. **Ionicons is embedded natively.** If glyphs render blank, inspect
   `UIAppFonts` in `ios/AURORA/Info.plist` and the Xcode Copy Bundle Resources
   phase. Do not add runtime `loadAsync` calls.
7. **Jest mocks native modules** in `tests/setup.ts`. Keep testable behavior in
   pure modules where possible.

## Icons and brand

- Mark source: `website/public/aurora-mark.svg`.
- Brand navy: `#0B1020`; accent: `#0A84FF`.
- `scripts/make-icons.mjs` regenerates source/store icon variants and the
  splash source.
- Xcode owns `ios/AURORA/Images.xcassets`; update and review the catalog
  explicitly after regenerating source files.

## Remaining release work

1. Install and select stable Xcode 26.6, switch the local shell to Node 24,
   and run `npm run ios:bootstrap`.
2. Configure the Apple Developer team and App Store Connect record for
   `com.nmapaye.aurora`.
3. Pass unsigned Debug and Release simulator builds plus physical iPhone/iPad
   smoke tests.
4. Create and validate a signed archive in Xcode Organizer, then distribute an
   internal TestFlight build.
5. Remove the temporary `eas.json` rollback path only after that Organizer
   archive validates.
6. Fill the real website and metadata link placeholders after the public
   App Store/TestFlight destinations exist.
