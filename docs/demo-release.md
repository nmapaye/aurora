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

## App Store Checklist

- Configure the App Store Connect app record for `com.nmapaye.aurora`.
- Set app pricing in App Store Connect for the paid v0.1.0 release.
- Add the production privacy policy URL: `https://nmapaye.github.io/aurora/privacy.html`.
- Add the production support URL: `https://nmapaye.github.io/aurora/support.html`.
- Keep `eas.json` only as an emergency rollback until the first signed Xcode Organizer archive validates.
- Do not use EAS as the primary release workflow during the Xcode-first migration.
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
- Keep EAS available only as the temporary rollback path described above.
- Start with internal testers, then create an external tester group.
- Use a public TestFlight link only for free beta testing.
- Use `docs/testflight-beta-metadata.md` for App Store Connect beta description, reviewer notes, privacy notes, and known demo limits.

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
- Vigilance test completes and saves a result.
- Insights summary and daily totals CSV can be shared.

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
- Export/share the insights summary or daily totals CSV and confirm the iOS share sheet opens.
- Force quit and reopen Aurora, then confirm saved records and dashboard state still load.

## Manual Physical iPad/TestFlight Smoke Checklist

Run this on a physical iPad or iPad simulator before App Store submission because the Xcode target includes iPhone and iPad device families:

- Launch Aurora from a fresh install and confirm onboarding appears.
- Complete manual-only onboarding and confirm the adaptive layout does not clip or overlap content.
- Visit Home, Log, Sleep, Insights, History, Vigilance, and Settings.
- Confirm Health unavailable/available messaging is clear for the test device.
- Confirm icons, splash, Settings privacy/support links, and share sheet behavior.
- Force quit and reopen Aurora, then confirm saved records and dashboard state still load.

## Smoke Results

Record the release-candidate result before submission:

| Area | Device/build | Result | Notes |
|------|--------------|--------|-------|
| iPhone TestFlight | [insert device + build] | Not run | [insert notes] |
| iPad TestFlight | [insert device + build] | Not run | [insert notes] |
| App Store metadata | App Store Connect | Not run | [insert notes] |
| Gumroad companion guide | Gumroad | Not run | [insert notes] |

## Release Checks

Run these exact local checks from the repo root (`/Users/nmapaye/Documents/Local Coding Projects/aurora`) before sharing an App Store, Gumroad, or TestFlight link:

```sh
npx expo-doctor
npm run type-check
npm run lint
npm test -- --runInBand
npm run site:type-check
npm run site:build
npx expo export --platform ios
```

Finish with the physical iPhone and iPad TestFlight smoke checklists above.
