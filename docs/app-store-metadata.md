# Aurora App Store metadata draft

This unpublished draft describes the approved Apple-synced-calendar beta candidate.
Revisit paid App Store scope before submission, and submit only after its release
checklist passes.

## Name and subtitle

Aurora — Energy and daily rhythm

## Description

A little clarity for your day. Aurora helps you explore recorded sleep, caffeine, commitments, and reaction speed through interactive native cards on iPhone and iPad.

- Review and save caffeine or manual sleep entries, with editable times and Undo.
- Optionally read sleep and caffeine from Apple Health, and add caffeine you save in Aurora. Each is a separate choice.
- Explore recorded trends and missing information without invented measurements.
- Run a 60-second reaction test and compare against your recorded baseline when enough evidence exists.
- Review selected calendars synced with Apple Calendar. Changes require a specific preview and your approval. Direct Google sign-in is deferred from this beta.
- Export records through the native share sheet.
- Opt into morning briefings and cutoff reminders.

Your health records and calculations stay on your device. Supported devices can classify requests using local intelligence; explicit quick actions remain available when local models are unavailable. Calendars synced with Apple Calendar can be included; direct Google sign-in is disabled in this beta. Aurora has no cloud AI inference, API keys, subscription, or Aurora account.

Alertness values are estimates, not measurements. Aurora does not diagnose fatigue, prescribe caffeine doses, or prescribe sleep schedules. It is not a medical device.

## Commercial defaults

Paid upfront: US$4.99 base price; free TestFlight beta. Initial English storefronts: United States, Canada, United Kingdom, Australia, and New Zealand, subject to regional review. No in-app purchases in v0.1.0.

App Privacy: Data Not Collected. Health, caffeine, sleep, and reaction data stay on the device and are never sent to the developer or third parties; `Aurora/PrivacyInfo.xcprivacy` declares no collected data types and no tracking. Calendar access uses EventKit; iOS may sync calendars through the account provider configured by the person. This beta does not authenticate directly with Google or call its Calendar API, and Aurora runs no server. CSV export happens only through the user-initiated share sheet.

## Keywords

caffeine,sleep,energy,coffee,calendar,reaction,alertness,wellness

## URLs and support

Proposed privacy: https://nmapaye.github.io/aurora/privacy.html
Proposed support: https://nmapaye.github.io/aurora/support.html
Verify deployed pages and configure a real private support contact before submission. These drafts have not been published.

## Reviewer notes

Complete manual setup to use Aurora without Health or Calendar access. HealthKit has three separate opt-ins (read sleep, read caffeine, write caffeine saved in Aurora); imported records are read-only, and Aurora edits or deletes only its own caffeine samples. Missing sleep remains missing. App Privacy answer: Data Not Collected. Aurora reads sleep and caffeine from HealthKit and writes dietary caffeine samples, but that Health data is processed and stored only on the device and is never transmitted to the developer or any third party; there is no tracking. Aurora's own records store (Application Support/Aurora) is excluded from device backups and is not opened until that exclusion is confirmed. Health data appears in the app on the Sleep screen (imported nights, marked read-only), in the caffeine Log (imported Health caffeine entries are read-only; Aurora's own entries show their Apple Health write status), on the Apple Health connection screen, and as inputs to the on-device energy estimates in Summary, Insights, and Assistant cards. Calendar access uses EventKit; iOS may sync calendars through the account provider configured by the person. Direct Google OAuth and Google Calendar API calls are disabled in this beta, and Aurora runs no server. CSV export happens only through the user-initiated share sheet. The optional "Update in the background" choice uses HealthKit background delivery (entitlement declared; provisioning profile must include it). Explicit quick actions work without a local model. Verify Apple Calendar consent and the absence of direct Google configuration in the beta archive. Account access must never be supplied in repository files.

Debug Design Gallery is excluded from Release. No Mac app or cross-device health/conversation sync is included. Notifications use permitted foreground/background opportunities, not continuous reasoning.

## Remaining metadata gates

Verify signed build, age rating, privacy answers, encryption/export compliance, accessibility, real screenshots, support contact, and final storefront pricing. Do not claim measured speed, battery savings, or medical outcomes without evidence.
