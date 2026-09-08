# Xcode Development

Aurora is an iPhone and iPad React Native application with a manually owned
native iOS project. Xcode is the authoritative environment for native
configuration, builds, debugging, profiling, signing, and archives. Expo
continues to provide the JavaScript runtime, Metro, and native modules.

## Requirements

- Stable Xcode 26.6 with the iOS 26.4 SDK or newer. Expo SDK 57 requires
  Xcode 26.4 or newer; the bootstrap retains the 26.6 release target. Do not
  use an Xcode 27 beta for release work.
- Node.js 24 and npm 11.6 or newer.
- CocoaPods 1.16.2, matching `ios/Podfile.lock`.

Run the bootstrap after cloning, changing Node installations, or changing a
native dependency:

```sh
npm run ios:bootstrap
```

The bootstrap validates the toolchain, writes the ignored
`ios/.xcode.env.local` with the active Node binary, and installs pods.

## Daily Workflow

Start Metro in one terminal:

```sh
npm start
```

Open the CocoaPods workspace:

```sh
npm run ios
```

In Xcode, select the shared `AURORA` scheme and a simulator or registered
device, then Run. Use React Native DevTools and Fast Refresh for TypeScript;
use Xcode's console, LLDB, and Instruments for native behavior.

Never open `ios/AURORA.xcodeproj` directly. It does not include the CocoaPods
workspace dependencies.

## Native Ownership

The following files are edited and reviewed directly:

- `ios/AURORA.xcodeproj/project.pbxproj` and the shared scheme.
- `ios/AURORA/Info.plist`, `AURORA/Supporting/Expo.plist`,
  `AURORA.entitlements`, and `PrivacyInfo.xcprivacy`.
- App icons, launch assets, `AppDelegate.swift`, the Podfile, and
  `Podfile.properties.json`.
- `ios/Podfile.lock`, after a deliberate dependency change.

Machine-local files remain untracked: `.xcode.env.local`, `xcuserdata`,
DerivedData, certificates, provisioning profiles, and simulator data.

Do not run `expo prebuild`. It can replace the manually maintained Xcode
project, plist values, capabilities, resources, and schemes. Expo SDK upgrades
must use the native-project upgrade helper and a reviewed Xcode diff.

After adding or removing an npm package with native iOS code, run:

```sh
npm install
npm run ios:pods
```

Future Swift bridges should be local Expo modules under `modules/` and linked
through CocoaPods. Do not place reusable feature logic in `AppDelegate.swift`.

## Build Checks

Unsigned simulator builds are available from the repository root:

```sh
npm run ios:build:debug
npm run ios:build:release
```

The deployment target is iOS 16.4, and the app targets both iPhone and
iPad. Do not accept Xcode's complete “recommended settings” migration as one
bulk change; review each proposed setting after both build configurations are
green.

## Signing and Versions

The bundle identifier is `com.nmapaye.aurora`. Select the Apple Developer team
that owns that identifier and use automatic signing for device and archive
builds. Simulator builds do not require a team.

Xcode owns release numbering:

- Marketing version: `0.1.0`
- Build number: `1`, incremented before every App Store Connect upload

The App Store Connect record and a valid Apple Developer team are prerequisites
for Organizer validation and upload.

## Archive and Distribute

Xcode Organizer is the canonical release path:

1. Run the complete release checks in `docs/demo-release.md`.
2. In the `AURORA` target, confirm `Version` is the intended marketing version
   and increment `Build` before every upload. `Info.plist` reads these values
   from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
3. Select the shared `AURORA` scheme and a generic iOS device destination, then
   choose Product → Archive.
4. In Organizer, choose Validate App and resolve every signing, entitlement,
   privacy, or metadata error.
5. Choose Distribute App → App Store Connect and upload the validated archive.
6. Wait for the build to process, then assign it to the internal TestFlight
   group before expanding beta access.

Before distribution, inspect the signed archive and confirm:

- Bundle identifier `com.nmapaye.aurora`.
- HealthKit entitlement is present and no APNs entitlement is present.
- `PrivacyInfo.xcprivacy`, Ionicons, icon appearances, and launch assets are
  embedded.
- The marketing version targets the intended App Store version, and the build
  number is unused and greater than every prior upload for that version.

Signing certificates, provisioning profiles, the Apple Developer team, and the
App Store Connect record are external prerequisites. If any is unavailable,
simulator and CI work may land, but Organizer upload remains blocked.

`eas.json` is retained only as an emergency rollback while the first signed
Organizer archive is unverified. It uses local version values and must not
override Xcode's build number. Delete `eas.json` and all EAS release
instructions immediately after the first signed Organizer archive validates.
Internal TestFlight processing remains a separate release gate.
