# September 7 release review

AURORA remains unpublished. These local changes prepare the first release for owner review; they do not establish native runtime or submission readiness.

Implemented fixes cover Health bridge inclusion and availability, sleep-category filtering, honest Health request/import states, visible temporary-storage fallback, unsupported deep-link suffixes, reminder serialization and retry, interrupted vigilance cancellation, sample-data preservation, and keyboard-accessible entry sheets.

Native startup now prepares Documents/mmkv, sets its backup-exclusion resource flag and verifies readback before React Native opens storage. Failure presents a native Retry screen and preserves existing records. Run `bash scripts/test-native-storage.sh` for the six Foundation CLI regressions. This test does not establish iOS backup behavior or compile UIKit.

Full Xcode is absent on the inspected machine, and the selected developer directory is CommandLineTools. No valid signing identity was found. Native Debug/Release builds, simulator and physical-device tests, screenshots, a signed archive and App Store Connect verification remain blocked. The inspected pod lock lacks ExpoSymbols. Run the supported bootstrap and review native dependency changes after selecting Xcode; never use prebuild.

Old imported Health records lack category provenance. The fix filters future reads but deliberately preserves existing records rather than guessing which records should be removed. MMKV has no app-configured encryption key. Final backup, SDK-manifest, runtime traffic, rights and Apple declaration checks remain open.

Release drafts and final command evidence are in the local review package at `/Users/nmapaye/Documents/Codex/2026-08-25/reall/outputs/aurora-release-review`. Begin with its MORNING_REPORT.md and SUBMISSION_CHECKLIST.md. No commit, push, upload, publication or tester invitation occurred in this review.

Before the SDK migration, host verification passed 52 Jest suites/283 tests, six Foundation CLI checks, TypeScript, lint scoped to exclude unrelated .worktrees/**, Expo iOS export, and showcase site typecheck/build. Expo Doctor passed 17/17 with the existing native-config synchronization check disabled. SDK 54 patches and compatible transitive updates removed the critical audit finding; 29 affected nodes remained across six advisory packages (11 high, 18 moderate). That evidence is retained in the earlier review package.

The subsequent SDK 55 → 56 → 57 migration ends at Expo 57.0.20, React Native 0.86.3 and React 19.2.3. The app now requires iOS 16.4. Node 24 and stable Xcode 26.6 remain the repository targets; Expo's minimum Xcode version is 26.4. The current migration passes 52 suites/283 tests, six Foundation checks, TypeScript 6, scoped lint, Expo Doctor 20/20, dependency mapping, lockfile validation and the iOS JavaScript export. Existing Doctor exceptions remain unchanged. The website was not changed or revalidated during this migration.

The final audit reports 20 affected packages (1 high, 19 moderate), arising from three underlying advisories in decode-uri-component, sharp/libvips and uuid. No clean audit claim is made. The old fingerprint override is removed; a Health-scoped config-plugins override resolves its outdated Expo tooling without changing HealthKit runtime code. Health and MMKV versions, service interfaces, the MMKV identifier, persisted schema and backup guard are preserved.

The pod lock remains the pre-migration SDK 54 lock because full Xcode is unavailable. ExpoSymbols is found by SDK 57 autolinking, but installed-pod and binary linkage are unverified. Pod regeneration through bootstrap, unsigned Debug/Release builds and iPhone/iPad runtime checks remain blocked. JavaScript and Foundation results do not establish native readiness. See [SDK 57 migration notes](expo-sdk57-migration.md) for the checkpoint evidence, advisory paths and remaining validation matrix.
