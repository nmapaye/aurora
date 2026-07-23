# Aurora — Agent Handoff

Last updated: 2026-07-23 (branch `codex/xcode-first-ios`)

## What this is

Aurora is an iPhone and iPad app built with Expo SDK 54, React Native 0.81,
React 19, and TypeScript. It tracks caffeine intake against sleep and
alertness through optional read-only HealthKit sleep import, manual dose
logging, a 60-second vigilance reaction test, and the pure alertness model in
`src/domain/algorithm/`. State uses Zustand with MMKV persistence in
`src/state/store.ts`. A standalone Vite showcase site lives in `website/`.

The target is a paid App Store v0.1.0 release, free TestFlight beta testing,
and an optional Gumroad companion guide/support package.

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

The JavaScript checks currently cover 15 suites and 47 tests. Native build
checks require stable Xcode 26 with the iOS 26 SDK.

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

1. Install and select stable Xcode 26, switch the local shell to Node 24, and
   run `npm run ios:bootstrap`.
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
