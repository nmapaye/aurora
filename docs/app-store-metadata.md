# Aurora App Store metadata draft

This is unpublished copy. Submit only after the release checklist passes.

## Name and subtitle

Aurora — Energy and daily rhythm

## Description

A little clarity for your day. Aurora helps you explore recorded sleep, caffeine, commitments, and reaction speed through interactive native cards on iPhone and iPad.

- Review and save caffeine or manual sleep entries, with editable times and Undo.
- Optionally read sleep and caffeine from Apple Health, and add caffeine you save in Aurora. Each is a separate choice.
- Explore recorded trends and missing information without invented measurements.
- Run a 60-second reaction test and compare against your recorded baseline when enough evidence exists.
- Review selected Apple and Google calendars. Changes require a specific preview and your approval.
- Export records through the native share sheet.
- Opt into morning briefings and cutoff reminders.

Your health records and calculations stay on your device. Supported devices can classify requests using local intelligence; explicit quick actions remain available when local models are unavailable. Google Calendar uses Google authentication and network requests. Aurora has no cloud AI inference, API keys, subscription, or Aurora account.

Alertness values are estimates, not measurements. Aurora does not diagnose fatigue, prescribe caffeine doses, or prescribe sleep schedules. It is not a medical device.

## Commercial defaults

Paid upfront: US$4.99 base price; free TestFlight beta. Initial English storefronts: United States, Canada, United Kingdom, Australia, and New Zealand, subject to regional review. No in-app purchases.

App Privacy: Data Not Collected. Health, caffeine, sleep, and reaction data stay on the device and are never sent to the developer or third parties; `Aurora/PrivacyInfo.xcprivacy` declares no collected data types and no tracking.

## Keywords

caffeine,sleep,energy,coffee,calendar,reaction,alertness,wellness

## URLs and support

Proposed privacy: https://nmapaye.github.io/aurora/privacy.html
Proposed support: https://nmapaye.github.io/aurora/support.html
Verify deployed pages and configure a real private support contact before submission. These drafts have not been published.

## Reviewer notes

Complete manual setup to use Aurora without Health or Calendar access. HealthKit has three separate opt-ins (read sleep, read caffeine, write caffeine saved in Aurora); imported records are read-only, and Aurora edits or deletes only its own caffeine samples. Missing sleep remains missing. App Privacy answer: Data Not Collected. Aurora reads sleep and caffeine from HealthKit and writes dietary caffeine samples, but that Health data is processed and stored only on the device and is never transmitted to the developer or any third party; there is no tracking. The optional "Update in the background" choice uses HealthKit background delivery (entitlement declared; provisioning profile must include it). Explicit quick actions work without a local model. Google Calendar production client registration and verification remain release gates. Account access must never be supplied in repository files.

Debug Design Gallery is excluded from Release. No Mac app or cross-device health/conversation sync is included. Notifications use permitted foreground/background opportunities, not continuous reasoning.

## Remaining metadata gates

Verify signed build, age rating, privacy answers, encryption/export compliance, accessibility, real screenshots, support contact, and final storefront pricing. Do not claim measured speed, battery savings, or medical outcomes without evidence.
