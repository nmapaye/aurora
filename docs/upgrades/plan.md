# Aurora: 50 upgrades, implemented through Goal Mode

## Summary

Implement all 50 upgrades below in tested stages, balancing daily usefulness, planning, analysis, accessibility, and native integrations.

Create branch `nmapaye-bot/aurora-50-upgrades` from the inspected `abd8ded` baseline in an isolated `.worktrees/aurora-50-upgrades` worktree. Preserve the primary checkout.

Once execution is enabled, call `create_goal` with the objective of implementing and verifying this entire plan. No token budget was requested. Maintain a numbered progress ledger with implementation, review, and verification evidence for every feature.

## The 50 upgrades

### Logging and daily use

1. **Personal drink library.** Create, edit, and archive custom drinks with a name and caffeine amount. Keep the four existing presets unchanged.
2. **Favorite quick adds.** Select and reorder drinks shown on Summary and Log, with the same order on both screens.
3. **Serving calculator.** Calculate caffeine from servings or a label’s concentration and volume. Display the calculation before saving.
4. **Repeat an entry.** Copy a previous drink into a new draft with the current time and an editable amount.
5. **Undo recent changes.** Offer a ten-second undo for caffeine additions, edits, and deletions without overwriting subsequent changes.
6. **Recover unfinished entries.** Restore an unsaved caffeine draft after navigation or relaunch, with explicit discard.
7. **Search caffeine history.** Search drink names and notes across stored entries.
8. **Filter caffeine history.** Combine date, source, and amount filters, with a visible reset action.
9. **Record caffeine-free days.** Mark a day as explicitly caffeine-free so insights distinguish zero intake from missing records. A later dose clears that marker.
10. **Preview a dose’s effect.** Before saving, show the resulting daily total and estimated caffeine remaining at the planned bedtime.

### Sleep and routines

11. **Weekly sleep schedule.** Set bedtime and wake time for each weekday, including sleep that crosses midnight.
12. **Schedule exceptions.** Override one date for travel, weekends, or unusual work hours without changing the weekly schedule.
13. **Consistent bedtime projections.** Make Summary, Sleep, cutoff guidance, and notifications use the same next scheduled bedtime. Remove conflicting hardcoded checkpoints and cycle-based wake suggestions.
14. **Morning sleep journal.** Record subjective sleep quality and notes against a sleep episode. Store annotations separately from read-only Health records.
15. **Nap session timer.** Start, cancel, or finish a nap timer, then confirm the resulting manual nap entry. Relaunch restores the timer without automatically claiming sleep occurred.
16. **Sleep consistency view.** Show bedtime and wake-time variation against the selected schedule using recorded main sleep episodes.
17. **Sleep deficit history.** Display recorded sleep duration against the user’s target over time, with missing days shown explicitly.
18. **Sleep overlap review.** Flag overlapping sessions and offer correction for manual entries. Keep imported records read-only and avoid double-counting overlapping intervals.
19. **Searchable sleep history.** Search notes and filter by date, source, and main sleep versus naps.
20. **Wind-down reminder.** Offer an optional local reminder before the scheduled bedtime, with a configurable lead time.

### Planning and personal experiments

21. **Caffeine scenario editor.** Add hypothetical future doses and inspect their projected caffeine curve without changing intake history.
22. **Saved scenarios.** Name, reopen, edit, and delete hypothetical schedules.
23. **Scenario comparison.** Compare two scenarios against the same baseline, including total caffeine and estimated bedtime residual.
24. **Threshold crossing estimate.** Show when modeled caffeine falls below a user-selected level. Describe it as a mathematical estimate rather than a safe-to-sleep threshold.
25. **Half-life sensitivity view.** Compare the same scenario at three user-selected half-life values without changing the active preference.
26. **Gradual reduction planner.** Generate a daily target schedule from a user-entered starting amount, ending amount, and duration. Never log doses automatically.
27. **Daily caffeine budget planner.** Allocate the user’s chosen daily target across planned drinks and show unused or excess allocation.
28. **Focus-window comparison.** Let users mark a desired work interval and compare existing alertness-model projections across scenarios, without prescribing an optimal dose.
29. **Subjective alertness check-ins.** Save a timestamped 1–5 rating with optional notes, independently of reaction-test scores.
30. **Personal experiment journal.** Define a question and baseline/comparison dates, then review caffeine, sleep, check-ins, and vigilance results. Label results as descriptive observations.

### Insights and understanding

31. **Combined daily timeline.** Inspect caffeine, sleep, naps, check-ins, and vigilance sessions together.
32. **Interactive chart inspection.** Select a time to inspect corresponding caffeine and alertness values, with equivalent accessible controls.
33. **Weekday pattern comparison.** Compare recorded caffeine and sleep across weekdays, showing sample counts.
34. **Bedtime caffeine versus sleep view.** Plot estimated caffeine at sleep onset against the following recorded sleep duration, without causal claims.
35. **Vigilance history and details.** Browse completed tests and inspect reaction metrics, lapses, and false starts.
36. **Personal vigilance comparison.** Compare a test with the median of previous eligible tests and show the baseline sample count.
37. **Subjective versus measured alertness.** Pair check-ins with the nearest completed vigilance test within 30 minutes and display both measures without combining their scales.
38. **Data completeness view.** Show which days contain caffeine records, confirmed zero intake, sleep, and tests. Explain gaps before presenting comparisons.
39. **Weekly review.** Generate an on-device review of recorded changes, missing information, and progress against user-set targets.
40. **Explain each metric.** Add contextual explanations of inputs, units, assumptions, and missing-data behavior for forecasts and insights.

### Customization, data ownership, and native access

41. **Customizable Summary.** Reorder or hide metric cards, restore defaults, and preserve the existing walkthrough’s required content while it runs.
42. **Accessible chart tables.** Provide a text/table alternative for every chart, with Dynamic Type, VoiceOver labels, and non-color indicators.
43. **Reminder center.** Manage cutoff, wind-down, check-in, and weekly-review reminders together, including weekdays, quiet hours, and current permission status.
44. **Backup and restore.** Export a versioned JSON backup through the system share sheet. Import Aurora backups with validation, a preview, and explicit replace confirmation.
45. **Privacy and deletion controls.** Show stored record counts and delete selected local categories or all Aurora data after confirmation. Explain that local deletion does not delete Apple Health records.
46. **Home Screen widget.** Provide small and medium summaries of logged caffeine, modeled active caffeine, and the next planned bedtime, with timestamps and links into Aurora.
47. **Lock Screen widgets.** Offer compact caffeine and next-cutoff views, respecting a preference to hide personal values.
48. **Log-drink Shortcut.** Accept a saved drink or amount and open Aurora with a validated draft for confirmation.
49. **Status Shortcut.** Return today’s logged caffeine and the scheduled cutoff from a timestamped local snapshot, clearly reporting unavailable or stale information.
50. **Nap Live Activity.** Display the active nap timer on supported devices. Open Aurora to finish and confirm the nap, and end the activity when canceled or completed.

## Implementation approach

**Navigation and presentation.** Keep Summary, Sleep, Log, and Insights as the four primary tabs. Place planners and experiments in secondary screens reachable from Summary and Insights. Put drink management under Log and data/reminder controls under Settings. Continue the existing Health-style components and brand.

**State and interfaces.** Extend typed persisted state for personal drinks, drafts, confirmed zero days, schedules, annotations, nap timers, scenarios, plans, check-ins, experiments, and customization. Update `normalizePersistedState` and migration fixtures with every persisted addition. Preserve existing record IDs and source restrictions.

Keep calculations in pure domain modules with explicit time inputs. Separate hypothetical plans from recorded intake. Share calendar handling and projection inputs across screens, reminders, and native snapshots.

Add typed navigation routes and validated deep-link parameters for drafts and detail screens. Incoming actions wait until onboarding and the ten-step walkthrough permit them. Links never save records automatically.

**Analysis rules.** Exclude sample data from personal comparisons and exports by default. Do not interpret missing records as zero. Display sample counts with every comparison. Require five paired observations for paired summaries and three prior completed tests for personal vigilance comparisons. Keep the existing alertness formula unchanged and identify its outputs as model estimates.

**Native integration.** Add a WidgetKit extension and a small native service module to the manually maintained Xcode workspace. Use an App Group snapshot containing only the values needed by widgets and Shortcuts. The React Native app remains the sole writer of intake history. Use WidgetKit timelines for widgets and ActivityKit for the nap activity, following Apple’s [widget extension](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension) and [ActivityKit](https://developer.apple.com/documentation/activitykit) guidance.

Keep SwiftUI within the extension rather than embedding it in React Native screens. Guard unsupported APIs and provide an honest unavailable state in Expo Go. Never run `expo prebuild`.

**Delivery sequence.**

- Establish the baseline, migration foundation, shared clock/calendar logic, and feature ledger.
- Implement logging features 1–10.
- Implement sleep features 11–20.
- Implement planning features 21–30.
- Implement insight features 31–40.
- Implement customization and data features 41–45.
- Implement native features 46–50, then run whole-app verification.

Follow the repository’s sequential implementation and independent review workflow. Use fresh implementation subagents with red-green-refactor tests, then specification and code-quality reviews. Resolve findings before the next batch. Commit reviewed batches to the new branch.

## Verification and completion

Each numbered feature requires reachable UI, working persistence where applicable, relevant behavioral tests, and recorded acceptance evidence. A placeholder screen does not count as implemented.

Test migrations, malformed imports, backup round trips, undo conflicts, midnight and DST boundaries, schedule exceptions, missing data, sample-data separation, and read-only Health restrictions. Verify scenarios never enter intake history without a separate confirmed logging action.

Exercise notification denial, rescheduling, quiet hours, cold-start links, stale native snapshots, canceled timers, and interrupted walkthroughs. Check compact iPhone and wide iPad layouts, large text, VoiceOver focus restoration, and Reduce Motion.

Run Node 24 type-check, lint, Jest, iOS Expo export, and website checks. Require unsigned Debug and Release native builds plus physical iPhone/iPad checks for supported native features.

Full Xcode is currently unavailable in `/Applications`, and Command Line Tools are selected. Native verification remains pending until the required toolchain, signing capabilities, and devices are available. Continue all unblocked work and report these prerequisites explicitly. Goal Mode must not mark the objective complete while required native verification remains unfinished.

## Defaults and boundaries

- All 50 features are included. Implementation ends with a verified branch, without merging or publishing.
- No accounts, cloud sync, paid APIs, telemetry, Watch app, or HealthKit writes.
- New reminders and lock-screen data exposure default off.
- Existing users retain their preferences. The initial sleep schedule uses 22:30 and a wake time derived from their sleep-duration target until edited.
- Backups are explicitly labeled unencrypted local exports. Restore replaces local Aurora data only after preview and confirmation, and never restores OS permission grants.
- Preserve the exact ten-step walkthrough. Disable new data-changing actions during it.
- Add no claims of clinical accuracy, safe caffeine dosing, or guaranteed sleep or performance outcomes.
