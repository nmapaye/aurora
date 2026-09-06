# Customization and data ownership review

Scope: features 41–45. Independent domain and UI fix-reviews passed. App checks passed; native/device acceptance remains pending.

## Resolved findings

- Reminder schedule generation now passes local date keys to the shared sleep resolver. Boundary tests cover quiet-hour start/end, wind-down notifications crossing midnight, and spring/fall wall-clock schedules.
- Routine deletion preserves pending nap timers, which belong to sleep data. Sleep deletion clears local sleep copies, journals and timers without touching caffeine records. All-data deletion clears transient undo state and reminder preferences.
- Backup imports reject unknown time zones and inconsistent vigilance counts/durations/metrics. Planning duplicate detection now uses a linear pass for larger imports. Required fields are validated; some unused nested extra fields are permitted, so this is not a claim of exact nested-key rejection.
- The explicit notification permission action works with no enabled reminders and remains blocked during walkthrough. Permission reporting follows the OS status rather than inferring it from whether another request is allowed.
- Reminder steppers expose disabled state during walkthrough. Scheduling serializes edits and cleans partially scheduled plans while preserving unrelated notifications.

## Independent evidence

Root tests cover detached personal-only exports, permission/sync exclusion, malformed versions and dates, duplicate IDs, cancellation and file-size boundaries, file cleanup after failure, selective deletion, restored walkthrough cards, quiet hours and queued reminder replacement. Domain re-review passed 14 tests. UI review passed 24 tests, including chart-table access, picker cancellation, preview before replacement, and deletion confirmation.

Every chart renderer has a text alternative. New screens are linked from Settings and registered through the shared standalone-route dispatcher. The reminder center states its 14-day scheduling horizon and replenishment behavior. Backup controls label exported JSON as unencrypted and explain that local Health deletion does not delete Apple Health records.

## Native dependency boundary

SDK 54-compatible document picker, file system and sharing packages were added with the lockfile. The manually owned native project was not regenerated. Native bootstrap and Debug/Release builds await the supported Xcode toolchain. Physical file picking/sharing, notification delivery, iPhone/iPad layout, Dynamic Type and VoiceOver still require device verification.

Final Node 24 verification passed type-check, lint, 89 Jest suites and 440 tests. The one timezone-specific skip passed in the separate New York gate (39 tests). Root iOS Expo export passed with 1678 modules, and website type-check/build passed. Diff whitespace and verification-script syntax checks passed. Full Jest evidence is retained in ../evidence/ownership-jest.txt.
