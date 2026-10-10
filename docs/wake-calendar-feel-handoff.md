# Wake reminders, source-styled calendar, copy cuts and touch feel

Branch `claude/aurora-wake-calendar-feel` from accepted `56ecb12`. Requested by
Nathan on 2026-10-10 after a Q&A. Local only; nothing pushed. Awaiting Codex review.

## Decisions Nathan made

- **Wake reminders are the person's own timing.** They pick offsets after waking
  (e.g. +1 h, +5 h); Aurora detects the wake-up from recorded sleep, falls back to
  their usual wake time, and never fires at or after their own cutoff. Aurora does
  not recommend timing or claim "maximum impact"; the no-prescription rule stands.
- **Calendar matches the source app.** Google events look like Google Calendar's
  schedule, Apple events like Apple Calendar. Duplicates across providers: the most
  recently updated copy wins.
- **Remove almost all disclaimers.** Keep only honesty labels (Sample Data,
  Modeled/Estimate, read-only, Health pending/not exported, failures) and the
  medical disclaimer in Settings.
- **Satisfying taps:** haptics on every tap, springy presses, instant response,
  a save moment.
- Device testing with his free Personal Team (team `72DC9RVDYJ`, passed on the
  command line only; no project signing change).

## Commits

| SHA | What |
|---|---|
| `6706302` | Core `WakeReminders` planner + `Prefs.wakeReminders` (optional, no schema bump), `ReminderService.syncWake`, AppModel re-planning on foreground/background refresh/Health sleep change/manual sleep edit, erase cancels. Setup step `.wakeReminders = 6`, `.finish = 7`. |
| `9bc6368` | `PressFeedback`/`.auroraPress`: 96% spring + soft haptic on touch-down for every custom control; `SavedBadge` draws its check in with a success haptic when a draft turns Saved on screen. |
| `9ea9983` | `WakeReminderEditor` (offset chips, usual wake time, live "Next" preview), setup controls, Settings → Wake reminders (Save to apply; asks notification permission only on explicit opt-in). |
| `70c6bf7` | `Commitment` gains optional `location`, `colorHex`, `lastModified`, `allDay` (both providers fill them identically on every read, so the approval stale check still holds). `CalendarMerge.newestCopies`. New card: Google solid color blocks, Apple color bar on tint, grouped by day, shorter move review. |
| `2861c57` | Copy cuts across cards, setup, story, settings; capture line shows just the time today. |
| `842ed6e` | Reminders card leads with "Caffeine after waking" + next reminder + Set up/Change. |
| `f758775` | **Responsiveness fix (pre-existing bug):** notification remove calls and Apple model availability no longer run synchronously on the main thread. |
| `1d38f0c` | Gallery calendar fixtures (both sources, one duplicate), single-line chips, design.md/agents.md rules. |

## The main-thread freeze (please review closely)

On a freshly booted simulator, finishing setup froze Aurora for 54 s to over
2 min. `sample` of the app during the freeze showed the main thread in
`AppModel.foregroundSync → ReminderService.sync →
UNUserNotificationCenter.removePendingNotificationRequests →
xpc_connection_send_message_with_reply_sync`. Baseline `56ecb12` freezes the same
way (probe log `build/logs/stall-base.log`). Removals now run detached
(`ReminderService.remove`), including the briefing notification; model
availability is checked once off-main and cached (`AssistantModel.modelAvailable`),
and keyboard prewarm uses the cached value. Cold-boot probe after the fix: setup
finish → composer 1.6 s in three runs (`build/logs/stall4.log`).
Not changed (Codex's code): `LocalDataDeletion` still removes notifications
synchronously during erase; same risk, behind a loading screen.

## Checks actually run

- Core `swift test`: 233/233 in UTC and America/Los_Angeles (after copy cuts);
  final run on `1d38f0c` is in `build/logs/final-core-*.log`.
- Full iPhone suite on dedicated "Aurora Welcome iPhone" (iPhone 18 Pro, iOS 27.0),
  ad-hoc signed, serial, at `842ed6e`: AuroraTests 76/76, AuroraUITests 32/32
  (includes new `testWakeRemindersChosenInSetupShowInTranscriptAndSettings`).
- Final runs on `1d38f0c`, serial, ad-hoc signed, dedicated simulators:
  core 233/233 UTC and Los Angeles; iPhone ("Aurora Welcome iPhone") AuroraTests
  76/76 and AuroraUITests 32/32; iPad ("Aurora Welcome iPad", iPad Pro 13-inch M5)
  AuroraTests 76/76 and AuroraUITests 32/32. Logs: `build/logs/final-*.log`
  (git-ignored, in this worktree).
- Visual review light + dark (`build/cap-{light,dark}/`): calendar gallery,
  setup reminder step, Reminders card. Fixed: gallery fixture branch, wrapping chip.
- Signed Debug build for Nathan's iPhone 13 with the Personal Team succeeded
  (HealthKit entitlements kept). Not installed: the phone was disconnected.

## Not verified / open

- Real wake detection timing on a device. HealthKit background delivery is hourly,
  so a recorded wake-up can arrive up to ~1 h late; reminders within 30 min of
  their time still fire, older ones are skipped, and the usual-wake fallback covers
  mornings with no data. Needs a week of real use to judge.
- Notification delivery while the app is suspended, permission denial UI on device.
- Google color uses the calendar list color; per-event `colorId` is ignored.
- Haptic feel and spring tuning on hardware; VoiceOver pass of new controls.
- Reminders card still shows each setting as a metric row and a toggle (core card
  metrics); worth a follow-up trim.
- UI tests touching setup: `finishSetup()` uses Skip all and is unaffected; the
  step-by-step test now expects the reminder question after calendars.
