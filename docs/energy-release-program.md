# Expanded Aurora release program

User-approved 2026-10-09. All packages below gate the first App Store release (v0.1.1),
except widget gates, which apply to v0.1.2 (owner decision 2026-10-24).
Versions renumbered 2026-10-30 (owner): the launch build is v0.1.1 after the beta fixes, and
widgets move to v0.1.2; earlier dated entries keep their meaning.
Starting checkpoint: 85a3ddb on codex/native-assistant, clean before work.
Legacy PR #19 is unmerged; remote Actions-analysis and gitleaks jobs were cancelled
with no executed steps (2026-10-05), not reported code/security findings. JS analysis passed.
Keep the legacy PR separate; no push, merge, account enrollment, or publication
occurs during local implementation.

## Ownership and isolation

Claude implements each bounded package in an isolated branch from the latest accepted
integration checkpoint. This user assignment overrides older UI-only ownership text
for the package's expressly assigned files. Codex orchestrates, reviews diffs, runs
independent checks and visual inspection, and integrates only accepted local commits.
No simultaneous UI runners or same-file edits; preserve original checkouts.
Claude subscription only, no API keys or alternate billed provider on exhaustion.

## Locked contracts

- Local deterministic calculations/actions; models classify a finite intent catalog.
- Energy is modeled, not measured or clinically validated. Preserve score baseline.
- Capture time/model version/time zone/input provenance/missing assumptions accompany
  snapshots; Refresh makes a new snapshot. Never invent future sleep or caffeine.
- Health: separate sleep-read, caffeine-read and caffeine-write choices; imported
  records read-only, optional export only of user-saved Aurora caffeine. Empty reads
  do not prove permission. Never identity-deduplicate on timestamp and amount.
- Local save and Health export report separate outcomes. Pending write retries use
  durable identity; edit/Undo deletes/replaces only own samples. Full local erase
  cancels reads/observers/outbox and leaves Health exports unless separately approved.
- Cutoff scenarios use a user-entered bedtime/threshold and chosen half-life; no
  recommended threshold/dose/sleep schedule. Reminder changes require Save.
- Refresh coalesces bounded foreground/observer/background work, invalidates stale
  results, honors quiet hours/daily limits/dismissal, never continuous reasoning.
- Widgets (v0.1.2) open review drafts; neutral Lock Screen defaults, metrics opt-in. Minimal
  protected App Group snapshots, stale labels, no calendar mutation or silent logs.
- Shared design.md/tokens; no fabricated speed, battery or accuracy claims.

## Packages and evidence ledger

| Package | Status | Required evidence |
|---|---|---|
| Foundation | Reviewed/integrated; original UI flows verified in combined Health checkpoint | 103 core UTC/LA baseline; 43 foundation native; combined 16/16 phone/pad UI pass |
| Health | Integrated including largest-text correction 8de9c0f; physical/live gates open | 165 baseline core UTC/LA; final combined Energy native 58/58 phone/pad; Health reachability flows pass; unsigned Release/site/tokens pass |
| Energy | Locally integrated at 85ecd49 after independent review; full release acceptance remains open | 186 core UTC/LA; 58 native phone/pad; pad UI 20/20; phone UI 19 full plus corrected 1 focused; light phone/pad and dark phone inspected; expanded accessibility/variant/device matrix pending |
| Planning/history | Pending | User-defined cutoff preview/reminder; impossible/past/DST scenarios, sparklines, protected edits/Undo |
| Widgets/performance | Pending; widgets deferred to v0.1.2 by owner decision 2026-10-24 | v0.1.1: local signposts and physical profiling (no widget extension in the v0.1.1 binary). v0.1.2: extension/App Group protection, routing/redaction/erase |
| Release polish | Pending | Gallery all states, serial phone/pad flows, screenshot critique, policies/metadata/website consistency |

## Release acceptance

Core UTC/Los_Angeles; native services; phone/pad serial UI; model-unavailable/offline
requests; migration/corrupt/future-schema recovery; notification/observer cancellation;
calendar authority/stale approval/partial outcomes; website/token checks/remote CI.
Visual matrix: light/dark, largest text, VoiceOver, Reduce Motion, keyboard,
orientation, Stop/failure/background; use dedicated fixtures, not personal records.

Hardware gates: Health allow/deny/revoke/import/export,
signed archive/privacy audit, real previous-version upgrade, dictation/background,
control feedback <100 ms, scrolling/animation/thermal/battery, verified support URLs
and contact, TestFlight feedback. No App Store submission without final authorization.

Beta structure (owner-approved 2026-10-24, "Yes"): v0.1.1 has no public wave-2 link.
The CPO exit criteria (at least 14 days of wave 1, at least 10 feedback testers, zero
data-safety bugs, CTO-verified migration, at least 80% comprehension with n of 8 or more)
gate App Review submission. Wave 2 becomes the invite-only v0.1.2 widget beta,
starting from the wave-1 panel.

## Resume instructions

Check clean status and latest accepted commit. Inspect Claude's handoff and commits
before cherry-picking. Do not count self-reported/partial/interrupted checks as passes.
Temporary Claude foundation output: /private/tmp/aurora-foundation-claude.json.
Worktree: /Users/nmapaye/Developer/aurora-energy-foundation.

## Overnight usage control (2026-10-09)

User confirmed the pause threshold is **15% remaining**, meaning the primary
five-hour meter reaches 85% used. Check the live account meter before expensive
stages; do not consume a banked reset. The attached `aurora-overnight-usage-guard`
checks every 15 minutes and resumes this task if the supervisor's queue fails.

Durable controller files live in `/Users/nmapaye/Developer/aurora-overnight/`:
`handoff.md`, `packages.json`, `supervisor.py`, `status.json` and per-package logs.
The Python supervisor was dry-run verified and started under process-scoped
`caffeinate -i`. It waits for `HANDOFF_READY` before dispatching Claude, also waits
for the active-writer marker/current foundation result, and never merges its
provisional package commits. The local queue is scheduled for **05:50 PDT**, after
the live meter's reported **05:46:04 PDT** reset. Actual queue delivery remains
unverified until it occurs; the heartbeat is the fallback.

Keep the Mac powered on with Codex running. `STOP` in the controller directory
cancels future dispatch/resumption, without discarding a running package's work.
At morning resumption pause the overnight guard, inspect the supervisor status,
and independently review each provisional commit before integration. A Claude
quota/authentication failure is a durable stop, never an API fallback.

Foundation `4b899bf` plus review correction `7abc32e` are integrated as `9a6c9c5`
and `3952667`. Older caffeine evidence/sample labeling, third-party Health identity
and migration restore failures now have regressions. Independent results: 103 core
tests in UTC/Los Angeles, 43 native phone tests and unsigned Release pass. Full
phone UI has an intermittent trend assertion failure; isolated rerun passed,
but full acceptance is still open. Pad native/UI run is in progress.
Claude's Health task is now isolated at `/Users/nmapaye/Developer/aurora-health-native`;
the controller's `workspace.json` is authoritative. Its commits require review.
