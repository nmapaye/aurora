# Aurora App Store + Free TestFlight Release

Aurora app access should be sold through the App Store. TestFlight is for uncompensated beta testing only. Gumroad may sell a companion guide, setup walkthrough, changelog, support path, and educational material, but it must not unlock the app or gate TestFlight access.

Do not sell TestFlight access and do not distribute a raw IPA as the product file.

## Configurable Release Links

Do not hard-code placeholder account URLs into the website. Configure real links only when the App Store listing, Gumroad companion guide, and free TestFlight public invite are ready:

```sh
VITE_AURORA_APP_STORE_URL="https://apps.apple.com/app/id0000000000"
VITE_AURORA_GUMROAD_URL="https://gumroad.com/l/your-product-slug"
VITE_AURORA_TESTFLIGHT_URL="https://testflight.apple.com/join/your-invite-code"
```

Until those variables are set, the website intentionally shows setup labels instead of external links.

## Canonical Xcode Organizer Workflow

1. Install and select stable Xcode 26.6 or 27.x, then open `Aurora.xcodeproj`.
2. Configure automatic signing on the `Aurora` target with the Apple Developer
   team that owns `com.nmapaye.aurora`.
3. Confirm the marketing version in Xcode and increment the build number before
   every upload.
4. Select the shared `Aurora` scheme and a generic iOS device destination, then
   choose Product → Archive.
5. In Organizer, choose Validate App. Resolve all signing, entitlement,
   privacy, and metadata findings before proceeding.
6. Choose Distribute App → App Store Connect and upload the validated archive.
7. Confirm that the build processes successfully and assign it to internal
   TestFlight testers before creating an external group or public invite.

The Apple Developer team and App Store Connect record are external
prerequisites. Without them, simulator and CI work may pass, but archive
validation and upload remain blocked.

## App Store Checklist

- Configure the App Store Connect app record for `com.nmapaye.aurora`.
- Set app pricing in App Store Connect for the paid v0.1.0 release.
- Add the production privacy policy URL: `https://nmapaye.github.io/aurora/privacy.html`.
- Add the production support URL: `https://nmapaye.github.io/aurora/support.html`.
- Follow the Organizer workflow above; do not use EAS as the normal build or
  upload path.
- Inspect the signed archive for the HealthKit entitlement, absence of an APNs
  entitlement, embedded privacy manifest, Ionicons, launch assets, and all app
  icon appearances.
- Use `docs/app-store-metadata.md` for App Store description, review notes, privacy notes, and known limits.

## Gumroad Companion Guide Contents

- App Store listing link and install instructions.
- Optional free TestFlight beta link, clearly labeled as uncompensated beta testing.
- Product walkthrough: onboarding, Health import, caffeine logging, vigilance test, insights, and export.
- Privacy summary: sample data stays on device unless the user explicitly shares or exports summaries.
- Known limits: iPhone/iPad only, HealthKit optional, no medical advice, no cloud sync, no Apple Watch companion app.
- Feedback/support link for testers.
- Changelog for the current demo build.

## TestFlight Checklist

- Configure the App Store Connect app record for `com.nmapaye.aurora`.
- Upload the validated archive from Xcode Organizer.
- Start with internal testers, then create an external tester group.
- Use a public TestFlight link only for free beta testing.
- Use `docs/testflight-beta-metadata.md` for App Store Connect beta description, reviewer notes, privacy notes, and known demo limits.

## Temporary EAS Rollback

`eas.json` remains only until the first signed Organizer archive validates. It
uses local Xcode version values and must not auto-increment or override the
Xcode build number. After validation passes, delete `eas.json` and every
remaining EAS build/submit instruction in a dedicated cleanup commit. Internal
TestFlight processing remains a separate release gate.

## Smoke Test

- Fresh install opens without crashing and shows onboarding.
- Manual onboarding reaches the dashboard.
- Health permission denied path remains usable.
- Health permission granted path imports or reports recent sleep clearly.
- Refresh sleep updates last sync status and does not duplicate sleep sessions.
- Sample data loads caffeine, sleep, and vigilance records.
- Sample data can be removed without deleting non-demo records.
- Quick Add updates dashboard totals.
- Custom caffeine entry appears in history.
- Custom-entry time selection preserves the chosen time.
- Vigilance test completes and saves a result.
- The three CSV exports in Settings → Data can be shared.
- All four tabs preserve their navigation paths.
- Opening `aurora://summary`, `aurora://sleep`, `aurora://log`,
  `aurora://insights`, `aurora://settings`, `aurora://vigilance`,
  `aurora://sleep/history` and `aurora://caffeine/history` lands on that
  screen. During the walkthrough, each lands on the current step's tab.
- Enabling the daily cutoff reminder schedules a local notification; disabling
  it cancels the reminder without requesting remote-push capability.

## Manual Physical iPhone/TestFlight Smoke Checklist

Run this on a physical iPhone from the actual TestFlight build before sharing the App Store listing or companion guide:

- Install the latest TestFlight build from the public or external tester invite.
- Launch Aurora from a fresh install and confirm onboarding appears.
- Complete the manual-only onboarding path and reach the dashboard.
- Relaunch the app and confirm the selected onboarding path persists.
- Deny Health access and confirm the app remains usable with manual caffeine logging.
- If test Health sleep data is available, grant Health access and confirm sleep import or the empty-state explanation is clear.
- Tap Refresh Sleep and confirm the last sync status updates without duplicating sessions.
- Load sample data and confirm sleep, caffeine, vigilance, insights, and export surfaces populate.
- Remove sample data and confirm non-demo records remain intact.
- Add a quick caffeine dose and confirm the dashboard total changes.
- Add a custom caffeine dose and confirm it appears in history.
- Complete one vigilance test and confirm the result is saved in insights.
- From Settings → Data, export the daily totals CSV and confirm the iOS share sheet opens.
- Enable and disable the daily cutoff reminder and verify local scheduling and
  cancellation.
- Open the registered `aurora://` scheme and confirm Aurora launches without
  crashing.
- Visit every tab and return to the previous stack without losing state.
- Force quit and reopen Aurora, then confirm saved records and dashboard state still load.
- On a device that ran the React Native build, install the Swift build over it
  and confirm every caffeine entry, sleep session, Reaction Test and setting
  carried over.

## Manual Physical iPad/TestFlight Smoke Checklist

Repeat the complete Smoke Test above on a physical iPad using the actual
TestFlight build before App Store submission because the Xcode target includes
iPhone and iPad device families. Then complete these iPad-specific checks:

- Launch Aurora from a fresh install and confirm onboarding appears.
- Complete manual-only onboarding and confirm the adaptive layout does not clip or overlap content.
- Visit Home, Log, Sleep, Insights, History, Vigilance, and Settings.
- Confirm Health unavailable/available messaging is clear for the test device.
- Confirm icons, the launch screen, Settings privacy/support links, and share sheet behavior.
- Force quit and reopen Aurora, then confirm saved records and dashboard state still load.

## Accessibility and Appearance Review

Complete this review on the release candidate:

- Capture Settings, Log, and the tab bar in both light and dark mode.
- Review every affected screen at the largest Dynamic Type accessibility size
  for clipping, overlap, truncation, and unreachable controls.
- Use VoiceOver to verify control labels, selected states, focus order, and
  announcements for buttons, steppers, tabs, and the time picker.
- Repeat interaction checks with Reduce Motion enabled.
- Repeat appearance checks with Reduce Transparency enabled.
- Record any intentional visual differences between iPhone and iPad.

## Smoke Results

Record the release-candidate result before submission:

| Area | Device/build | Result | Notes |
|------|--------------|--------|-------|
| iPhone TestFlight | [insert device + build] | Not run | [insert notes] |
| iPad TestFlight | [insert device + build] | Not run | [insert notes] |
| Signed archive validation | Xcode Organizer | Not run | [insert notes] |
| Internal TestFlight processing | App Store Connect | Not run | [insert notes] |
| App Store metadata | App Store Connect | Not run | [insert notes] |
| Gumroad companion guide | Gumroad | Not run | [insert notes] |

## Release Checks

Run these checks from the repo root before sharing an App Store, Gumroad, or
TestFlight link:

```sh
(cd AuroraCore && swift test)
xcodebuild test -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS Simulator,name=iPhone 17'
xcodebuild test -project Aurora.xcodeproj -scheme Aurora \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M5)'
xcodebuild build -project Aurora.xcodeproj -scheme Aurora -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
npm run site:type-check
npm run site:build
```

Use whichever iPhone and iPad simulators your Xcode lists. Finish with the
physical iPhone/iPad, accessibility, signed-archive, and internal TestFlight
gates above.
