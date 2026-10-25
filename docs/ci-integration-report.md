# Aurora CI and integration report

Snapshot: 2026-10-25. Worker scope: CI/integration only. No simulator was launched,
terminated, reset, or reconfigured; no release or Pages deployment was dispatched.

## Isolation and initial state

- Repository: `nmapaye/aurora`; original checkout `/Users/nmapaye/Developer/aurora`.
- Initial original branch: `main`; HEAD `a59e6486939c468e2d4116751a6fc2f2bdba509c`.
- Initial original status: untracked `.expo/`, `HANDOFF-2026-10-13.md`, `ios/`;
  no tracked changes. Existing worktrees were enumerated before creation.
- Requested commit exists: `09433a6651fe1f1385b640158e1ff15d7e53988b`.
- Proposed path and branch were unused. Created `/Users/nmapaye/Developer/aurora-ci-integration`,
  branch `codex/ci-integration`, clean at exactly that commit.
- The requested starting point already contains 58 commits / 55 changed files
  relative to remote main. This is a consolidated beta candidate, not a narrow
  substitute for any original PR. Existing PR branches remain untouched.
- All local artifacts: `/private/tmp/aurora-ci-integration/`; Xcode DerivedData
  and Swift scratch paths are separate. Xcode selection was per command only.

## Merge and review policy verified live

- Active ruleset `10983290`: required `Swift Core gate` and `iOS App gate`,
  code-quality errors blocked, no force-push/deletion. Strict up-to-date checks
  are not enabled. Classic protection endpoint returns 404 because rulesets apply.
- Ruleset `25785331` separately prohibits default-branch rewrite/deletion with
  no bypass. No bypass was used and no protection setting was changed.
- `.github/CODEOWNERS`: `* @nmapaye`. No ruleset currently enforces approving
  PR reviews, but individual PR descriptions/comments impose additional reviews.
- All 22 open PRs were inspected; none has an approving GitHub review. Review
  thread query found no unresolved threads. An empty review list does not prove
  CTO/CPO or human owner sign-off; shared owner-account comments are not assumed
  to be independent human approval. No self-approval was submitted.
- #51 explicitly awaits CTO re-review and owner review. #59 requires CTO and owner;
  #60 requires CTO, CPO, then owner. #50 still awaits CTO re-review. #52/#53 comments
  explicitly request CTO re-review. Do not wake or message those reviewers.

## Prioritized queue and observed failures

| Priority / PR | Exact evidence and disposition |
| --- | --- |
| P1 #51 @44497f6a | Run 40118089191: long-card stress failed on iPad iteration 1 (line 570); iPhone iteration 6 (line 572). This is not failedSaveShowsNoReceipt. Required iOS gate red; CTO/owner reviews absent. Consolidated starting point retains reveal/follow fixes and both device stress gates. |
| P1 #58 @306b24ef | Run 40119537631: iPhone briefing iteration 28 failed composer validation; its later diagnostic shows the full expected text, so this alone does not prove lost keys. iPad trends iteration 7 failed setup at line 17. Both full suites also failed long-card visibility. Draft; keyboard pinning alone is not proved sufficient. Candidate additionally waits for composer focus and requires exact iteration counts. |
| P1 #61 @5f3cc77c | Run 40121856355: iPad testGalleryMotionFixtureEndsAndStaysStatic, Working/light assertion, line 783. Google provider tests were not the failing case. Candidate retains the asynchronous fixture-state wait plus Google configured/request guards and disconnect generation defenses. Still needs integrated hosted checks and review. |
| P1 #48 @bc1379ba | Run 40078245781: cutoff failed-save test cannot reveal Add bedtime, button y=-80.3. Helper always dragged up even for targets above viewport. Worker repair below. iOS gate remains red on original PR. |
| P1 #55 @5a22cc75 → #56 @227ea092 | #55 run 40078582372: briefing/reminders UI failure; artifact-based dropped-key diagnosis remains a lead, not this worker's reproduction. #55 draft/red; #56 draft/stacked on #55. Privacy/encryption guards already integrated in starting point. |
| P1 #52 @1850b2cc → #62 @866492c4 | Both green in current GitHub snapshot. #52 explicitly depends on CI fix then #48 and CTO re-review; #62 targets #52 branch. Signing config integrated in starting point, alongside stronger exact-commit release evidence guards. Account/secrets/device acceptance remain owner work. |
| P1 #54 @c86b15ad, #60 @197590a5 | Green; Apple-calendar privacy/reviewer changes integrated in candidate. #60 explicitly requires CTO/CPO/owner review. Reconcile any remaining copy with #50 before merge; no publication performed. |
| P1 #42 @aad57360 | Run 38991191929: same iPad Working/light motion assertion (line 955). Draft, based on #38; notification/model scope requires product review. Not added to candidate merely to clear inventory. |
| P2 #53 @316a60a0 | Green; explicit CTO re-review outstanding. Functional and copy changes, dependency on #39/#42/#43 and #50 conflict resolutions; do not merge as a trivial copy-only patch. |
| P2 #59 @73be0f64 | Green; small calendar disclosure fix already integrated in candidate. Explicit CTO and owner review absent. |
| P2 #50 @78be5a40 | Green; comments record prior privacy/CPO sign-off, but CTO re-review remains outstanding. Conflicts/metadata overlap with #53/#54; retain approved copy. |
| P2 #38 → #39 → #44; #41/#43 on #38 | All draft and green in snapshot. Preserve stacked bases; #43 model rules conflict with owner-approved missing-night rules. Feature ownership/review required, not independently merge-ready. |
| P2 #40 @ef92b2d2 | Green research-only PR, no GitHub approvals; ready to present for owner review. It proposes model/product decisions; merging docs does not authorize implementing them. |
| P2 #57 @9d50c46a | Green draft release-program document, no GitHub approvals; owner scope ratification remains. |
| P3 #31 @f0dd8940 | Conflicting Plus/IAP branch; paid-upfront/no-IAP beta scope mismatch. Park for owner decision; do not resolve by adopting IAP or close without direction. |

## Worker changes and validation

Inherited repairs are attributed to the requested starting commit, not claimed
as newly authored here. They combine both repeat steps, run the full suite after
either repeat fails, use a 180-minute job budget, verify nonzero clean xcresults,
and enforce exactly 40 passed endings per stress case with no failures/skips.

New worker changes:

1. `CutoffScenarioUITests.reveal`: require the control below the navigation bar
   as well as above the composer/quick-action area; drag down when the control is
   above the viewport and up when below it. Keep the final visibility/hittability
   assertion. No test disabled, assertion weakened, or product behavior changed.
   This addresses the confirmed helper defect; hosted execution must still prove
   the scenario passes.
2. Four annotation regression tests use actual CI signatures. Passing Swift
   Testing cases with `.failed` argument values must produce no error, while real
   XCTest/Swift Testing/compiler failures remain annotated and escaped.
   Against original main, 2/4 fail; against candidate, 4/4 pass.

Checks executed by this worker:

- Swift Core: 342 tests / 41 suites pass in UTC and America/Los_Angeles.
- CI/release/result guard Python tests: 38 pass.
- Privacy manifest / encryption verification: pass, zero errors/warnings.
- Native design-token and Apple-only beta scope checks: pass.
- Website clean dependency install, TypeScript check, Vite production build: pass.
- Isolated generic simulator `xcodebuild build-for-testing`: TEST BUILD SUCCEEDED;
  app, native tests and UI test targets compiled without launching a simulator.
- Changed Swift test syntax check and `git diff --check`: pass.
- Local iOS execution/stress: deliberately not run; simulator lane belongs to the
  other development session. Existing historical receipts are not fresh evidence.

## Integration disposition and default branch

Merged PRs: none. Merge hashes: none. No inspected PR with an explicit outstanding
CTO/CPO/owner review was treated as approved because checks were green.

Default branch verified live: `5a51696375d85e0ed1e84a191a573dc501d4e720`.
Its check runs include successful CodeQL (Actions, JS/TS, Swift) and gitleaks;
there are no Swift Core gate or iOS App gate check runs attached to that exact
commit in the initial snapshot. Do not describe the default branch as fully green.
No dependent merge will proceed until required current-commit evidence is present.

Next action: obtain hosted full iPhone/iPad plus 40-iteration receipts for the
consolidated worker candidate, then resolve any newly observed failure before
requesting final owner review. Preserve all original PRs and feature-session
worktrees. Pending checks/reviews and physical beta acceptance remain blockers.

Hosted candidate: pending creation; final URL/status will be recorded below.
