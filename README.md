# Aurora

Another Unwise Refill? O.K, Reconsider Alertness.

Aurora is an iPhone and iPad app for understanding how caffeine timing, sleep,
and alertness fit together. It supports optional read-only Apple Health sleep
import, manual caffeine logging, a 60-second reaction test, and private
on-device insights.

Aurora does not include cloud sync, an Apple Watch companion app, encrypted
import/export, or background automation.

## Requirements

- macOS with stable Xcode 26.6 or 27.x. Never use a beta Xcode for release
  work.
- iOS 17 or later on the device or simulator.

Nothing else is needed to build the app. Node.js 24 is only used for the
website and the icon script.

## Develop in Xcode

```sh
git clone https://github.com/nmapaye/aurora
cd aurora
open Aurora.xcodeproj
```

Select the shared `Aurora` scheme and an iPhone or iPad destination, then Run.
HealthKit needs a signed build: set your team under Signing & Capabilities.
Unsigned builds can't reach HealthKit, so Health access reads as not set up.

## Project layout

- `AuroraCore/` is a Swift package with every rule that doesn't need UIKit:
  the records and their validation, the alertness, caffeine, and sleep
  models, what each screen says, CSV export, Sample Data, and the import of
  data left by the old React Native build. It builds and tests on macOS and
  Linux.
- `Aurora/` is the SwiftUI app. `App/` holds the model, router, and tabs;
  `Services/` holds storage, HealthKit, reminders, and haptics; `Screens/`
  has one folder per screen.
- `AuroraTests/` and `AuroraUITests/` are the app's unit and UI tests.

The Xcode project uses folder-synchronized groups, so files added under these
folders join their target without editing the project file.

## Data

State is one JSON file in Application Support, excluded from device backups.
The app checks that exclusion before reading anything and shows a recovery
screen if it can't confirm it.

On first launch, Aurora imports records left by the React Native build
(`Documents/mmkv/aurora`) and then removes that store. If the old store can't
be read, it is left in place untouched.

## App permissions

- Apple Health access is optional and read-only (Sleep Analysis only).
- The daily cutoff reminder is a local notification. It needs no push
  entitlement.
- If Health access is unavailable, denied, or empty, manual logging and
  Sample Data still work.

## Checks

```sh
cd AuroraCore && swift test
xcodebuild test -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

CI runs the core tests on Linux and macOS, the app's unit and UI tests on
iPhone and iPad simulators, a Release build, CodeQL, and gitleaks.

## Showcase website

The standalone Vite site in `website/` is independent of the app:

```sh
npm run site:dev
npm run site:type-check
npm run site:build
```

Set `VITE_AURORA_APP_STORE_URL`, `VITE_AURORA_GUMROAD_URL`, and
`VITE_AURORA_TESTFLIGHT_URL` only after the corresponding public links exist.

## App Store and TestFlight

Aurora targets a paid App Store v0.1.0 release, with free TestFlight beta
testing and an optional Gumroad companion guide. TestFlight access must not be
sold, and a raw IPA must not be distributed as the product.

See `docs/demo-release.md` for release checks and device smoke tests. Create
releases with Product → Archive in Xcode, Validate App in Organizer, then
Distribute App → App Store Connect. Increment the build number before every
upload.

## Icons

`npm run icons` regenerates the app icon PNGs in
`Aurora/Assets.xcassets/AppIcon.appiconset` and the source copies in
`assets/`. Review the result in Xcode before committing.
