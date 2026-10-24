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
Device and archive builds use automatic signing with the Apple Developer team
that owns the identifier, set in `Config/Signing.xcconfig` (below). Simulator
builds don't need a team, but HealthKit only works in a signed build.

Signing lives in `Config/Signing.xcconfig`, the app target's base
configuration: `DEVELOPMENT_TEAM` and automatic signing. Don't choose a team in
Signing & Capabilities; that writes a target setting that overrides the file.
For a personal override, create the gitignored `Config/Signing.local.xcconfig`
with `DEVELOPMENT_TEAM = <your team>`.

Release numbering:

- Marketing version: `0.1.0`, set in the target.
- Build number: set by the Release workflow as `<run number>.<attempt>`
  (plus the optional `BUILD_NUMBER_OFFSET` variable, a non-negative integer,
  default 0). Local
  archives keep `CURRENT_PROJECT_VERSION = 1` and must not be uploaded.

## Release workflow (TestFlight)

`.github/workflows/release.yml` runs only from `main` on manual dispatch. It
archives with `xcodebuild` using cloud-managed automatic signing and uploads to
App Store Connect. The `release` environment requires the owner's approval and
holds `ASC_KEY_ID`, `ASC_ISSUER_ID` and `ASC_KEY_P8` (base64 of the team API
key's `.p8`, Admin role). Before the first run, set the Team ID in
`Config/Signing.xcconfig` and `Config/ExportOptions.plist`, and create the App
Store Connect app record for `com.nmapaye.aurora`.

Owner setup, before the first dispatch:

1. Create the GitHub environment `release` (Settings → Environments) with
   required reviewer `nmapaye` and deployment branches set to "Selected
   branches" with `main` only. Create it before the first dispatch: a job that
   references a missing environment makes GitHub auto-create it unprotected,
   with no reviewer or branch rule.
2. As the owner, add the environment secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and
   `ASC_KEY_P8`, plus the optional environment variable `BUILD_NUMBER_OFFSET`.
3. Set the Team ID in `Config/Signing.xcconfig` and
   `Config/ExportOptions.plist`, and create the App Store Connect app record.

Re-running an older run after a newer build has been uploaded produces a lower
build number, which App Store Connect rejects. That failure is safe: nothing is
uploaded or replaced. Dispatch a new run instead.

## Archive and Distribute

The Release workflow is the upload path. Use Organizer to validate a local
archive; upload one only if the workflow is unavailable:

1. Run the release checks in `docs/demo-release.md`.
2. In the `Aurora` target, confirm `Version`. For a manual upload, pass a build
   number higher than every workflow upload (for example
   `CURRENT_PROJECT_VERSION=<n>` on an `xcodebuild archive`); never upload the
   default `1`.
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
