# Aurora TestFlight Beta Metadata Draft

Use this copy when preparing App Store Connect/TestFlight beta review. Replace bracketed values only after the real build and links exist.

## Beta App Description

Aurora is an iPhone-first caffeine and sleep guidance demo. Testers can log caffeine intake, optionally import recent sleep from Apple Health, run a 60-second vigilance reaction test, and review on-device insights that connect intake timing, sleep windows, and attentiveness.

## What To Test

- Complete onboarding with either HealthKit or manual-only setup.
- Deny Health access and confirm Aurora remains usable with manual caffeine logging.
- Grant Health access, if available, and confirm sleep import or the empty-state explanation is clear.
- Use demo sample data to review the full product loop without personal Health data.
- Quick-add caffeine, add a custom caffeine entry, run a vigilance test, and share an insights summary or daily totals CSV.

## Beta Review Notes

Aurora uses HealthKit only to read recent sleep data for caffeine and sleep guidance. Health access is optional. If HealthKit is unavailable, denied, or empty, testers can continue with manual logging or load deterministic demo sample data from onboarding or the Sleep screen.

Aurora is not a medical device and does not diagnose, treat, cure, or prevent any disease or condition. Guidance is informational and based on locally stored caffeine logs, imported sleep timing when available, and an on-device reaction test.

No cloud account is required for this demo. Demo records and user logs are stored on device unless the tester explicitly shares or exports a summary.

## Reviewer Access

- TestFlight invite: [insert public or reviewer TestFlight link]
- Gumroad package: [insert Gumroad product link, if applicable]
- Demo path without Health data: launch Aurora, use manual setup, then tap "Load demo sample data" from onboarding or Sleep.

## Privacy Notes

- HealthKit sleep data is read-only.
- Aurora does not write Health data.
- Demo mode uses generated sample records identifiable by `demo:` ids.
- Export/share actions use the iOS share sheet and require explicit tester action.

## Known Demo Limits

- iOS-first release candidate.
- Android health integration is deferred.
- Cloud sync is deferred.
- Apple Watch and background automation are deferred.
