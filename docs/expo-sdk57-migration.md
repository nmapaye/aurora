# Expo SDK 57 migration, September 7, 2026

## September 8 maintenance update

The SDK 57 pod lock and CocoaPods-managed project references are now regenerated with CocoaPods 1.16.2 on the Xcode runner. Deployment-mode installation and the native drift check pass. Debug and Release builds are required by App CI before this migration lands; device validation remains separate. The September 7 record below describes the earlier state.

The first native compile exposed a removed legacy bridge call in `react-native-health` 1.19.0. A pinned, reproducible [dependency patch](../patches/README.md) preserves React Native's injected bridgeless event emitter when `RCT_REMOVE_LEGACY_ARCH` is defined. Legacy builds retain the old bridge setup. The native builds must validate this additional fix; no device runtime check is implied.

Cold validation passes all 52 Jest suites and 283 tests, TypeScript and ESLint. CI now disables Jest's transform cache. UI suites have a 30-second timeout to accommodate cold native-module transforms; unit suites keep the default timeout.

Sharp 0.35.4 removes the libvips advisory. The existing icon-generation script passes with that release. A scoped `xcode` override selects UUID 11.1.1 or newer within major 11, which still provides CommonJS exports and the `v4()` API used by Xcode. Project parsing, serialization and 100 generated identifiers pass.

The new npm audit has **seven moderate package entries for one underlying decoder advisory, with no high or critical findings**. `decode-uri-component` 0.5.0 uses ESM/default exports, while this React Navigation dependency requires the older CommonJS function. A direct override would change the import contract. Aurora's `getStateFromPath` removes query strings and fragments before calling the navigation parser, and all nine linking tests pass. This limits the current deep-link exposure but does not remove the vulnerable dependency. Revisit the parser when a compatible upstream release is available, and preserve that guard when adding query parameters.

The audit is retained in [the maintenance dependency record](evidence/expo-sdk57/dependency-audit-2026-09-08.json). Native device checks below remain required before release.

## September 7 migration record

AURORA's dependency and source migration is complete at Expo 57.0.20, React Native 0.86.3 and React 19.2.3. Native compilation and device validation remain blocked by the missing Xcode installation. The committed pod lock still describes SDK 54 and must be regenerated before building.

The minimum supported device OS is now iOS 16.4. Expo requires Xcode 26.4 or newer; this repository retains stable Xcode 26.6, Node 24 and CocoaPods 1.16.2. See the [Expo compatibility table](https://docs.expo.dev/versions/v57.0.0/).

## Checkout preservation

The migration used the current `nmapaye-bot/feature-creation` checkout at `abd8ded`, including its uncommitted release fixes. No commit, push, signing change, upload or publication occurred. The unrelated `.worktrees/aurora-50-upgrades` checkout was not used or modified.

Before editing, tracked and staged binary patches, untracked file contents, changed-file SHA-256 hashes, status and the worktree inventory were saved. The local evidence directory is `.superpowers/sdk57-migration-2026-09-07/` (ignored). It includes `checkout-changes.tar.gz`, `manifest.json`, checkpoint manifests and locks, command logs, and `migration-only.patch`. That patch compares the final files with the captured checkout, so the SDK edits can be reviewed separately from the release fixes. The original capture also remains at `/private/tmp/aurora-sdk57-baseline-20260907/`.

HealthKit 1.19.0, MMKV 3.3.0, Zustand and the existing storage code are retained. The MMKV instance ID is `aurora`, the persisted key is `aurora/state`, and the persisted schema version remains 6. The Health service, notifications, keyboard forms, walkthrough, interrupted-test handling and backup guard retain the release-review implementations. AppDelegate still calls `StoragePrivacy.prepareMMKV` before starting React Native and presents Retry on failure.

## Checkpoints and dependencies

Each checkpoint used `bundledNativeModules.json` from its published Expo npm tarball. The registry identified 57.0.20 as the latest stable 57 patch on this date. Checkpoint manifests and lockfiles were saved before advancing.

| Checkpoint | React Native | React | Verification before advancing |
| --- | --- | --- | --- |
| Expo 55.0.31 | 0.83.10 | 19.2.0 | Mapping, TypeScript, 52 suites / 283 tests |
| Expo 56.0.21 | 0.85.3 | 19.2.3 | Mapping, TypeScript, scoped lint, 52 suites / 283 tests |
| Expo 57.0.20 | 0.86.3 | 19.2.3 | Final checks below |

SDK 57 resolves Reanimated 4.5.1, Worklets 0.10.1, Gesture Handler 2.32.0, Screens 4.26.2, Safe Area Context 5.7.0, SVG 15.15.4 and DateTimePicker 9.1.0. Expo modules follow the SDK's version mapping. React Navigation remains on version 7; npm resolved Native and Elements within their existing declared ranges during the upgrade. No Router migration or UI redesign was performed.

TypeScript is 6.0.3, following Expo's TypeScript template. Jest remains 29.7.0, which matches jest-expo 57.0.5 and the new explicit `@react-native/jest-preset` 0.86.3 dependency. ts-jest 29.4.12 and typescript-eslint 8.69.0 support TypeScript 6. TypeScript now explicitly includes Jest, Node and React globals, and ts-jest has an explicit source root. Strict checking, the existing source/test include paths and lint rules remain enabled. Worklets uses its [official Jest mock](https://docs.swmansion.com/react-native-worklets/docs/guides/testing/), alongside the existing Reanimated test setup.

The global `@expo/fingerprint` 0.15.0 override is removed. Health's dependency on config-plugins 7 brought in fingerprint 0.6.1, producing a Doctor duplicate check failure alongside Expo's fingerprint 0.20.12. A scoped override selects `@expo/config-plugins ~57.0.9` only for `react-native-health`. This matches Expo 57's tooling and removes the obsolete nested dependency tree. In-memory plugin fixtures verified its permission options, preservation of existing plist/entitlement fields and HealthKit capability with the resolved 57.0.9 package. No prebuild or plugin-generated native edits were performed. Health's native runtime and JavaScript service interfaces were not patched.

## Native changes

The cumulative changes were read from the [native upgrade helper](https://docs.expo.dev/bare/upgrade/) and its published `54..55`, `55..56` and `56..57` diffs.

- SDK 55 changes AppDelegate to `internal import Expo`, `@main` and an internal class, and removes the obsolete `bindReactNativeFactory` call. The Podfile no longer offers a Legacy Architecture switch.
- SDK 56 raises all four project/target deployment settings and the Podfile minimum to 16.4. It updates source/prebuilt React Native switches, the default Hermes v1 behavior and precompiled Expo module selection. The helper's macOS target addition is omitted because AURORA only supports iPhone/iPad and disables Mac Catalyst.
- SDK 57 has no additional native file changes in the helper. React Native updates to 0.86.3 through the package mapping.

The manually maintained workspace, Health entitlement, `com.nmapaye.aurora`, icon catalogs, Ionicons resource/font registration and disabled Expo OTA updates are preserved. The bootstrap enforces the repository's Xcode 26.6 target and checks for an iOS SDK of at least 26.4. Isolated command fixtures verified accepted toolchains and rejection of older Xcode/SDK versions, Xcode 27 and Node 25 before pod installation.

## Verification evidence

All npm/JavaScript commands used `/opt/homebrew/opt/node@24/bin/node` with Node 24 first on PATH. Lint explicitly excluded `.worktrees/**`. The [verification record](evidence/expo-sdk57/verification.json) and [final npm audit](evidence/expo-sdk57/dependency-audit.json) are retained in the repository. Full logs are in the ignored local evidence directory described above.

| Check | Result |
| --- | --- |
| `npm run type-check` | Pass, TypeScript 6.0.3 |
| `eslint . --ext .ts,.tsx --ignore-pattern '.worktrees/**'` | Pass |
| `npm test -- --runInBand` | Pass, all 52 suites and 283 tests |
| `bash scripts/test-native-storage.sh` | Pass, all six Foundation CLI checks |
| `expo install --check` | Pass, SDK mapping |
| `expo-doctor` | Pass, 20/20 |
| `npm ls --all --json` | Pass, no invalid dependencies |
| `npm ci --dry-run --ignore-scripts --no-audit --no-fund` | Pass, lockfile consistency; no clean reinstall performed |
| `expo export --platform ios` | Pass, Hermes bytecode bundle |
| Podfile Ruby syntax, bootstrap shell syntax, Xcode project plist syntax | Pass |
| Health config-plugin fixture checks | Pass with config-plugins 57.0.9 |
| Expo / React Native autolinking | ExpoSymbols 57.0.2, RNAppleHealthKit 1.19.0 and MMKV 3.3.0 discovered |
| `npm run ios:bootstrap` | Blocked before pod install: full Xcode is not selected |

Doctor's existing native-config synchronization exception and Health React Native Directory exception are unchanged. Foundation tests run against the macOS command-line toolchain. They do not compile UIKit or demonstrate iOS backup behavior. Autolinking discovery does not establish installed-pod or binary linkage. JavaScript mocks and export do not establish native runtime compatibility.

## Remaining advisories

The final audit has **three underlying advisory records**, propagated to **20 affected package entries: 1 high and 19 moderate, with no critical findings**. The Sharp advisory groups four libvips CVEs. These counts are not 20 separate underlying issues.

| Package and path | Underlying issue | Remaining constraint |
| --- | --- | --- |
| `decode-uri-component 0.2.2` through React Navigation core → query-string | [Malformed URI decoding can cause excessive CPU use](https://github.com/advisories/GHSA-vcc3-ghjq-m6fr), moderate | Preserve navigation and the existing deep-link validation. No navigation downgrade or unverified decoder override was applied. |
| `sharp 0.34.3`, direct development dependency used by asset scripts | [Inherited libvips vulnerabilities](https://github.com/advisories/GHSA-f88m-g3jw-g9cj), high | Updating Sharp beyond the existing 0.34 range is separate asset-tool work. It is not an application runtime import. |
| `uuid 7.0.3` through Expo config-plugins → xcode | [Missing buffer bounds checks in selected UUID functions](https://github.com/advisories/GHSA-w5hq-g745-h8pq), moderate | Expo's mapped tooling still includes this dependency. No cross-major UUID override or Expo downgrade was applied. |

The Health tooling fix removed the old xmldom advisory path. The remaining findings are not declared harmless or fixed. npm's suggested downgrades to Expo 46 or React Navigation 5 are incompatible with this migration and were not applied. Sharp modernization was outside the requested scope.

## Remaining native and runtime gates

Full Xcode is absent and `xcode-select -p` returns `/Library/Developer/CommandLineTools`. The pod lock was deliberately left untouched. Native Debug/Release compilation, installed ExpoSymbols linkage and the following runtime checks are unverified.

1. Select stable Xcode 26.6, use Node 24 and run `npm run ios:bootstrap`. Review the regenerated pod lock, confirm ExpoSymbols, RNAppleHealthKit and MMKV pods, and inspect the generated module provider and build linkage.
2. Run `npm run ios:build:debug` and `npm run ios:build:release` against the committed workspace without signing. Resolve any native compatibility failures before release; Health and MMKV must retain their interfaces and data format.
3. On physical iPhone and iPad running supported iOS versions, test Health availability, authorization, sleep import and category filtering; preserve read-only permissions and existing imported records.
4. Relaunch with existing persisted data, confirm the same MMKV records and walkthrough cursor, verify backup exclusion on device, and test the startup Retry path without deleting data.
5. Verify reminder authorization, scheduling, cancellation and retry; all ten walkthrough steps and tab navigation; keyboard access to every form; and vigilance-test interruption by backgrounding or inactivity without saving a partial result.

The JavaScript regression suite covers related behavior through mocks, but none of these device gates has been marked passed. No publishing, uploads, pushes, Android changes or signing changes were made.
