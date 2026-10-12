# Xcode Development

Aurora is a native SwiftUI app for iPhone and iPad. `Aurora.xcodeproj` is the
only project. It builds the `Aurora` app target on top of the local
`AuroraCore` Swift package.

## Requirements

- Stable Xcode 26.6 or 27.x. Never use a beta Xcode for release work.
- Deployment target iOS 17.0, iPhone and iPad.

## Daily Workflow

```sh
open Aurora.xcodeproj
```

Select the shared `Aurora` scheme and a simulator or registered device, then
Run. SwiftUI previews work for any screen that gets an `AppModel` and a
`Router` in its environment.

Logic that doesn't need UIKit belongs in `AuroraCore`, where `swift test` runs
it in seconds on macOS or Linux:

```sh
cd AuroraCore
swift test
```

## Project Structure

The project uses folder-synchronized groups (project format 77). Every file
under `Aurora/`, `AuroraTests/` and `AuroraUITests/` belongs to its folder's
target automatically, so adding a Swift file needs no project change. Two
files in `Aurora/` are excluded from the app's resources in the project file:
`Info.plist` and `Aurora.entitlements`.

These are edited and reviewed directly:

- `Aurora.xcodeproj/project.pbxproj` and the shared `Aurora` scheme.
- `Aurora/Info.plist`: URL schemes `aurora` and `com.nmapaye.aurora`, the
  HealthKit usage strings, and the launch screen color. The build also
  generates keys from `INFOPLIST_KEY_*` settings.
- `Aurora/Aurora.entitlements`: HealthKit only, with no APNs.
- `Aurora/PrivacyInfo.xcprivacy`: no tracking, no collected data, and no
  required-reason APIs.
- `Aurora/Assets.xcassets`: the app icon (light, dark and tinted), the accent
  color, and the launch background.

Machine-local files stay untracked: `xcuserdata`, DerivedData, `.swiftpm`,
certificates and provisioning profiles.

## Build Checks

```sh
xcodebuild test -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild build -project Aurora.xcodeproj -scheme Aurora -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

The iOS App workflow runs the tests on an iPhone and an iPad simulator, and a
Release build. Don't accept Xcode's "recommended settings" migration as one
bulk change; review each setting after both configurations are green.

## Signing and Versions

The bundle identifier is `com.nmapaye.aurora`, the same as the React Native
build, so the new app reads that build's container and imports its records.
Select the Apple Developer team that owns the identifier and use automatic
signing for device and archive builds. Simulator builds don't need a team, but
HealthKit only works in a signed build.

Xcode owns release numbering:

- Marketing version: `0.1.0`
- Build number: `1`, incremented before every App Store Connect upload

## Archive and Distribute

Xcode Organizer is the release path:

1. Run the release checks in `docs/demo-release.md`.
2. In the `Aurora` target, confirm `Version` and increment `Build`.
3. Select the `Aurora` scheme and a generic iOS device, then Product →
   Archive.
4. In Organizer, choose Validate App and resolve every signing, entitlement,
   privacy or metadata error.
5. Choose Distribute App → App Store Connect and upload.
6. Once the build has processed, assign it to the internal TestFlight group
   before expanding beta access.

Before distribution, inspect the signed archive:

- Bundle identifier `com.nmapaye.aurora`.
- HealthKit entitlement present, no APNs entitlement.
- `PrivacyInfo.xcprivacy` and all three icon appearances embedded.
- The build number is unused and greater than every earlier upload for that
  version.

Signing certificates, provisioning profiles, the Apple Developer team and the
App Store Connect record are external prerequisites. Without them, simulator
and CI work can land, but Organizer upload stays blocked.
