# Aurora TestFlight metadata draft

Unpublished. No TestFlight invitation exists from this draft.

## Beta description

Aurora is a local-first iPhone and iPad assistant for energy and daily rhythm. Interactive cards support caffeine and sleep recording, evidence review, trends, reaction tests, approved calendar changes, exports, and optional reminders.

## What to test

- Manual setup, missing records, sample labels, and separate optional Apple Health sleep/caffeine reads and Aurora-owned caffeine export.
- Reminders: the cutoff time starts unset and its reminder turns on only after you set one; wake reminders; drink follow-ups, which ask about an hour after yesterday's time with at most one silent notification a day.
- Caffeine/sleep draft edits, invalid values, duplicate taps, Save, Undo, history corrections, exports, and relaunch snapshots.
- Full local-data erase and onboarding after relaunch.
- Offline use and unavailable local models through explicit quick actions.
- Selected Apple-synced calendars, read-only access, recurrence scope, stale proposals, and partial failures. Never approve a real change you do not intend.
- Largest text, VoiceOver, Reduce Motion, light/dark, keyboard, Stop, and interrupted processing on real iPhone and iPad.

## Beta review notes

Apple Health is optional, with three separate choices: read sleep, read caffeine, and add caffeine saved in Aurora. Imported records stay read-only; Aurora changes or deletes only caffeine samples it wrote. Records and conversation storage remain on-device and are excluded from Aurora's backup storage. This beta uses Apple Calendar through EventKit, including Google calendars synced by iOS. Direct Google OAuth and Calendar API access are disabled. Calendar changes require a fresh approved preview. No API keys or cloud AI inference are accepted. Model availability does not prevent explicit native logging and review.

Estimates can’t establish the cause of fatigue, and Aurora doesn’t prescribe caffeine doses or sleep schedules. It is not a medical device. Informational only. Doesn’t diagnose, treat, cure or prevent any condition. Check with a doctor before medical decisions.

Intelligence is local. On devices where Apple Intelligence is available (iOS 26 or later), Aurora uses Apple's on-device Foundation Models only to understand typed requests; explicit quick actions remain available elsewhere. Dictation requires on-device speech recognition. The local Ollama developer option exists only in Simulator builds and is unavailable in device builds.

No Aurora account or sign-in is needed, and Aurora has no server.

To test HealthKit: add a Sleep sample and a Caffeine sample in the Health app. In Aurora settings, open Connections → Apple Health and enable the separate choices to read sleep, read caffeine, and add caffeine saved in Aurora. Imported samples appear as read-only records. Log a caffeine entry in Aurora and inspect its separate Apple Health status before checking Health → Nutrition → Caffeine for Aurora's sample. Denied or revoked access leaves manual entry available; an empty read does not establish whether Health read access was granted.

App Privacy: Data Not Collected. Aurora includes no tracking, analytics or advertising SDK. Health records and conversation are not sent to the developer or an AI provider. CSV export happens only when the person shares a file. Calendar synchronization follows the device's configured account provider, as described above.

## Access and gates

Free TestFlight access; public release defaults to paid upfront. Supply actual reviewer access through App Store Connect only if required, never repository credentials. Distribution signing, physical-device acceptance, independent installation and privacy/support verification remain pending. Direct Google sign-in is deferred from this beta, not a beta setup requirement. See app-store-release-checklist.md.

Privacy: https://aurora.nmapaye.com/privacy.html
Support: https://aurora.nmapaye.com/support.html

The canonical pages returned HTTPS 200 on October 28. The served privacy page
still described direct Google Calendar access, and the support page still asked
for Health read decisions Aurora cannot observe. Repository corrections require
an approved website publication and a post-publication content check before beta;
URL reachability alone does not satisfy that gate. No publication is implied by
these metadata changes.
