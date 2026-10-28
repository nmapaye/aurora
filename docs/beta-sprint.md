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
- Latest validated binary: app `24d36e5c`; core `9050bad2`; capture tests `8946ce90`.
  New beta-scope copy/UI assertions require a new build and final-suite evidence.
  Earlier complete UI/native baseline: `253b0829`. Build provenance is retained.
- Installed toolchain: Xcode 27.0 (27A266a), per-command `DEVELOPER_DIR`.
  Global Xcode selection was not changed. Simulator runtime: iOS 26.5.
- All 49 other baseline worktrees, including dirty work, preserved (fresh HEAD/status comparison retained). No pushes, remote
  merges, releases, force-pushes or Grok messages. The only external change was
  owner-approved private-reporting enablement; verification is retained.

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
not clinical thresholds. The owner explicitly accepted these display assumptions on October 25.
Do not combine #43's competing episode/model rules into this beta.

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
| No-record and Sample Data truthfulness; alertness eligibility | P1 | 342 core tests pass UTC/LA; old implementation fails regression control; display assumptions approved; physical-data verification pending |
| Corrupt/future storage preserved, migration, erase, interrupted work | P1 | Full fixture storage/erase suites pass; real prior-version device upgrade pending |
| Health separate opt-ins, exact sample ownership, confirmed export receipts | P1 | Core tests/source inspection; physical allow/deny/revoke/import/export/background matrix pending |
| Calendar preview approval and stale-data revalidation | P1 | Source validator and tests exist; live dedicated-event matrix pending |
| Google unconfigured means no requests; disconnect cannot restore credentials | P1 | #61 plus refresh/read generation fixes pass seven provider tests inside 132 native tests on each device; no real Google calls |
| CI, iPhone/iPad and repeated regressions all green at final head | P1 | Live PR gates remain red; full 172 per device and final native/gallery 134 per device pass; 40-iteration stress checks running |
| iOS 17+ compatibility, physical VoiceOver, largest text, Reduce Motion, background lifecycle | P1 | iOS 26.5 simulator Release/UI and largest-text captures pass; physical VoiceOver/motion/older-OS evidence pending |
| Reproducible installable distribution and signed archive validation | P1 | Two clean final unsigned archives at `24d36e5c` and strict artifact/privacy checks pass; signed archive/device upgrade/TestFlight unproven; ASC signing secrets absent at both repository/environment scope |
| Tester instructions, private feedback and support route | P1 | [Guide](beta-tester-guide.md) and bug template added; Private reporting enabled with owner approval and GET verified true; actual TestFlight/support setup pending |
| Rollback, incident owner and non-destructive recovery | P1 | Procedure below prepared; owner rehearsal pending |
| Owner control of Git and release actions | P1 | Local safeguards added; external bypass/shared identity risks require owner action |
| Website build/dependency health | P2 | Type-check/build pass; npm audit reports zero known vulnerabilities in production and full locked tree |

Final validation caveat: a narrow Swift Testing method filter selected zero tests
while xcodebuild exited 0. `2f8ce603` adds an actual-xcresult guard (26 total
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
- `2f8ce603`: reject zero-test/skipped/failed xcresult receipts in native, stress and Release smoke CI; current evidence-guard suite has 26 passing tests.
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
| Release and xcresult guards | 26 tests pass; actual zero-test bundle rejected; both 172-test bundles accepted | `evidence-guard-tests.log` |
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
| P1 #61 | Guard and tests integrated; motion correction reused; disconnect refresh/read fixes have executed red/green evidence. Do not call the remote PR green. |
| P1 missing-night | Integrated for review; owner accepted 3h/18h and ongoing-sleep assumptions; preserve merged gaps, clipping and historical model versions. Original branch remains untouched. |
| P1 #48 → #55 → #56 | Integrated locally; actual device archive inspected, not just simulator plist. #56 is stacked on #55. |
| P1 #52 → #62 | Integrated locally, with additional exact-commit evidence guard; no workflow dispatch or signing material accessed. #62 is stacked on #52. |
| P1 #54, #60 | Apple-only beta scope approved. Reconcile reviewer/privacy statements with the guarded unconfigured archive; retain #61 provider defenses. Direct Google remains deferred, and competing main docs are corrected locally. |
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

- **P1 configuration blocker resolved with owner approval:** private reporting was disabled despite SECURITY.md. The owner explicitly approved enablement; PUT succeeded and fresh GET verified `enabled: true` on October 25 at 15:02:58 UTC. `59220039` adds fail-closed release verification. No report was submitted; notification delivery/response is not certified.


- **P1, mitigated locally:** release workflow lacked a head-specific evidence
  preflight. New guard requires completed successful native/core/security/privacy
  checks and rejects skipped results before any signing key is installed.
- **P1, fixed and tested locally:** disconnect could restore OAuth credentials after a
  late refresh or expose late calendar data. Generation invalidation now covers
  refresh, read and sign-in callbacks; credential deletion failure is surfaced.
  Red controls fail as expected; all seven provider regressions pass on both simulators.
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
TestFlight upload or external installation has been certified. Read-only signing
metadata confirms a valid development identity for the Aurora team and an
existing HealthKit profile expiring October 30 at 05:23:54 UTC. A local signed
archive attempt is awaiting macOS key access; it does not enable provisioning
updates. Both repository and release-environment secret-name lists are empty:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, and `ASC_KEY_P8` are absent. No secret values were
read. Owner setup is required for the TestFlight workflow; no upload was attempted.

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

Stress correction: the original combined iPhone run was interrupted without a
final receipt. Its log has 40 briefing and 40 long-card passes, then an unfinished
trends case; last write was 10:53:52 UTC and no worker/Xcode process remained at
15:04 UTC. Cause is not established. These are partial observations, not an active
or accepted complete run. A detached finite worker started at 15:13 UTC with per-test/process time
bounds and live PID/heartbeat state (`stress-worker-state.json`, PID 41632).
It runs one simulator lane and stops at the first failure; all six per-flow
receipts must pass before accepting the repeat gate.
The original log and incomplete bundle are preserved; no app assertion failure
is being rerun until green.

Iteration acceptance was strengthened after finding CI only printed counts.
The guard now requires exactly forty actual passed case endings for every
selected stress method, with no failures. Its real-bundle control accepts the
preserved ten-pass run when ten are required and rejects it when forty are
required (`iteration-guard-control.json`). All 26 guard tests and 38 workflow
shell bodies pass local checks. This change does not rebuild the app binary.


## Concrete owner review actions (prepared, not executed)

- Review `git diff 5a516963..codex/beta-consolidation-2026-10-25` and the source-specific evidence above. The candidate is not approved for merge or distribution.
- When ready to authorize hosted verification, the exact proposed push is `git -C /Users/nmapaye/Developer/aurora-beta-consolidation-2026-10-25 push -u origin codex/beta-consolidation-2026-10-25`. This creates/updates only the new branch. No push, PR creation, protected merge or workflow dispatch has been performed by this sprint.
- The owner must configure `ASC_KEY_ID`, `ASC_ISSUER_ID` and base64-encoded `ASC_KEY_P8` directly in the protected GitHub `release` environment, choose a scoped App Store Connect key, and confirm account/team/App Store Connect app eligibility. Do not paste key contents into a public issue or chat. Existing local development signing is not TestFlight distribution signing.
- Owner decisions recorded: tested missing-night display assumptions accepted; Apple-synced-calendar-only beta approved; physical iPhone and iPad will be made available. Physical Health, accessibility, migration and installed-build tests still need execution with dedicated fixtures.
- Review the exact proposed force-push/ruleset and release-environment changes above. Only the separately approved private-reporting enablement has been applied.


## Approved beta scope implementation

The owner approved Apple-synced calendars only, the tested missing-night display
assumptions, and availability of both physical device families. App connection
copy, product truth, unpublished metadata, website/privacy source and tester
instructions now reflect that scope. HealthKit descriptions distinguish the
three separate opt-ins and Aurora-owned caffeine export; they no longer claim
the whole integration is read-only. No Google implementation or defensive test
was removed. Eight new scope-guard tests reject Google client/callback keys and
Google OAuth URL schemes, including malformed metadata. CI checks source plists,
the built device plist and the archive before upload. Current Python guard suite
has 34 passing tests; the retained final unsigned archive also passes the scope
check. The existing calendar UI test now verifies reachable Apple connection controls and the
absence of direct-Google connection actions without requesting permissions.
Its new assertions are pending execution, not passed evidence. The prior full
suite queue is superseded with a rebuild of this changed app/test source;
ongoing old-source stress receipts remain explicitly labelled.

The local development-signed archive attempt timed out (exit 124) at 15:40:22
UTC while waiting at codesign/SecurityAgent. No accepted signed archive or
installation resulted. The failed manual-profile attempt and timed-out corrected
attempt are retained separately; no Keychain permission workaround was used.


## Safe website verification

Website Demo previously deployed whenever manually dispatched, even from a
non-main branch. It now defaults to build-only; deployment requires explicit
`publish: true` on main. No dispatch or publication was performed. The exact-SHA
release preflight additionally requires the uniquely named `Website build` check.
For a documentation-only release commit, manually dispatch Core, iOS App and
Website Demo with publishing off at that same commit; never use a publishing
workflow as a build probe. This preserves the existing explicit publication
path and environment while preventing accidental publication during validation.
