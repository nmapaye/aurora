# Aurora upgrade delivery ledger

Goal: implement and verify every feature in [the approved plan](plan.md).

Baseline: `abd8ded`. Branch: `nmapaye-bot/aurora-50-upgrades`.

Status separates implementation, independent review, and acceptance verification. Pending native checks prevent goal completion.

| # | Feature | Implementation | Review | Verification evidence |
| --- | --- | --- | --- | --- |
| 1 | Personal drink library. | Implemented | State and UI review passed | DrinkLibrary.review UI lifecycle; native/device acceptance pending |
| 2 | Favorite quick adds. | Implemented | State and UI review passed | DrinkLibrary.review persistence; CaffeineLoggingFlow shared order; native/device acceptance pending |
| 3 | Serving calculator. | Implemented | State and UI review passed | CaffeineUpgrades calculator; store.logging arithmetic; native/device acceptance pending |
| 4 | Repeat an entry. | Implemented | State and UI review passed | CaffeineLoggingFlow repeat/edit/save; native/device acceptance pending |
| 5 | Undo recent changes. | Implemented | State and UI review passed | CaffeineLoggingFlow pinned overlay; store.logging.review undo conflicts; native/device acceptance pending |
| 6 | Recover unfinished entries. | Implemented | State and UI review passed | LogIntakeScreen recovery; CaffeineLoggingFlow editor switching; persistence fixtures; native/device acceptance pending |
| 7 | Search caffeine history. | Implemented | State and UI review passed | CaffeineHistoryScreen search; store.logging combined filters; native/device acceptance pending |
| 8 | Filter caffeine history. | Implemented | State and UI review passed | CaffeineHistoryScreen filter/reset; store.logging combined filters; native/device acceptance pending |
| 9 | Record caffeine-free days. | Implemented | State and UI review passed | sampleSeparation zero/sample records; CaffeineLoggingFlow zero control; native/device acceptance pending |
| 10 | Preview a dose’s effect. | Implemented | State and UI review passed | DosePreview now uses shared weekly/exception schedule; native/device acceptance pending |
| 11 | Weekly sleep schedule. | Implemented | Independent domain and UI re-review passed | SleepRoutinesScreen weekday picker; defaults preserve onboarding target; native/device acceptance pending |
| 12 | Schedule exceptions. | Implemented | Independent domain and UI re-review passed | sleep.upgrades date exceptions; independent DST boundary tests; native/device acceptance pending |
| 13 | Consistent bedtime projections. | Implemented | Independent domain and UI re-review passed | Shared scheduledSleep resolver across guidance, previews and reminders; native/device acceptance pending |
| 14 | Morning sleep journal. | Implemented | Independent domain and UI re-review passed | SleepHistory journal UI; store review preserves annotations across episode changes; native/device acceptance pending |
| 15 | Nap session timer. | Implemented | Independent domain and UI re-review passed | Timer UI confirmation/cancel; persistence and invalid-duration regression tests; native/device acceptance pending |
| 16 | Sleep consistency view. | Implemented | Independent domain and UI re-review passed | sleepTrends schedule variation with segmented episodes; native/device acceptance pending |
| 17 | Sleep deficit history. | Implemented | Independent domain and UI re-review passed | sleepTrends missing/sample separation; duration against target; native/device acceptance pending |
| 18 | Sleep overlap review. | Implemented | Independent domain and UI re-review passed | Overlap partner UI; rolling duration interval union and cross-day nap regression; native/device acceptance pending |
| 19 | Searchable sleep history. | Implemented | Independent domain and UI re-review passed | SleepHistory combined filters; journal note search with explicit clock; native/device acceptance pending |
| 20 | Wind-down reminder. | Implemented | Independent domain and UI re-review passed | Permission and foreground tests; reschedule queue and partial-failure cleanup; native/device acceptance pending |
| 21 | Caffeine scenario editor. | Implemented | Independent domain and UI re-review passed | PlanningScreen future editor and pre-dose curve regression; native/device acceptance pending |
| 22 | Saved scenarios. | Implemented | Independent domain and UI re-review passed | PlanningScreen create/reopen/edit/delete; complete persistence roundtrip; native/device acceptance pending |
| 23 | Scenario comparison. | Implemented | Independent domain and UI re-review passed | Common baseline/time and residual math regression; native/device acceptance pending |
| 24 | Threshold crossing estimate. | Implemented | Independent domain and UI re-review passed | Analytical carryover decay after final hypothetical dose; native/device acceptance pending |
| 25 | Half-life sensitivity view. | Implemented | Independent domain and UI re-review passed | Three editable assumptions without changing active preference; native/device acceptance pending |
| 26 | Gradual reduction planner. | Implemented | Independent domain and UI re-review passed | Daily endpoints and both DST transition regression cases; native/device acceptance pending |
| 27 | Daily caffeine budget planner. | Implemented | Independent domain and UI re-review passed | Budget allocation and excess/unused UI tests; native/device acceptance pending |
| 28 | Focus-window comparison. | Implemented | Independent domain and UI re-review passed | Shared focus interval and existing alertness formula projections; native/device acceptance pending |
| 29 | Subjective alertness check-ins. | Implemented | Independent domain and UI re-review passed | Check-in UI/persistence; invalid dates and ratings rejected; native/device acceptance pending |
| 30 | Personal experiment journal. | Implemented | Independent domain and UI re-review passed | Experiment editing and all personal measures; zero versus missing/sample regression; native/device acceptance pending |
| 31 | Combined daily timeline. | Implemented | Independent domain and UI re-review passed | Daily timeline includes overnight sleep and all personal record kinds; native/device acceptance pending |
| 32 | Interactive chart inspection. | Implemented | Independent domain and UI re-review passed | Dual-model inspector; compact/wide endpoint tests and accessible controls; native/device acceptance pending |
| 33 | Weekday pattern comparison. | Implemented | Independent domain and UI re-review passed | Weekday recorded-only averages and counts; explicit zero/missing regression; native/device acceptance pending |
| 34 | Bedtime caffeine versus sleep view. | Implemented | Independent domain and UI re-review passed | Sleep-onset scatter/table; overlap union and five-observation gate; native/device acceptance pending |
| 35 | Vigilance history and details. | Implemented | Independent domain and UI re-review passed | Completed test selection and full reaction/lapse/false-start details; native/device acceptance pending |
| 36 | Personal vigilance comparison. | Implemented | Independent domain and UI re-review passed | Three strictly prior eligible tests; median and selected difference regression; native/device acceptance pending |
| 37 | Subjective versus measured alertness. | Implemented | Independent domain and UI re-review passed | Nearest completed test within 30 minutes; unavailable median retained; five usable pairs; native/device acceptance pending |
| 38 | Data completeness view. | Implemented | Independent domain and UI re-review passed | Calendar flags for caffeine, zero, sleep, tests and check-ins; native/device acceptance pending |
| 39 | Weekly review. | Implemented | Independent domain and UI re-review passed | Weekly current/prior recorded values, user targets and explicit missing counts; native/device acceptance pending |
| 40 | Explain each metric. | Implemented | Independent domain and UI re-review passed | Contextual explanations checked against Summary, Planning and Explorer inputs; native/device acceptance pending |
| 41 | Customizable Summary. | Pending | Pending | Pending |
| 42 | Accessible chart tables. | Pending | Pending | Pending |
| 43 | Reminder center. | Pending | Pending | Pending |
| 44 | Backup and restore. | Pending | Pending | Pending |
| 45 | Privacy and deletion controls. | Pending | Pending | Pending |
| 46 | Home Screen widget. | Pending | Pending | Pending |
| 47 | Lock Screen widgets. | Pending | Pending | Pending |
| 48 | Log-drink Shortcut. | Pending | Pending | Pending |
| 49 | Status Shortcut. | Pending | Pending | Pending |
| 50 | Nap Live Activity. | Pending | Pending | Pending |

## Delivery gates

- Baseline Node 24 type-check and lint: passed. Jest: 47 suites / 240 tests passed.
- Final Node 24 type-check, lint, Jest, iOS export, website checks: pending.
- Debug and Release simulator builds: pending full supported Xcode.
- Physical iPhone/iPad native checks, VoiceOver, large text, Reduce Motion: pending.
- No merging or publishing.

## Work log

- 2026-09-07: Created isolated worktree from approved baseline. Primary checkout HealthKit modifications preserved. Goal already active with attached plan. Logging implementation 1–10 assigned to fresh implementation agent.

- Foundation: shared calendar helpers and foreground-aware clock added using red-green tests. Focused New York timezone gate passed 2 suites / 12 tests, including 23/25-hour days. Independent foundation review and fix/re-review passed.
- Website baseline type-check and build passed. Expo export initially identified symlinked dependency entrypoint resolution; resolved with an isolated dependency copy, then iOS export passed (1644 modules).
- Native prerequisite probe: xcodebuild requires full Xcode; simctl unavailable. No native verification claimed.

- Added `scripts/verify-upgrades.sh` to pin Node 24 for npm and all child commands. Earlier explicit npm invocation did not guarantee child Node version; all final checks will use the script. Under corrected PATH, foundation plus logging state/persistence passed 4 suites / 34 tests. Script syntax and independent review passed after adding full stable Xcode preflight; `--native` correctly reports missing Xcode.

- Logging batch implementation and independent state/UI fix-reviews passed. Full pinned Node 24 gate: 55 suites / 287 tests, type-check, lint, diff whitespace check, and root iOS Expo export (1647 modules). Detailed evidence in `reviews/logging.md` and `evidence/logging-jest.txt`. Features 1–9 implemented; feature10 awaits shared schedule integration in next batch.

- Started sequential sleep batch11–20 from reviewed logging commit b711a97. Shared bedtime resolver also completes feature10 integration.

- Sleep accounting checkpoint: reproduced5 failures in6 overlap regressions, then corrected rolling24-hour duration to union valid clipped intervals. Root gate passed3 suites10tests including unchanged alertness tests; independent sleep_accounting_review passed. Broader sleep batch and cross-day presentation remain in progress.

- Sleep batch 11–20 and shared schedule integration for feature 10 passed independent fix/re-review. Node 24 type-check/lint and 65 Jest suites passed (338 tests, one timezone-specific skip covered by the separate 25-test New York gate). iOS export passed with 1650 modules, website checks passed, and git diff/script syntax checks passed. Details in reviews/sleep.md and evidence/sleep-jest.txt. Native/device acceptance remains pending.

- Started sequential planning batch 21–30 from reviewed sleep commit db700f9. Hypothetical schedules remain separate from recorded history, and every comparison uses the same baseline and explicit time input.

- Planning integration caught a missed SleepRoutines standalone-route dispatch in the shared navigation helper. The next batch includes the route correction and a dispatch regression test; prior screen tests mocked this helper, so they did not establish end-to-end reachability. Four independent planning domain checks pass under America/New_York (carryover crossing, reusable scenario timing, DST targets, sample and missing-data separation).

- Planning batch 21–30 passed independent domain/UI fix-reviews. Node 24 type-check/lint and 73 Jest suites passed (371 tests, one DST skip covered by separate 30-test New York gate). Expo iOS export passed with 1656 modules. SleepRoutines standalone dispatch fixed and tested. Details in reviews/planning.md and evidence/planning-jest.txt. Native/device acceptance remains pending.

- Started sequential insights batch 31–40 from reviewed planning commit e411cfd. New comparisons must show eligible sample counts, preserve missing data and exclude Sample Data.

- Insights batch 31–40 passed independent domain/UI fix-reviews. Node 24 type-check/lint and 78 Jest suites passed (400 tests, one DST skip covered by the separate 35-test New York gate). Expo iOS export passed with 1659 modules. Details in reviews/insights.md and evidence/insights-jest.txt. Native/device acceptance remains pending.
