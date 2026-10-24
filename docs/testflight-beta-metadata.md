# Aurora TestFlight metadata draft

Unpublished. No TestFlight invitation exists from this draft.

## Beta description

Aurora is a local-first iPhone and iPad assistant for energy and daily rhythm. Interactive cards support caffeine and sleep recording, evidence review, trends, reaction tests, approved calendar changes, exports, and optional reminders.

## What to test

- Manual setup, missing records, sample labels, and optional Apple Health connection (read sleep and caffeine; add caffeine you save in Aurora).
- Caffeine/sleep draft edits, invalid values, duplicate taps, Save, Undo, history corrections, exports, and relaunch snapshots.
- Full local-data erase and onboarding after relaunch.
- Offline use and unavailable local models through explicit quick actions.
- Apple Calendar (on this device, through EventKit full access; Aurora moves an event only after you approve its preview): calendars you can't edit, recurrence scope, stale proposals, and partial failures. Google Calendar sign-in isn't available in this build. Never approve a real change you do not intend.
- Largest text, VoiceOver, Reduce Motion, light/dark, keyboard, Stop, and interrupted processing on real iPhone and iPad.

## Beta review notes

HealthKit is optional: Aurora reads sleep and caffeine and adds only caffeine you save in Aurora, each as a separate choice. Records and conversation storage remain on-device and are excluded from Aurora's backup storage. No API keys or cloud AI inference are accepted. Model availability does not prevent explicit native logging and review.

Aurora is informational, not a medical device. Estimates cannot establish the cause of fatigue or prescribe caffeine doses or sleep schedules.

Google Calendar isn't available in this build: Aurora's production Google sign-in isn't configured, so the Calendars screen shows a note instead of a sign-in button and the app makes no Google requests. Apple Calendar works on the device through EventKit, and Aurora changes an event only after you approve its preview.

Intelligence is local. On devices where Apple Intelligence is available (iOS 26 or later), Aurora uses Apple's on-device Foundation Models only to understand typed requests; elsewhere explicit quick actions do the same work. Dictation uses on-device speech recognition only. A developer option to use a local Ollama model on a Mac exists only in Simulator builds and isn't available in device builds.

No account or sign-in is needed, and Aurora has no server.

To test HealthKit: in the Health app, add a Sleep sample and a Caffeine sample. In Aurora, tap the settings button (sliders icon) → Connections → Apple Health, and turn on Read sleep, Read caffeine and Add my caffeine to Health. The samples appear in Aurora as read-only records. A caffeine entry logged in Aurora appears in Health → Nutrition → Caffeine with AURORA as its source. Denying or revoking access leaves Aurora usable with manual entries.

App Privacy: Data Not Collected. Nothing is sent to the developer or any third party; no tracking, analytics or advertising. CSV export happens only when you share a file.

## Access and gates

Free TestFlight access; public release defaults to paid upfront. Supply actual reviewer access through App Store Connect only if required, never repository credentials. Signed archive, physical-device acceptance, and privacy/support deployment remain pending. Google Calendar isn't part of v0.1.0. See app-store-release-checklist.md.

Proposed privacy: https://nmapaye.github.io/aurora/privacy.html
Proposed support: https://nmapaye.github.io/aurora/support.html
