# Aurora beta tester guide

Draft for owner-approved distribution. No public beta link or invitation is
created by this file. Aurora targets iPhone and iPad on iOS/iPadOS 17 or later;
the current sprint has simulator coverage on 26.5 only. TestFlight is free.

## Before testing

Use the exact build the owner invited you to test through TestFlight. Record the
version/build, device and OS. The owner must confirm the feedback/support route
and the build's known issues before sending invitations. Do not install an
unsigned local archive or assume a GitHub commit is an available beta build.

Begin with Sample Data or a dedicated test device. Sample records are labelled
and read-only. Health, calendars, dictation and reminders are optional; skipping
them must leave manual logging and review usable. There is no cloud AI API key.

## Suggested pass through the app

1. Install, open, skip optional setup, close and reopen. Confirm setup progress
   and later records survive relaunch.
2. Explore Sample Data, then use a separate empty fixture installation to check
   “No record” and missing estimates. A missing record must not appear as zero.
3. Log a manual caffeine entry and sleep record. Review before Save, tap Save
   again, verify one entry, and test Undo. Check history and export the CSVs to a
   location you control. Treat exports as private files.
4. Review energy/trend cards with little history, and run a complete Reaction
   Test. The duration shown by the tested build is authoritative. Backgrounding
   mid-test must interrupt rather than silently save an incomplete result.
5. With optional permissions, use only dedicated Health samples and calendar
   events. Health sleep/caffeine reads and caffeine export are separate choices.
   Imported samples are read-only in Aurora. Calendar previews require explicit
   approval and revalidation; never approve a real change you do not intend.
6. Try the software keyboard, largest text, VoiceOver, Reduce Motion, light/dark,
   orientation, background/return and offline use. Report unreachable controls,
   hidden titles, misleading receipts or lost text.
7. Test full erase only on a disposable fixture installation with no needed data.
   It removes local records/conversation and returns to setup after relaunch.
   Existing Aurora exports in Apple Health are deliberately left in Health.

## Feedback and known limits

Use the configured TestFlight feedback route, or the owner's verified private
support route. For a public GitHub bug, use the Beta bug template with synthetic
values and cropped/redacted screenshots. Include steps, expected/actual result,
version/build, device/OS, reproducibility and whether Sample Data was used.
Never include Health records, calendar details, conversation dumps, CSVs, tokens,
Apple account information or credentials publicly. Security reports follow
[`SECURITY.md`](../SECURITY.md).

Current candidate limits: no signed distributed build is proven; physical Health,
accessibility, legacy upgrade and background behavior remain unvalidated. The
archive has no direct Google configuration; Apple-synced calendars are a separate
connection. The owner accepted the 3h/18h alertness display rule and ongoing-sleep behavior
as disclosed assumptions. This beta uses Apple-synced calendars only; direct
Google sign-in is deferred. Physical acceptance remains required. CI intermittency is not considered
resolved until the stress and final integration gates pass. See
[the current scorecard](beta-sprint.md) for build-specific evidence and blockers.

Aurora describes records and estimates; it does not prescribe caffeine doses or
sleep schedules. An estimate is not a measurement or a diagnosis.

Owner-assisted hardware gates and evidence fields are in the
[device acceptance protocol](beta-device-acceptance.md). These checks are not
marked passed by the existence of a checklist.
