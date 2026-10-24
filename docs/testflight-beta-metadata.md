# Aurora TestFlight metadata draft

Unpublished. No TestFlight invitation exists from this draft.

## Beta description

Aurora is a local-first iPhone and iPad assistant for energy and daily rhythm. Interactive cards support caffeine and sleep recording, evidence review, trends, reaction tests, approved calendar changes, exports, and optional reminders.

## What to test

- Manual setup, missing records, sample labels, and optional read-only Apple Health connection.
- Caffeine/sleep draft edits, invalid values, duplicate taps, Save, Undo, history corrections, exports, and relaunch snapshots.
- Full local-data erase and onboarding after relaunch.
- Offline use and unavailable local models through explicit quick actions.
- Apple/Google calendars, read-only access, recurrence scope, stale proposals, and partial failures. Never approve a real change you do not intend.
- Largest text, VoiceOver, Reduce Motion, light/dark, keyboard, Stop, and interrupted processing on real iPhone and iPad.

## Beta review notes

HealthKit is read-only and optional. Records and conversation storage remain on-device and are excluded from Aurora's backup storage. Google Calendar requires direct Google authentication and network requests; local account tokens are protected in Keychain. No API keys or cloud AI inference are accepted. Model availability does not prevent explicit native logging and review.

Estimates can’t establish the cause of fatigue, and Aurora doesn’t prescribe caffeine doses or sleep schedules. It is not a medical device. Informational only. Doesn’t diagnose, treat, cure or prevent any condition. Check with a doctor before medical decisions.

## Access and gates

Free TestFlight access; public release defaults to paid upfront. Supply actual reviewer access through App Store Connect only if required, never repository credentials. Production Google configuration, signed archive, physical-device acceptance, and privacy/support deployment remain pending. See app-store-release-checklist.md.

Proposed privacy: https://nmapaye.github.io/aurora/privacy.html
Proposed support: https://nmapaye.github.io/aurora/support.html
