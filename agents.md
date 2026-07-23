# Aurora — Agent Handoff

Last updated: 2026-07-09 (branch `feat/app-icons`)

## What this is

Aurora is an iOS-first Expo app (SDK 54, RN 0.81, React 19, TypeScript) that
tracks caffeine intake against sleep and alertness: HealthKit sleep import,
manual dose logging, a 60-second vigilance reaction test, and an alertness
model in `src/domain/algorithm/` (pure functions: caffeine pharmacokinetics ×
circadian rhythm × sleep debt × sleep inertia). State is zustand + MMKV
persistence (`src/state/store.ts`). A standalone Vite showcase site lives in
`website/`. Target: paid App Store v0.1.0 release, with free TestFlight beta
testing and an optional Gumroad companion guide/support package.

## Current state: stacked PRs, merge in order

`main` ← #7 ← #8 ← #9 ← #10 ← #11 (each PR is based on the previous branch;
GitHub retargets children as parents merge)

| PR | Branch | What it does |
|----|--------|--------------|
| #7 | `chore/remove-dead-scaffolding` | **Fixes `main` (currently uncompilable** — the PR #6 merge left broken JSX in DashboardScreen/StepSources and bad imports in OnboardingScreen). Also deletes ~24 dead files, adds the persistence round-trip guard test, drops deprecated tsconfig `baseUrl`. |
| #8 | `chore/release-config` | Fills empty EAS profiles (`autoIncrement` + remote appVersionSource for TestFlight build numbers), removes stray `com.example.aurora` URL scheme, documents `VITE_AURORA_*` env vars, bumps expo/expo-font (expo-doctor 17/17). |
| #9 | `ci/secret-scanning` | gitleaks workflow on every push/PR; broader `.gitignore` secret patterns. |
| #10 | `feat/cutoff-notification` | Daily local notification at `prefs.cutoffHour` via expo-notifications; `prefs.notifyCutoff` + Settings toggle. Needs a manual simulator check (`npx pod-install` first — new pod not in Podfile.lock). |
| #11 | `feat/app-icons` | Real app icons (assets were literal placeholders) in the iOS design language: gradient bg + glyph glow, iOS 18 light/dark/tinted variants via `expo.ios.icon`, gradient splash, and native embedding of Ionicons.ttf (in-app glyphs rendered blank without it). |

## Commands

- `npm run type-check` / `npm run lint` / `npm test -- --runInBand` — CI runs
  these on every push (`.github/workflows/app-ci.yml`); all green at handoff
  (15 suites / 47 tests).
- `npx expo export --platform ios` — fast Metro bundle check that the module
  graph is intact (used after deletions).
- `npm run ios` / `npx expo start` — real builds; run `npx pod-install` after
  dependency changes.
- `node scripts/make-icons.mjs` (from repo root) — regenerates all icon/splash
  PNGs from the aurora-wave mark (see Icons below).

## Landmines and repo-specific knowledge

1. **Native dirs are committed.** `ios/` and `android/` do not auto-sync from
   `app.json`. After changing icons/splash/plugins/orientation, run
   `npm run sync:native` (prebuild) and commit the native diffs. README
   "Native Sync" documents this.
2. **Persistence foot-gun (guarded).** The persist `merge` in
   `src/state/store.ts` funnels everything through `normalizePersistedState`,
   which silently resets any persisted key it doesn't know about. Adding a
   persisted field requires extending that function AND the fixture in
   `tests/state/store.persistence.spec.ts` — the test fails loudly if you
   forget (by design; it caught `notifyCutoff` during development).
3. **The "SSH key" incident is a false alarm — don't re-flag it.** The file
   `eval "$(ssh-agent -s)"` that used to sit in the repo root only ever
   contained the 8-byte string `REMOVED` (verified via `git show e01f658:...`
   and a full-history gitleaks scan). No real private key was ever committed;
   no rotation or history purge is needed. Files were deleted in PR #6.
4. **Careless GitHub-UI merges have broken `main` before.** PR #6's conflict
   resolution mixed pre- and post-redesign JSX and didn't compile. After
   merging anything with conflicts, run `npm run type-check` on `main`.
5. **FortiGate TLS interception.** On some networks the user is behind a
   FortiGate that re-signs `*.github.com`; pushes fail with certificate
   errors. Do not disable SSL verification — wait for a clean network or let
   the user decide.
6. **In-app icons need the embedded font.** Ionicons is embedded via the
   `expo-font` config plugin in `app.json` (as of #11). If glyphs ever render
   blank again, check `UIAppFonts` in `ios/AURORA/Info.plist` and
   `android/app/src/main/assets/fonts/` — do not add runtime `loadAsync`
   calls.
7. **Jest mocks native modules** in `tests/setup.ts` (MMKV, react-native,
   expo-modules-core). Keep testable logic in pure modules (see
   `src/services/platform/notificationContent.ts` vs `notifications.ts`).

## Icons / brand

- Source of truth for the mark: `website/public/aurora-mark.svg` (blue
  alertness-wave + dot). Brand navy `#0B1020`, accent `#0A84FF`.
- `scripts/make-icons.mjs` renders: `assets/icon.png` (dark, primary),
  `assets/icons/ios-{light,dark,tinted}.png` (wired via `expo.ios.icon`),
  adaptive icon, and gradient splash. After regenerating, run
  `npm run sync:native` and commit native changes.
- Historical note: before #11 every icon asset was a placeholder (blank navy
  square or the ASCII text `PNG_PLACEHOLDER`).

## Remaining release work (mostly external, owner: nmapaye)

1. Push/land the local `main` merge stack if it is not already on GitHub.
2. Manual device pass: `npx expo run:ios`; check tab-bar glyphs, home-screen
   icon (light/dark/tinted), splash, Settings privacy/support links, and the
   cutoff notification toggle end-to-end.
3. App Store Connect record for `com.nmapaye.aurora` → set `ascAppId` in
   `eas.json` → `eas build -p ios --profile production` → EAS Submit.
4. App Store listing + free TestFlight public invite + optional Gumroad
   companion guide → fill `VITE_AURORA_APP_STORE_URL`,
   `VITE_AURORA_GUMROAD_URL`, and `VITE_AURORA_TESTFLIGHT_URL` (website env)
   and the `[insert ...]` placeholders in `docs/testflight-beta-metadata.md`
   and `docs/app-store-metadata.md`.
5. Physical iPhone and iPad smoke checklists in `docs/demo-release.md`.
