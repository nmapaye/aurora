# Aurora TestFlight metadata draft

Unpublished. No TestFlight invitation exists from this draft.

## Beta description

Aurora is a local-first iPhone and iPad assistant for energy and daily rhythm. Interactive cards support caffeine and sleep recording, evidence review, trends, reaction tests, approved calendar changes, exports, and optional reminders.

## What to test

- Manual setup, missing records, sample labels, and separate optional Apple Health sleep/caffeine reads and Aurora-owned caffeine export.
- Caffeine/sleep draft edits, invalid values, duplicate taps, Save, Undo, history corrections, exports, and relaunch snapshots.
- Full local-data erase and onboarding after relaunch.
- Offline use and unavailable local models through explicit quick actions.
- Selected Apple-synced calendars, read-only access, recurrence scope, stale proposals, and partial failures. Never approve a real change you do not intend.
- Largest text, VoiceOver, Reduce Motion, light/dark, keyboard, Stop, and interrupted processing on real iPhone and iPad.

## Beta review notes

Apple Health is optional, with three separate choices: read sleep, read caffeine, and add caffeine saved in Aurora. Imported records stay read-only; Aurora changes or deletes only caffeine samples it wrote. Records and conversation storage remain on-device and are excluded from Aurora's backup storage. This beta uses Apple Calendar through EventKit, including Google calendars synced by iOS. Direct Google OAuth and Calendar API access are disabled. Calendar changes require a fresh approved preview. No API keys or cloud AI inference are accepted. Model availability does not prevent explicit native logging and review.

Aurora is informational, not a medical device. Estimates cannot establish the cause of fatigue or prescribe caffeine doses or sleep schedules.

## Access and gates

Free TestFlight access; public release defaults to paid upfront. Supply actual reviewer access through App Store Connect only if required, never repository credentials. Distribution signing, physical-device acceptance, independent installation and privacy/support verification remain pending. Direct Google sign-in is deferred from this beta, not a beta setup requirement. See app-store-release-checklist.md.

Proposed privacy: https://nmapaye.github.io/aurora/privacy.html
Proposed support: https://nmapaye.github.io/aurora/support.html
