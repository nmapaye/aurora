# AURORA 
Another Unwise Refill? O.K, Reconsider Alertness

Current Scope
	•	iOS-first MVP with HealthKit-backed sleep import, manual caffeine logging, and an on-device vigilance reaction test
	•	Onboarding currently supports sleep target setup, Health app connection, or manual-only mode
	•	Android health integration, cloud sync, encrypted import/export, and background automation are not part of the current release branch

Setup Tutorial

Requirements
	•	Node.js 24.x+ and npm 11.6+ (or pnpm/yarn)
	•	macOS with Xcode 16.4+ and CocoaPods 1.16.2+ for iOS builds
	•	Android Studio 2025+ with SDK 54 and JDK 24 for Android builds
	•	Expo CLI and EAS CLI (highly recommended)

npm i -g expo eas-cli

1) Clone and install

git clone https://github.com/nmapaye/aurora
cd aurora
npm install

2) Initialize local environment

# Verify environment
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


Website demo
	•	Start the standalone showcase site

npm run site:dev


	•	Build the static demo for GitHub Pages

npm run site:build

Gumroad + TestFlight demo
	•	Use Gumroad as the access and documentation package: release notes, setup steps, beta notes, feedback path, and the TestFlight invite.
	•	Use TestFlight for iOS app delivery to iPhone testers; do not distribute a raw IPA as the product file.
	•	Configure website release links with VITE_AURORA_GUMROAD_URL and VITE_AURORA_TESTFLIGHT_URL only after the real Gumroad product and TestFlight public invite exist.
	•	See docs/demo-release.md for the exact local release checks, configurable link variables, demo package contents, and physical iPhone/TestFlight smoke checklist.



4) App permissions
	•	iOS Health: enable permissions on first launch via the system prompt or Settings → Health → Data Access.
Ensure the Info.plist includes NSHealthShareUsageDescription and NSHealthUpdateUsageDescription.
	•	Notifications (if enabled later): include NSUserNotificationUsageDescription.

5) Sample data
	•	Use Quick Add to create doses if Health data is not connected.
	•	Run the 60-second vigilance reaction test from the Dashboard to create an attentiveness baseline even without Health data.
	•	Insights and sleep-aware guidance improve once Health sleep sessions are imported.

6) Build for testers (EAS)

eas login
eas build:configure

# iOS
eas build -p ios --profile preview

# Android
eas build -p android --profile preview

Troubleshooting

# Clear Metro cache
npx expo start -c

# Reset iOS pods
rm -rf ios/Pods ios/Podfile.lock && npx pod-install

# Reset watchman (macOS)
watchman watch-del-all || true

# Verify Xcode and Java paths
xcode-select -p
/usr/libexec/java_home -V

	•	On Expo SDK upgrades or native plugin changes, regenerate native projects (see “Native Sync” below).

Native Sync (Prebuild) 

This repo commits ios/ and android/ folders. When native folders exist, Expo/EAS will not automatically sync native config from app.json on build. After changing any native-related fields in app.json (e.g., icon, splash, ios, android, plugins), re-generate native projects locally and commit the changes.

Scripts
	•	npm run sync:native — runs expo prebuild --no-install to apply config changes without reinstalling node modules.
	•	npm run sync:native:clean — runs expo prebuild --clean to fully regenerate native projects (use when changing icons/splash or after major SDK upgrades).

Typical flow
	1.	Edit app.json (icons, splash, plugins, etc.).
	2.	Run npm run sync:native.
	3.	Review and commit changes under ios/ and android/.
	4.	Build locally or with EAS.
