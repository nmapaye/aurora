# Native access review

Scope: features 46–50. Independent React Native and Swift source fix-reviews passed. Native SDK compilation and physical acceptance remain unverified.

## Implemented behavior

Small and medium Home Screen widgets read a timestamped App Group snapshot. Lock Screen variants hide personal values by default. Snapshots distinguish missing records from confirmed zero intake and expire at the earliest freshness, local midnight, cutoff or bedtime boundary. A timezone change invalidates the snapshot.

The Log Shortcut accepts a saved drink or amount. Its bounded native inbox hands requests to a durable JavaScript queue. Requests wait for hydration, onboarding, walkthrough completion and navigation readiness. An editable confirmation screen shows the dose preview before saving and preserves the existing Log draft. The Status Shortcut returns fresh local values or an explicit unavailable/stale result. Neither intent writes intake history.

The nap Live Activity follows the persisted timer and opens Aurora for finish confirmation. Serialized activity changes ensure reset ends an in-flight start. All-data deletion clears the shared snapshot, inbox and queued actions. Expo Go shows the integration as unavailable.

The manually maintained Xcode project contains the widget target, extension embedding, App Group entitlements and shared sources. Expo autolinking discovers the local AuroraNative module. No prebuild was run.

## Findings resolved and tested

- React Native 0.81's URL implementation does not parse custom-scheme host/path fields like Node's implementation. A failing test using the actual React Native URL class led to a strict custom-scheme parser with malformed and duplicate parameter rejection.
- OpenURLIntent does not support this custom-scheme routing and requires newer API availability. The Log intent now opens the app and writes an atomic inbox request for the app to confirm.
- The inline accessory widget now uses a single Text view.
- Shortcut confirmation includes the same dose-effect preview and visible ten-second Undo behavior as normal logging, including consecutive queued requests.
- Failed durable queue writes cannot acknowledge or lose native requests. Relaunch and retry tests cover this boundary.
- Snapshot freshness covers scheduled checkpoints and timezone changes. Snapshot cache clearing permits republishing, and failed writes remain retryable.
- Legacy version-one backups without native preferences restore with Lock Screen exposure disabled. Persistence migration includes the new preference.

Independent tests cover confirmation/cancellation, walkthrough gating, reset, nap actions, draft preservation, sample exclusion, missing versus zero, malformed URLs, snapshot freshness, durable handoff failures and native bridge ordering. The Foundation Swift test checks snapshot decoding and freshness without importing an iOS framework.

## Verification boundary

The final app gate passed Node 24 type-check, lint, Jest, the New York timezone gate, Expo iOS export, and website type-check/build. A subsequent full Jest run includes the last two bridge review tests and passed 97 suites / 478 tests. One timezone-specific test is skipped in the default timezone and covered by the separate 39-test New York gate. Raw output is retained in `../evidence/final-app-gates.txt` and `../evidence/native-jest.txt`.

`bash scripts/verify-native-source.sh` passed Swift syntax parsing, the compiled Foundation snapshot regression, plist/project validation and podspec syntax. These checks do not establish iOS SDK type correctness, extension linking, signing, rendering or runtime behavior.

Native bootstrap and unsigned Debug/Release build attempts failed at the toolchain prerequisite. The selected developer directory is `/Library/Developer/CommandLineTools`; full Xcode is unavailable. Exact output is retained in the native-bootstrap, native-debug and native-release evidence files.

## Required acceptance before goal completion

1. Install/select stable Xcode 26.6 with the iOS 26 SDK, then run `npm run ios:bootstrap` under Node 24. Open only `ios/AURORA.xcworkspace` and resolve any SDK compilation or linking findings.
2. Pass both unsigned simulator builds using `bash scripts/verify-upgrades.sh --native`.
3. Configure the application and widget signing profiles with `group.com.nmapaye.aurora.shared` and test on physical iPhone and iPad.
4. Verify Home Screen and Lock Screen variants, missing/zero/stale/timezone states, privacy changes and reset. Confirm widget links reach Aurora.
5. Exercise saved-drink and amount Shortcuts during cold start, onboarding, interrupted walkthrough and an existing draft. Confirm nothing logs before approval, cancellation preserves records, and Undo works for queued requests. Verify fresh/stale Status results.
6. Exercise nap start, relaunch, cancel, finish confirmation, reset and unsupported-device states. Confirm the activity ends and no sleep is inferred automatically.
7. Check every new screen on compact iPhone and wide iPad, large Dynamic Type, VoiceOver focus restoration and Reduce Motion. Verify system backup sharing/picking and notification denial, delivery, quiet hours and rescheduling on devices.

These acceptance steps remain pending. Source implementation and review do not satisfy the complete goal without them.
