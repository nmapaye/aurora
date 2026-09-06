# Aurora upgrade delivery ledger

Goal: implement and verify every feature in [the approved plan](plan.md).

Baseline: `abd8ded`. Branch: `nmapaye-bot/aurora-50-upgrades`.

Status separates implementation, independent review, and acceptance verification. Pending native checks prevent goal completion.

| # | Feature | Implementation | Review | Verification evidence |
| --- | --- | --- | --- | --- |
| 1 | Personal drink library. | Pending | Pending | Pending |
| 2 | Favorite quick adds. | Pending | Pending | Pending |
| 3 | Serving calculator. | Pending | Pending | Pending |
| 4 | Repeat an entry. | Pending | Pending | Pending |
| 5 | Undo recent changes. | Pending | Pending | Pending |
| 6 | Recover unfinished entries. | Pending | Pending | Pending |
| 7 | Search caffeine history. | Pending | Pending | Pending |
| 8 | Filter caffeine history. | Pending | Pending | Pending |
| 9 | Record caffeine-free days. | Pending | Pending | Pending |
| 10 | Preview a dose’s effect. | Pending | Pending | Pending |
| 11 | Weekly sleep schedule. | Pending | Pending | Pending |
| 12 | Schedule exceptions. | Pending | Pending | Pending |
| 13 | Consistent bedtime projections. | Pending | Pending | Pending |
| 14 | Morning sleep journal. | Pending | Pending | Pending |
| 15 | Nap session timer. | Pending | Pending | Pending |
| 16 | Sleep consistency view. | Pending | Pending | Pending |
| 17 | Sleep deficit history. | Pending | Pending | Pending |
| 18 | Sleep overlap review. | Pending | Pending | Pending |
| 19 | Searchable sleep history. | Pending | Pending | Pending |
| 20 | Wind-down reminder. | Pending | Pending | Pending |
| 21 | Caffeine scenario editor. | Pending | Pending | Pending |
| 22 | Saved scenarios. | Pending | Pending | Pending |
| 23 | Scenario comparison. | Pending | Pending | Pending |
| 24 | Threshold crossing estimate. | Pending | Pending | Pending |
| 25 | Half-life sensitivity view. | Pending | Pending | Pending |
| 26 | Gradual reduction planner. | Pending | Pending | Pending |
| 27 | Daily caffeine budget planner. | Pending | Pending | Pending |
| 28 | Focus-window comparison. | Pending | Pending | Pending |
| 29 | Subjective alertness check-ins. | Pending | Pending | Pending |
| 30 | Personal experiment journal. | Pending | Pending | Pending |
| 31 | Combined daily timeline. | Pending | Pending | Pending |
| 32 | Interactive chart inspection. | Pending | Pending | Pending |
| 33 | Weekday pattern comparison. | Pending | Pending | Pending |
| 34 | Bedtime caffeine versus sleep view. | Pending | Pending | Pending |
| 35 | Vigilance history and details. | Pending | Pending | Pending |
| 36 | Personal vigilance comparison. | Pending | Pending | Pending |
| 37 | Subjective versus measured alertness. | Pending | Pending | Pending |
| 38 | Data completeness view. | Pending | Pending | Pending |
| 39 | Weekly review. | Pending | Pending | Pending |
| 40 | Explain each metric. | Pending | Pending | Pending |
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
- Website baseline build passed; Expo export identified symlinked dependency entrypoint resolution problem. Preparing isolated dependency copy.
- Native prerequisite probe: xcodebuild requires full Xcode; simctl unavailable. No native verification claimed.
