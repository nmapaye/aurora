# AURORA

Caffeine + sleep tracker with a computed alertness score

Setup Tutorial

Requirements
	•	Node.js 18+ and npm 10+ (or pnpm/yarn)
	•	macOS with Xcode 15+ and CocoaPods 1.15+ for iOS builds
	•	Android Studio 2024+ with SDK 34 and JDK 17 for Android builds
	•	Expo CLI and EAS CLI (optional but recommended):
npm i -g expo eas-cli

1) Clone and install

git clone <your-repo-url>
cd aurora
npm install

2) Initialize local environment

# verify environment
npx expo-doctor

# iOS pods
npx pod-install

3) Run the app locally
	•	Start Metro

npx expo start

	•	iOS (simulator or device)

npx expo run:ios

	•	Android (emulator or device)

npx expo run:android

4) App permissions
	•	iOS Health: enable permissions on first launch via the system prompt or Settings → Health → Data Access.
Ensure the Info.plist includes NSHealthShareUsageDescription and NSHealthUpdateUsageDescription.
	•	Notifications (if enabled later): include NSUserNotificationUsageDescription.

5) Sample data
	•	Use Quick Add to create doses if Health data is not connected.
	•	Insights will hide sleep correlations until Health data exists.

6) Build for testers (EAS)

eas login
eas build:configure
# iOS
eas build -p ios --profile preview
# Android
eas build -p android --profile preview

Troubleshooting

# clear Metro cache
npx expo start -c

# reset iOS pods
rm -rf ios/Pods ios/Podfile.lock && npx pod-install

# reset watchman (macOS)
watchman watch-del-all || true

# verify Xcode and Java paths
xcode-select -p
/usr/libexec/java_home -V

	•	On Expo SDK upgrades or native plugin changes, regenerate native projects (see “Native Sync” below).

## Native Sync (Prebuild) — Option A

This repo commits `ios/` and `android/` folders. When native folders exist, Expo/EAS will not automatically sync native config from `app.json` on build. After changing any native-related fields in `app.json` (e.g., `icon`, `splash`, `ios`, `android`, `plugins`), re-generate native projects locally and commit the changes.

Scripts:

- `npm run sync:native` — runs `expo prebuild --no-install` to apply config changes without reinstalling node modules.
- `npm run sync:native:clean` — runs `expo prebuild --clean` to fully regenerate native projects (use when changing icons/splash or after major SDK upgrades).

Typical flow:

1. Edit `app.json` (icons, splash, plugins, etc.).
2. Run `npm run sync:native`.
3. Review and commit changes under `ios/` and `android/`.
4. Build locally or with EAS.

Note: If you prefer Config‑Driven builds (no native folders), delete `ios/` and `android/` and let EAS prebuild on the server each build instead.
