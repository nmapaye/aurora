# Sleep batch review

Scope: features 11–20 and feature 10 shared-bedtime integration. Independent domain/state and UI re-reviews found no unresolved material findings. Physical device acceptance remains pending.

## Resolved findings

- Journal lookup retains an existing annotated episode member. Saving updates episode members, and deleting a manual anchor preserves annotations on surviving records. Imported Health records remain read-only.
- Nonexistent DST wall times move forward. If that adjustment reverses a short configured interval, the resolver preserves its positive configured duration and exposes the adjustment in the UI. Normal overnight schedules retain 23/25-hour calendar behavior.
- Initial wake defaults continue following the onboarding sleep target until the weekly schedule is edited.
- Rolling sleep accounting unions valid clipped intervals, and presentation subtracts overlapping main sleep from naps even when their wake dates differ.
- Foreground activation rechecks notification permissions even on the same day. Reminder scheduling is serialized, and partial native scheduling failures clean up owned notifications while preserving unrelated reminders.
- Overlap rows show full start/end times and each partner’s source. Weekday controls expose both times and the wake-date relationship to accessibility services.

Independent reviewers: sleep_domain_review, sleep_ui_review, sleep_accounting_review. Root regression files cover schedules, persistence, journal membership, interval accounting and reminder failure cleanup. The domain reviewer ran 40 focused tests under America/New_York; the UI reviewer ran 19 focused tests.

## Verification

Root America/New_York gate passed 25 tests, including the spring-forward schedule gap. iOS Expo export passed with 1650 modules. Website type-check and build passed. Node 24 type-check and lint passed. Full Jest passed 65 suites with 338 tests and one DST-specific test skipped in the default timezone; that test passed in the separate New York gate. Full Jest evidence is stored in ../evidence/sleep-jest.txt.

Full native Debug/Release builds and physical iPhone/iPad layout, VoiceOver, large text and Reduce Motion checks remain pending. Xcode and device prerequisites prevent claiming final acceptance.

Reminders schedule the next 14 days and replenish on launch, foreground activation, day changes and edits. Delivery after a longer period without opening Aurora is not guaranteed.
