# Aurora

Another Unwise Refill? O.K, Reconsider Alertness.

Aurora is an iPhone and iPad app for understanding how caffeine timing, sleep,
and alertness fit together. It supports optional read-only Apple Health sleep
import, manual caffeine logging, a 60-second vigilance reaction test, and
private on-device insights.

Aurora does not currently include cloud sync, an Apple Watch companion app,
encrypted import/export, or background automation.

## Requirements

- macOS with stable Xcode 26.6 and the iOS 26.4 SDK or newer. Do not use an Xcode 27 beta
  for release work.
- Node.js 24 and npm 11.6 or newer.
- CocoaPods 1.16.2, matching `ios/Podfile.lock`.

The repository pins its Node major in `.node-version`. The committed Xcode
workspace is authoritative for native configuration, signing, builds,
profiling, and releases.

## Install

```sh
git clone https://github.com/nmapaye/aurora
cd aurora
npm install
npm run ios:bootstrap
```

The bootstrap checks the required tool versions, refreshes the ignored local
Node path used by Xcode, and installs pods without changing native
configuration.

## Develop in Xcode

Start Metro in one terminal:

```sh
npm start
```

Open the CocoaPods workspace:

```sh
npm run ios:open
```

Select the shared `AURORA` scheme and an iPhone or iPad destination, then use
Xcode's Run action. Use Fast Refresh and React Native DevTools for TypeScript,
and Xcode's console, LLDB, and Instruments for native work.

Always open `ios/AURORA.xcworkspace`, never `ios/AURORA.xcodeproj`. Do not run
`expo prebuild`: Aurora's native project is maintained manually and prebuild
can overwrite it. See `docs/xcode-development.md` for ownership boundaries and
the full workflow.

## App permissions

- Apple Health access is optional and read-only. The native project contains
  `NSHealthShareUsageDescription` and the HealthKit entitlement.
- Daily cutoff reminders are local notifications. They do not require the APNs
  push entitlement.
- If Health access is unavailable, denied, or empty, manual logging and sample
  data remain available.

## Checks

```sh
npm run type-check
npm run lint
npm test -- --runInBand
npx expo export --platform ios
npm run ios:build:debug
npm run ios:build:release
```

The two native build checks require the full supported Xcode installation.

## Showcase website

The standalone Vite site remains independent from the Expo app:

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

See `docs/demo-release.md` for release checks and physical iPhone/iPad smoke
tests. Create releases with Product → Archive in Xcode, Validate App in
Organizer, then Distribute App → App Store Connect. Increment Xcode's build
number before every upload.

The existing EAS configuration remains only as a temporary emergency rollback
until the first signed Organizer archive validates. It uses Xcode's local
version values and is not a second supported release workflow.

## Icons and launch assets

Run `node scripts/make-icons.mjs` to regenerate the source icon and splash
files. Because Xcode owns the native asset catalog, review and update
`ios/AURORA/Images.xcassets` explicitly; never use prebuild to synchronize it.

## Troubleshooting

Clear Metro's cache:

```sh
npm start -- --clear
```

Refresh the local Node path and pods:

```sh
npm run ios:bootstrap
```

Confirm the active developer directory:

```sh
xcode-select -p
```
