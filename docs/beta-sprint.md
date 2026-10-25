# Aurora beta sprint — evidence and integration ledger

Updated October 25, 2026. **Day 1; NO-GO for public beta.** This is a local,
owner-review candidate, not a release approval. Days 2–5 have not been executed.
The checkpoint outside this repository is
`/Users/nmapaye/Documents/Aurora Audits/beta-sprint-progress.md`.

## Candidate and evidence

- Branch: `codex/beta-consolidation-2026-10-25`.
- Worktree: `/Users/nmapaye/Developer/aurora-beta-consolidation-2026-10-25`.
- Base: refreshed `origin/main`, `5a51696375d85e0ed1e84a191a573dc501d4e720`.
- Active evidence: `/private/tmp/aurora-beta-evidence-2026-10-25/`.
- Durable evidence: `/Users/nmapaye/Documents/Aurora Audits/beta-sprint-evidence-2026-10-25/`.
- Final app source: `24d36e5c`; core: `9050bad2`; capture tests: `8946ce90`.
  Earlier complete UI/native baseline: `253b0829`. Build provenance is retained.
- Installed toolchain: Xcode 27.0 (27A266a), per-command `DEVELOPER_DIR`.
  Global Xcode selection was not changed. Simulator runtime: iOS 26.5.
- All 48 prior worktrees, including dirty work, preserved. No pushes, remote
  merges, releases, account changes, force-pushes, or Grok messages.

Evidence receipts and result bundles take precedence over these summaries.
Temporary build output is not permanent archival storage; retain the selected
logs, receipts and result bundles with the external checkpoint before cleanup.

## Day 1 findings verified against current sources

All five requested October 24 audit reports were inspected. Live GitHub still
reports 22 open PRs; the recent fifteen consist of merged #47 and fourteen open
PRs. #51/#58 remain red on both devices; #61 remains red on iPad. Latest main
iOS run is a failure at `73199d4`, not evidence of green native tests at the
current documentation-only main tip. GitHub snapshots and all PR diff statistics
are retained as `pr-diff-inventory.md` and JSON in the evidence root.

Missing-night remains clean at original `6542b4c7`, nine commits ahead of its
base. Its original branch was not modified. The whole sequence is locally
integrated for testing. The current rule merges brief awakenings, clips ongoing
records to evaluation time, requires a block spanning three hours, and withholds
a score once its end is older than eighteen hours. These are display assumptions,
not clinical thresholds. Owner acceptance is still required. In particular,
reconcile them with #43's different episode rule before combining those branches.

The #54 force-push event exists at 2026-10-24 08:35:41 UTC under `nmapaye`.
The audit's account of lack of authorization is historical evidence; GitHub
alone establishes the event, not human intent. Current ruleset 25785331 blocks
main rewrites/deletion with no bypass. PR branches are outside that rule.
The release environment still permits admin bypass and self-review. No live
compromise or new credential exposure is established.

## Acceptance scorecard

P0 = compromise, unauthorized write/release, widespread crash or irreversible
data loss. P1 = a critical journey, safety, privacy, build, mandatory test or
distribution gate fails or lacks required acceptance. P2 = bounded degradation
with documented risk and explicit owner acceptance. P3 = optional polish.
Every open P0/P1 blocks beta; P2 acceptance cannot be inferred from this ledger.

| Gate derived from repository requirements | Severity | Evidence / status |
|---|---|---|
| Repeated clean launch, onboarding, completed-user relaunch | P1 | Clean Release phone/pad launch, setup, relaunch/background/native navigation pass; physical cold launch pending |
| Caffeine/sleep/check-in Save, Undo, duplicate taps, snapshots, CSV, offline tools | P1 | Earlier full suites pass 172 each; final native tests pass 132 each; actual CSV/device inspection pending |
| No-record and Sample Data truthfulness; alertness eligibility | P1 | 342 core tests pass UTC/LA; old implementation fails regression control; product acceptance pending |
| Corrupt/future storage preserved, migration, erase, interrupted work | P1 | Full fixture storage/erase suites pass; real prior-version device upgrade pending |
| Health separate opt-ins, exact sample ownership, confirmed export receipts | P1 | Core tests/source inspection; physical allow/deny/revoke/import/export/background matrix pending |
| Calendar preview approval and stale-data revalidation | P1 | Source validator and tests exist; live dedicated-event matrix pending |
| Google unconfigured means no requests; disconnect cannot restore credentials | P1 | #61 plus refresh/read generation fixes pass seven provider tests inside 132 native tests on each device; no real Google calls |
| CI, iPhone/iPad and repeated regressions all green at final head | P1 | Live PR gates remain red; full 172 per device and final native/gallery 134 per device pass; 40-iteration stress checks running |
| iOS 17+ compatibility, physical VoiceOver, largest text, Reduce Motion, background lifecycle | P1 | iOS 26.5 simulator Release/UI and largest-text captures pass; physical VoiceOver/motion/older-OS evidence pending |
| Reproducible installable distribution and signed archive validation | P1 | Two clean final unsigned archives at `24d36e5c` and strict artifact/privacy checks pass; signed archive/device upgrade/TestFlight unproven |
| Tester instructions, private feedback and support route | P1 | [Guide](beta-tester-guide.md) and bug template added; real TestFlight/support setup must be verified |
| Rollback, incident owner and non-destructive recovery | P1 | Procedure below prepared; owner rehearsal pending |
| Owner control of Git and release actions | P1 | Local safeguards added; external bypass/shared identity risks require owner action |
| Website build/dependency health | P2 | Type-check/build pass; npm audit reports zero known vulnerabilities in production and full locked tree |

Final validation caveat: a narrow Swift Testing method filter selected zero tests
while xcodebuild exited 0. `2f8ce603` adds an actual-xcresult guard (17 total
Python tests) to reject zero tests, skips and failures in CI. The real zero-test
bundle is rejected; the two 172-test bundles are accepted. The corrected whole-native-target
control executes 131 tests and fails exactly the refresh race assertions (four
issues), proving the old behavior restores credentials and sends a later API call. The first later-binary tests failed before
launch: SpringBoard explicitly reported the app/runner was still being updated.
Both signatures and deployment targets verified; boot-and-wait was omitted from
that local follow-up harness, unlike CI. Explicit boot-and-wait corrected the
launch precondition; final native/gallery and Release runs then passed on both
devices. The earlier failures remain retained, not relabelled as passes.

No P0 incident is currently confirmed. Passing unit tests alone cannot make
the recommendation GO. GO requires evidence for every mandatory row and owner
authorization; CONDITIONAL GO can apply only after all P0/P1 close and the owner
explicitly accepts each remaining P2 risk.

## Implemented changes

Existing work locally consolidated, with original history preserved:
#51 conversation reveal/follow fixes and annotations; #58 input diagnostics,
keyboard CI setup and stop-on-first-failure stress checks; #61 provider guard;
the nine missing-night commits; #48 simulator/device networking separation;
#55/#56 manifest/encryption verification; #52/#62 manual release and signing
configuration; and motion-test correction `98167927` from the earlier remediation
worktree. These are integration changes, not claims of newly authored work or
remote PR completion.

New fixes:

- `5b2b185c`: exact-commit executed CI checks required before signing/upload;
  skipped checks cannot satisfy a relevant native/core change; strict archive
  privacy/ATS checks; release-guard regression tests and CI job.
- `a4f37360`: verify the composer owns keyboard focus before typing; continue to
  reject partial requests. No test retyping or retry-until-green was added.
- `253b0829`: explain ongoing-sleep eligibility consistently in energy/summary
  copy, including accessibility, without changing the three/eighteen-hour rule.
- `24d36e5c`: discard late Google responses after disconnect and validate session/token before sending, closing the newly executed late-read regression.
- `2f8ce603`: reject zero-test/skipped/failed xcresult receipts in native, stress and Release smoke CI; 17 evidence-guard tests pass.
- `9050bad2`: distinguish the missing-night eligibility model in new estimates and projections, while preserving historical `alertness-1` snapshot values and schema. Compatibility tests pass in both zones.
- `60f9622a`: invalidate pending Google refresh/sign-in work on disconnect;
  expose credential-deletion failures; inject transport/storage for deterministic
  race tests that make no network requests or real credential writes.

## Test ledger

| Execution | Result | Evidence file under evidence root |
|---|---|---|
| Pristine-main core UTC | 326/326 pass | `baseline-core-utc.log` |
| Baseline simulator test build | Pass, ad hoc signed | `baseline-build.log` |
| Baseline iPad motion, long card, two typed flows | 4/4 pass; no local failure reproduced | `baseline-ipad.xcresult` |
| Baseline iPad long-card repeat, stop on failure | 10/10 pass; CI intermittency remains unresolved | `baseline-longcard-repeat-ipad.xcresult` |
| Candidate core, UTC and America/Los_Angeles | 342/342 each pass after provenance fix | `model-version-core-{utc,la}-final.log` |
| Missing-night regression tests with pristine-main Summary/EnergyEstimate | Expected red: 5 test functions, 9 issues; 24 tests run | `core-old-code-control.log` |
| Release and xcresult guards | 17 tests pass; actual zero-test bundle rejected; both 172-test bundles accepted | `evidence-guard-tests.log` |
| Workflow YAML and bash syntax | 7 YAML files / 38 shell bodies parse | `workflow-syntax.json` |
| Privacy source and unsigned archive | Pass, zero warnings | `privacy-source.log`, `privacy-archive.log` |
| Website type-check/build, locked dependency audits | Pass; 0 reported vulnerabilities | `website-*.log`, `website-audit-*.json` |
| Full simulator suites at `253b0829` | Phone and pad: 172 passed each (129 native + 43 UI), zero skipped. Later security/provenance changes require targeted final runs | `candidate-full-*-receipt.json`, `candidate-full-*.xcresult` |
| New disconnect-race red/green native tests | Old control: 131 executed, intended refresh test fails with four issues. Final native: 132 pass each device, including refresh/read/deletion regressions | `security-{red,fixed}-build.log` |

Unsigned archive metadata confirms bundle `com.nmapaye.aurora`, version 0.1.0
(1), iOS 17 minimum, iPhone/iPad families, embedded privacy manifest, encryption
exemption false, no device ATS exception, and no direct Google configuration.
It cannot be installed as a signed beta. No signed entitlements, HealthKit
device behavior, Organizer validation or distribution has been certified.

## Ordered backlog and PR integration recommendations

The following is a review order, not merge authorization. Every source SHA is
captured in the live PR snapshot. Re-run checks after conflict resolution at the
actual integrated head; a green check on another branch is insufficient.

| Priority / PRs | Disposition and dependency |
|---|---|
| P1 #51, #58 | Locally combined; require full suite and 40 stop-on-first-failure iterations on each device before accepting either as solved. Overlap in workflow edits resolved by keeping both stress steps and full tests after either failure. |
| P1 #61 | Guard and tests integrated; motion test correction reused; new disconnect fix additionally needs red/green evidence. Do not call the remote PR green. |
| P1 missing-night | Integrated for review; owner must accept 3h/18h, ongoing sleep, merged gaps and projection cutoff. Original branch remains untouched. |
| P1 #48 → #55 → #56 | Integrated locally; actual device archive inspected, not just simulator plist. #56 is stacked on #55. |
| P1 #52 → #62 | Integrated locally, with additional exact-commit evidence guard; no workflow dispatch or signing material accessed. #62 is stacked on #52. |
| P1 #54, #60 | Ratify Apple-only release scope and reconcile reviewer/privacy statements with actual unconfigured archive; #60's claims depend on #61, not copy alone. Existing main docs still call Google a requirement. |
| P1 #42, #43 | Review model/default/notification acceptance before integration. Both based on #38; #42 still has a red iPad gate. #43 modifies the sleep model and snapshot versioning and must be reconciled with missing-night. |
| P2 #38 → #39 → #44 | Large UI, reaction and accessibility stack; not duplicates of narrow #51/#58 fixes. Reconcile shared files first. Physical touch/VoiceOver remains mandatory if adopting it. |
| P2 #40, #41 | Research #40 can be reviewed independently; #41 changes caffeine kinetics and depends on #38. Do not add a new model merely to consolidate inventory. |
| P2 #50, #53; #59 integrated | Reconcile overlapping website/Health/reaction/notification copy once with #42/#43. #53 includes functional changes, not only prose. #59's isolated calendar write-disclosure correction is integrated as `767a0d82`. Support availability needs an actual check. |
| P2 #57 | Records deferred widgets and beta structure; owner ratifies scope, no widget implementation in this candidate. |
| P3 #31 | Conflicting Plus/IAP PR; inconsistent with paid-upfront/no-IAP v0.1.0. Recommend park/close after owner review; no close performed. |

No PR was marked obsolete simply because it is old. #51/#58 and the remediation
motion commit address related symptoms; their useful deltas were reused rather
than spawning another agent or replacing their histories.

## Known issues requiring explicit owner acceptance

- **P2 / Codex technical follow-up:** the passing phone bundle retains three “Invalid frame dimension (negative or non-finite)” SwiftUI runtime warnings in cutoff result/reminder flows. No failing assertion or crash accompanies them. Source location is absent; cause is not established. Do not silently accept them for beta. Owner acceptance or a verified fix is required.
- **Test infrastructure:** Xcode’s end-of-run diagnostics collector could not resolve `simctl` under global Command Line Tools selection, despite per-command Xcode selection. The xcresult bundle and executed tests were retained. Do not change the machine-wide setting without owner direction; use explicit tool paths and retain this evidence limitation.

## Security findings and exact owner actions

- **P1, mitigated locally:** release workflow lacked a head-specific evidence
  preflight. New guard requires completed successful native/core/security/privacy
  checks and rejects skipped results before any signing key is installed.
- **P1, fix pending test:** disconnect could restore OAuth credentials after a
  successful late refresh. Generation invalidation now covers disconnect and
  successful sign-in callbacks; credential deletion failure is surfaced.
- **P1, externally open:** a shared owner GitHub identity cannot distinguish bot
  approval from human approval. Use a separate scoped bot/app principal without
  merge/release-approval permissions. The owner retains the release reviewer role.
- **Proposed ruleset, not applied:** active branch ruleset with
  `conditions.ref_name.include=["~ALL"]`, no exclusions, `bypass_actors=[]`,
  and `rules=[{"type":"non_fast_forward"}]`. This extends rewrite protection
  to PR branches. Review branch creation and maintenance needs before applying.
- **Proposed release environment change, not applied:** after separate requester
  identity is in place, set `can_admins_bypass=false`, `prevent_self_review=true`,
  retain owner reviewer `User:206962697`, wait timer 0 and main-only deployment
  policy. With only one requester/reviewer identity, self-review prevention would
  block releases; do not apply it blindly.
- **Reviewed protections:** source uses backup-excluded protected local storage,
  preserves corrupt/future files and migration originals; Health writes constrain
  source/sync identity; calendar actions revalidate approval and revisions;
  Google credentials use device-only Keychain protection; signposts use fixed
  names rather than private contents. Fixture tests do not certify device behavior.
- Actions are pinned by commit; Swift package has no remote package dependencies;
  website lockfile audit is clean. Local CodeQL was not executed. Isolated checksum-verified Gitleaks 8.30.1 scanned 48 sprint commits with full redaction and no leaks.
  Final-head hosted secret/security scans remain required. Historical SSH-key
  alert stays closed as documented in `agents.md`.

## Rollback and incident procedure

1. The owner records approved commit, build number, archive, dSYMs and results
   before any distribution. Keep the previous accepted archive and its schema
   compatibility evidence. No accepted signed baseline is established yet.
2. For a suspected crash, data loss, unauthorized write or private-data exposure,
   stop expanding tester access. Owner/technical responder triages using build,
   device, OS and redacted reproduction; use the private channel in `SECURITY.md`
   for security findings. Preserve logs and originals. Do not request live Health
   records, tokens, calendar details or conversation dumps in public issues.
3. The owner may stop invitations/expire the affected TestFlight build and choose
   an already validated compatible build or a forward fix. These external actions
   require explicit approval; no automation here performs them.
4. Prefer a focused `git revert <bad-commit>` on a repair branch, then rerun the
   mandatory suite and issue a higher build number after owner review. Never
   force-push or rewrite main. Do not downgrade over newer stored schemas, erase
   app data, delete Health exports or restore a snapshot without explicit consent
   and a verified recovery plan. Aurora deliberately refuses newer state versions.
5. Reopen access only after the regression has a red/green test, the final build
   passes acceptance, and the owner records the incident resolution. A simulator
   pass cannot substitute for physical Health/migration verification.

## Validation details and limits

`AuroraReleaseSmoke` exercises optimized Release without Debug reset/gallery
hooks or testability overrides. The first ordinary Release test-build attempt
failed because its native unit target requires Debug fixtures; it is retained as
a failed attempt. The dedicated UI-only scheme keeps that target separate from
the mandatory full Debug suite. Actual clean install/setup, energy card,
relaunch, background return and responsive native navigation pass 1/1 on each
simulator, with the nonzero result guard confirming no skips/failures.

Final `proof-native-gallery-{iphone,ipad}` bundles each pass 134 tests (132
native plus both strengthened capture tests). Visual review confirmed phone
numeric-keyboard Save and the long-card heading. It found older largest-text
“result” images still showed inputs; `9a58d203` / `8946ce90` now require the actual
result heading (Calculate for empty inputs) on screen. Both devices pass that
stricter check, and a final phone largest-text result image was inspected.

The temporary portable control with the exact `ConversationReveal.swift` fails
on pristine main and passes integrated source (`conversation-control-{old,fixed}.log`).
This is logic proof, not local reproduction of the intermittent CI renderer race.
The original missing-night control and Google refresh control fail as intended.
The later native run additionally caught stale calendar data after disconnect;
`24d36e5c` fixes it and all seven provider regressions pass on both simulators.

Actual final unsigned archives are 5/6 at app source `24d36e5c`. Both independent
clean archive commands and strict privacy checks succeed; embedded Info.plists
and privacy-manifest hashes match. This is build-procedure reproducibility, not
bit-for-bit executable equivalence or signed distribution. Physical iPhone/iPad
are listed as unavailable. No signed archive, device HealthKit, Organizer,
TestFlight upload or external installation has been certified.

`stress40-{iphone,ipad}` run serially against app `24d36e5c` and stop on failure.
They require forty actual passes of each long-card/briefing/trends flow and a
nonzero, clean xcresult. The worker updates the external checkpoint and preserves
results. These long runs are **pending**, not passed. Check the checkpoint before
starting any new simulator lane. Earlier binaries/archives retain their original
source labels in `BUILD-PROVENANCE.md`.

## Remaining day boundaries

Only October 25 Day 1 is claimed executed. Critical fixes, integration/security
preparation and Release simulation advanced early. Day 2 closes any remaining
stress/CI defects; Day 3 completes the owner-chosen integration/security deltas;
Day 4 supplies physical and complete end-to-end evidence; Day 5 prepares the
signed owner-reviewed candidate and final gate decision without publishing.
Unelapsed days, owner decisions and unexecuted tests remain open.
