# Aurora

Another Unwise Refill? O.K, Reconsider Alertness.

Aurora is an iPhone and iPad app for understanding how caffeine timing, sleep,
and alertness fit together. It supports optional read-only Apple Health sleep
import, manual caffeine logging, a 60-second vigilance reaction test, and
private on-device insights.

Aurora does not currently include cloud sync, an Apple Watch companion app,
encrypted import/export, or background automation.

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

- macOS with stable Xcode 26.6 or newer. Never use a beta Xcode for release
  work.
- iOS 17 or newer on the device or simulator.
- Node.js 24 only for the website.

## Develop

Open `Aurora.xcodeproj`, select the shared `Aurora` scheme and an iPhone or
iPad destination, then use Xcode's Run action.

Run the logic tests without Xcode:

```sh
cd AuroraCore
swift test
```

## App permissions

- Apple Health access is optional and read-only. The target has the HealthKit
  entitlement and `NSHealthShareUsageDescription`.
- Daily cutoff reminders are local notifications. They do not require the APNs
  push entitlement.
- If Health access is unavailable, denied, or empty, manual logging and sample
  data remain available.

## Checks

CI runs on every pull request: the app's build, unit and UI tests on iPhone
and iPad simulators, a Release build, the AuroraCore tests on macOS and Linux,
CodeQL, and a secret scan. `docs/demo-release.md` lists the local commands
and the device checks to run before a release.

## Showcase website

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

Create releases with Product → Archive in Xcode, Validate App in Organizer,
then Distribute App → App Store Connect. Increment the build number before
every upload. TestFlight access must not be sold, and a raw IPA must not be
distributed as the product. See `docs/demo-release.md` for the release
checklist and physical iPhone and iPad smoke tests.
