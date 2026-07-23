# Aurora TestFlight Beta Metadata Draft

Use this copy when preparing App Store Connect/TestFlight beta review. Replace bracketed values only after the real build and links exist.

## Beta App Description

Aurora is an iPhone and iPad caffeine and sleep guidance app. Testers can log caffeine intake, optionally import recent sleep from Apple Health, run a 60-second vigilance reaction test, and review on-device insights that connect intake timing, sleep windows, and attentiveness.

## What To Test

- Complete onboarding with either HealthKit or manual-only setup.
- Deny Health access and confirm Aurora remains usable with manual caffeine logging.
- Grant Health access, if available, and confirm sleep import or the empty-state explanation is clear.
- Use sample data to review the full product loop without personal Health data.
- Quick-add caffeine, add a custom caffeine entry, run a vigilance test, and share an insights summary or daily totals CSV.

## Beta Review Notes

Aurora uses HealthKit only to read recent sleep data for caffeine and sleep guidance. Health access is optional. If HealthKit is unavailable, denied, or empty, testers can continue with manual logging or load sample data from onboarding or the Sleep screen.

Aurora is not a medical device and does not diagnose, treat, cure, or prevent any disease or condition. Guidance is informational and based on locally stored caffeine logs, imported sleep timing when available, and an on-device reaction test.

No cloud account is required for this demo. Demo records and user logs are stored on device unless the tester explicitly shares or exports a summary.

TestFlight access is free and used only for beta testing. Paid app distribution is handled through the App Store after release approval. Gumroad, if used, contains only companion guide/support material and does not unlock app access.

## Reviewer Access

- TestFlight invite: [insert public or reviewer TestFlight link]
- App Store listing: [insert App Store link, after approval]
- Gumroad companion guide: [insert Gumroad product link, if applicable]
- Privacy policy: https://nmapaye.github.io/aurora/privacy.html
- Support: https://nmapaye.github.io/aurora/support.html
- Sample-data path without Health data: launch Aurora, use manual setup, then tap "Load Sample Data" from onboarding or Sleep.

## Privacy Notes

- HealthKit sleep data is read-only.
- Aurora does not write Health data.
- Sample Data uses generated records identifiable by `demo:` ids.
- Export/share actions use the iOS share sheet and require explicit tester action.

## Known Demo Limits

- Available for iPhone and iPad.
- Cloud sync is not included in v0.1.0.
- Apple Watch and background automation are not included in v0.1.0.
