# Aurora TestFlight metadata draft

Unpublished. No TestFlight invitation exists from this draft.

## Beta description

Aurora is a local-first iPhone and iPad assistant for energy and daily rhythm. Interactive cards support caffeine and sleep recording, evidence review, trends, reaction tests, approved calendar changes, exports, and optional reminders.

## What to test

- Manual setup, missing records, sample labels, and the optional Apple Health choices: reading sleep, reading caffeine, and adding caffeine saved in Aurora.
- Reminders: the cutoff time starts unset and its reminder turns on only after you set one; wake reminders; drink follow-ups, which ask about an hour after yesterday's time with at most one silent notification a day.
- Caffeine/sleep draft edits, invalid values, duplicate taps, Save, Undo, history corrections, exports, and relaunch snapshots.
- Full local-data erase and onboarding after relaunch.
- Offline use and unavailable local models through explicit quick actions.
- Apple/Google calendars, read-only access, recurrence scope, stale proposals, and partial failures. Never approve a real change you do not intend.
- Largest text, VoiceOver, Reduce Motion, light/dark, keyboard, Stop, and interrupted processing on real iPhone and iPad.

## Beta review notes

Apple Health is optional: separate reads for sleep and caffeine, and an optional write for caffeine saved in Aurora. Records and conversation storage remain on-device and are excluded from Aurora's backup storage. Google Calendar requires direct Google authentication and network requests; local account tokens are protected in Keychain. No API keys or cloud AI inference are accepted. Model availability does not prevent explicit native logging and review.

Aurora is informational, not a medical device. Estimates cannot establish the cause of fatigue or prescribe caffeine doses or sleep schedules.

## Access and gates

Free TestFlight access; public release defaults to paid upfront. Supply actual reviewer access through App Store Connect only if required, never repository credentials. Production Google configuration, signed archive, physical-device acceptance, and privacy/support deployment remain pending. See app-store-release-checklist.md.

Proposed privacy: https://nmapaye.github.io/aurora/privacy.html
Proposed support: https://nmapaye.github.io/aurora/support.html
