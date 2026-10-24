# Aurora

Another Unwise Refill? O.K, Reconsider Alertness.

Aurora is a native conversational assistant for understanding energy and daily
rhythm on iPhone and iPad. It combines local sleep/caffeine records, modeled
alertness, reaction tests, interactive native cards, and reviewed calendar proposals.
Cards capture dated results; Refresh creates a new snapshot. Logging has inline
review controls, durable receipts, and validated Undo.
AI stays local: Apple Foundation Models on supported devices, with native quick
actions everywhere and an optional local Ollama adapter for simulator testing.

See [the native assistant handoff](docs/native-assistant.md) for implementation,
calendar setup, local evaluation, migration behavior, and remaining release gates.

Aurora does not include cloud sync, an Apple Watch companion app, encrypted
import/export, or cloud AI. Background refresh is opportunistic and opt-in.

## Layout

- `Aurora/` is the SwiftUI app: screens, components, HealthKit, reminders
  and on-device storage.
- `AuroraCore/` is the app's logic as a Swift package with no dependencies
  beyond Foundation: models, the alertness estimate, presentation, sample
  data, CSV export, and the reader for data saved by the earlier React Native
  build. See `AuroraCore/README.md`.
- `AuroraTests/` and `AuroraUITests/` are the app's unit and UI tests.
- `website/` is the standalone Vite showcase site.

The React Native build was removed after commit `0013c38`. Check out that
commit to see it.

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

- Apple Health has three separate opt-ins: read Sleep Analysis, read dietary
  caffeine, and add caffeine saved in Aurora. Imported records are read-only;
  Aurora edits or deletes only samples it wrote. Erase leaves those samples in
  Health.
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
cd website
npm ci
npm run dev
npm run type-check
npm run build
```

Set `VITE_AURORA_APP_STORE_URL`, `VITE_AURORA_GUMROAD_URL`, and
`VITE_AURORA_TESTFLIGHT_URL` only after the corresponding public links exist.

## App Store and TestFlight

Aurora targets a paid App Store v0.1.0 release, with free TestFlight beta
testing and an optional Gumroad companion guide. TestFlight access must not be
sold, and a raw IPA must not be distributed as the product.

See `docs/demo-release.md` for release checks and device smoke tests. Upload
TestFlight builds with the Release (TestFlight) workflow: dispatch it manually
from `main`, and it waits in the `release` environment until the owner
approves. The environment holds the secrets `ASC_KEY_ID`, `ASC_ISSUER_ID` and
`ASC_KEY_P8`; the workflow sets the build number. Setup is in
`docs/xcode-development.md`.

## Icons

`npm run icons` regenerates the app icon PNGs in
`Aurora/Assets.xcassets/AppIcon.appiconset` and the source copies in
`assets/`. Review the result in Xcode before committing.
