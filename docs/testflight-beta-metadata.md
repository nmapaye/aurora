# Aurora TestFlight metadata draft

Unpublished. No TestFlight invitation exists from this draft.

## Beta description

Aurora is a local-first iPhone and iPad assistant for energy and daily rhythm. Interactive cards support caffeine and sleep recording, evidence review, trends, reaction tests, approved calendar changes, exports, and optional reminders.

## What to test

- Manual setup, missing records, sample labels, and optional Apple Health connection (separate opt-ins to read sleep, read caffeine, and write caffeine you save in Aurora; imported records stay read-only).
- Caffeine/sleep draft edits, invalid values, duplicate taps, Save, Undo, history corrections, exports, and relaunch snapshots.
- Full local-data erase and onboarding after relaunch.
- Offline use and unavailable local models through explicit quick actions.
- Apple/Google calendars, read-only access, recurrence scope, stale proposals, and partial failures. Never approve a real change you do not intend.
- Largest text, VoiceOver, Reduce Motion, light/dark, keyboard, Stop, and interrupted processing on real iPhone and iPad.

Send feedback through TestFlight, or email nmapaye@outlook.com. Don't include Health records, calendar details, or credentials.

## Beta review notes

HealthKit is optional. Aurora reads sleep and caffeine, and only if you turn it on, writes caffeine you save in Aurora; it updates or removes only those entries, never data from other apps or devices. Records and conversation storage remain on-device and are excluded from Aurora's backup storage. Google Calendar requires direct Google authentication and network requests; local account tokens are protected in Keychain. No API keys or cloud AI inference are accepted. Model availability does not prevent explicit native logging and review.

Aurora is informational, not a medical device. Estimates cannot establish the cause of fatigue or prescribe caffeine doses or sleep schedules.

## Access and gates

Free TestFlight access; public release defaults to paid upfront. Supply actual reviewer access through App Store Connect only if required, never repository credentials. Production Google configuration, signed archive, physical-device acceptance, and privacy/support deployment remain pending. See app-store-release-checklist.md.

Proposed privacy: https://nmapaye.github.io/aurora/privacy.html
Proposed support: https://nmapaye.github.io/aurora/support.html
Beta feedback and access requests: nmapaye@outlook.com (owner approved 2026-10-24)

## Beta sign-up

The website's "Request beta access" link opens an email to nmapaye@outlook.com (subject "Aurora beta request") asking for the tester's Apple ID email and device. First wave: small and invite-only; no dates promised. Addresses are used only to send a TestFlight invite and beta updates, aren't shared or sold, and testers can ask to be removed any time by replying.
