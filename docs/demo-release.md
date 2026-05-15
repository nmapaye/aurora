# Aurora Gumroad + TestFlight Demo Release

Aurora demo access should be packaged through Gumroad, while the installed iOS beta is delivered through TestFlight. Do not sell or distribute a raw IPA as the product file.

## Configurable Release Links

Do not hard-code placeholder account URLs into the website. Configure real links only when the Gumroad product and TestFlight public invite are ready:

```sh
VITE_AURORA_GUMROAD_URL="https://gumroad.com/l/your-product-slug"
VITE_AURORA_TESTFLIGHT_URL="https://testflight.apple.com/join/your-invite-code"
```

Until those variables are set, the website intentionally shows setup labels instead of external links.

## Gumroad Product Contents

- TestFlight public link and iPhone install instructions.
- Demo walkthrough: onboarding, Health import, caffeine logging, vigilance test, insights, and export.
- Privacy summary: sample data stays on device unless the user explicitly shares or exports summaries.
- Known limits: iOS-first, HealthKit optional, no medical advice, no cloud sync, no Android health parity.
- Feedback/support link for testers.
- Changelog for the current demo build.

## TestFlight Checklist

- Configure the App Store Connect app record for `com.nmapaye.aurora`.
- Build an iOS preview/release artifact with EAS.
- Upload with EAS Submit or App Store Connect.
- Start with internal testers, then create an external tester group.
- Use a public TestFlight link with a tester cap that matches Gumroad availability.
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

Run this on a physical iPhone from the actual TestFlight build before sharing the Gumroad package:

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

## Release Checks

Run these exact local checks from the repo root (`/Users/nmapaye/Documents/Local Coding Projects/aurora`) before sharing a Gumroad/TestFlight link:

```sh
npx expo-doctor
npm run type-check
npm run lint
npm test -- --runInBand
npm run site:type-check
npm run site:build
```

Finish with the physical iPhone/TestFlight smoke checklist above.
