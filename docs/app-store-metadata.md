# Aurora App Store Metadata Draft

Use this copy when preparing the App Store release. Aurora is free to download with one in-app purchase, Aurora Plus. Replace bracketed values only after the real App Store Connect record, support URL, privacy URL, screenshots, and pricing exist.

## Name

Aurora

## Subtitle

Sleep-aware caffeine guidance

## Description

Aurora helps you understand how caffeine timing, sleep, and alertness fit together. Log caffeine quickly, optionally import recent sleep from Apple Health, run a 60-second vigilance reaction test, and review private on-device insights.

Aurora is built for people who want a clearer caffeine routine without a cloud account. Health access is optional, manual logging works on its own, and sample data lets you explore the app before using personal Health data.

Core features:

- Quick caffeine logging and custom entries.
- Optional read-only Apple Health sleep import.
- Manual-only setup for users who skip Health access.
- 60-second vigilance reaction test.
- Sleep-aware daily guidance and insights.
- Shareable summary text and daily totals CSV through the iOS share sheet.
- Local sample data that can be removed without deleting personal records.

Aurora is informational only. It is not a medical device and does not diagnose, treat, cure, or prevent any disease or condition.

## Promotional Text

Track caffeine, protect sleep, and check alertness privately on iPhone and iPad.

## Keywords

caffeine,sleep,alertness,health,focus,coffee,energy,reaction,time,wellness

## Support URL

https://nmapaye.github.io/aurora/support.html

## Privacy Policy URL

https://nmapaye.github.io/aurora/privacy.html

## Review Notes

Aurora uses HealthKit only to read recent sleep data for caffeine and sleep guidance. Health access is optional. If HealthKit is unavailable, denied, or empty, users can continue with manual logging or load sample data from onboarding or the Sleep screen.

No cloud account is required. Demo records and user logs are stored on device unless the user explicitly shares or exports a summary.

Aurora is free to download. Aurora Plus (`com.nmapaye.aurora.plus`) is a non-consumable in-app purchase that unlocks the two-week and month views in Insights and Sleep. Logging, the alertness estimate, the Reaction Test, Health import and exports are free. To review Plus, open Settings → Aurora Plus, or choose 2W or M in Insights. Restore Purchase is on the same screen. There are no license keys, Gumroad unlock codes or accounts.

## Known Release Limits

- Available for iPhone and iPad.
- Cloud sync is not included in v0.1.0.
- Apple Watch support is not included in v0.1.0.
- Background automation is not included in v0.1.0.
