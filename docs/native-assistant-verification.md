# Verification — October 8, 2026

- Swift core: 54 tests passed in UTC and America/Los_Angeles, including existing
  TypeScript parity fixtures and assistant/calendar policy regressions.
- Native storage/service tests: 16 passed on each isolated simulator.
- UI flows: 5 passed on iPhone 18 Pro and iPad Pro 13-inch (M5). Covers
  onboarding, conversation without tabs, explicit Save/Undo, native tools,
  disconnected calendar review, and absence of API-key entry.
- Debug simulator build and Release simulator build succeeded.
- Local Gemma 4 26B: 10/10 synthetic intent cases passed; warm requests roughly
  0.45–0.48 seconds. This measures classification, not end-to-end phone latency.
- Apple Foundation Models: the native simulator successfully classified
  “Could you help me understand my sluggishness today?” and returned the
  deterministic missing-data energy explanation. Processing ended afterward.
- Largest accessibility text size inspected in the isolated iPhone simulator;
  conversation remains scrollable, controls reachable. Final icon sizing uses
  fixed glyph sizes with labeled 44-point touch targets.

Source logs are in `/private/tmp/aurora-assistant-core-{utc,la}.log`,
`/private/tmp/aurora-assistant-tests.log`,
`/private/tmp/aurora-assistant-ipad-tests.log`,
`/private/tmp/aurora-assistant-release.log`, and
`/private/tmp/aurora-local-acceptance.json`. They are ephemeral local evidence,
not product telemetry. The reusable evaluation script is checked in.

Pending: public Google OAuth registration and live account tests; physical
HealthKit, microphone/dictation, VoiceOver, Reduce Motion, background scheduling,
touch latency, scrolling/frame rate, battery usage, signing/archive/TestFlight.
No personal calendars were changed and no credentials were created or entered.
No cloud inference occurred. Existing Aurora worktrees retain their original
heads (`a04b3dc`, `fed770d`, `165707e`).

## Input prewarming and classification cache

The follow-up Release simulator build passed. All 19 native storage/service
and cache tests plus the 5 UI flows passed on the isolated iPhone simulator.
Cache regressions cover exact request/model isolation, five-minute expiry,
least-recently-used eviction, clearing, and unsupported-response exclusion.
Logs: `/private/tmp/aurora-assistant-cache-tests.log` and
`/private/tmp/aurora-assistant-cache-release.log`.

The input-focus prewarming path compiles against the installed Apple SDK.
Its actual cold/warm latency, cache hit rate and energy impact are not measured;
use the Foundation Models instrument on physical hardware before making speed
claims. Cached classifications always route through fresh action validation
and deterministic records/time calculations.

## Interactive conversation cards: final pass (October 8, 2026)

Checkpoint `5078901` on `codex/native-assistant` captured the card work; the
fixes below are on `claude/aurora-ui-polish`, verified on the isolated
"Aurora Assistant iPhone" and "Aurora Assistant iPad" simulators (iOS 27.0).

- Swift core: 61 tests passed in UTC and America/Los_Angeles.
- Native storage/service/card tests: 31 passed on each simulator, including
  `briefingRefreshReadsCalendarsAndKeepsPriorSnapshot` and
  `interruptedReadBecomesRefreshableFailureAfterRelaunch`.
- UI flows: 13 passed on each simulator, run serially
  (`-parallel-testing-enabled NO`); parallel clones intermittently stalled in
  CoreSimulator creation.
- Release simulator build succeeded.

Fixes:

- Largest accessibility text: the composer inset (hint, quick actions,
  composer) did not scroll and covered most of an iPhone screen, so sent
  requests showed no visible reply. The inset now caps Dynamic Type at
  `accessibility1` and drops the hint line at accessibility sizes; messages
  and cards still scale fully. Covered by
  `testLargestAccessibilityTextKeepsCardsAndComposerReachable` (AX XXXL).
- `PrimaryButtonStyle` read `isEnabled` from a style wrapped by
  `AnyButtonStyle`, which always reads the default, so disabled primary
  buttons in onboarding could render as enabled. It now reads it in a view.
- `OnDeviceDictation.stop()` deactivated the audio session on every send and
  scene change, even when dictation never started, blocking the main thread.
  It now deactivates only a session it activated.
- UI test stability: history empty-state check waits instead of reading once;
  the send helper retries if the keyboard moved the button before the tap
  (sending clears the field, so a retry cannot send twice).

Reduce Motion: the edge glow, activity indicator and auto-scroll all branch
on `accessibilityReduceMotion`; all 13 UI flows passed with Reduce Motion
enabled on the iPhone simulator (restored to off afterward). Animation
smoothness under Reduce Motion was not judged visually.

Logs: `/private/tmp/aurora-polish-core-{utc,la}.log`,
`/private/tmp/aurora-polish-iphone-final.log`,
`/private/tmp/aurora-polish-ipad-final.log`,
`/private/tmp/aurora-polish-iphone-reducemotion.log`,
`/private/tmp/aurora-polish-release.log`.

Still pending: physical-device VoiceOver, Dynamic Type and Reduce Motion
pass; live Google OAuth and EventKit accounts; HealthKit; dictation; background
refresh; performance and battery; signing, archive and TestFlight.

## Correctness and integration (October 8, 2026)

Code checkpoint: `d35407a` on `codex/native-assistant`. This combines
`0693f22` (deterministic drink-source fixes) with reviewed Claude commits
`e972a68` and `605d6d7`, cherry-picked as `4f225b5` and `d35407a`.
Claude's worktree remains clean at `605d6d7`.

- “Usual coffee” considers repeated Coffee, Espresso, Drip, and Cold Brew
  records only. Explicit drink types use matching history. Sample, future,
  and records older than 30 days are excluded. Insufficient matching history
  leaves the proposed amount empty; explicit amounts still override history.
- Source-only corrections such as “Actually tea” and “Actually coffee”
  preserve the draft's amount, timestamp, and note. An unrelated history
  request is not treated as a correction. Corrections never save a record;
  explicit Save is still required.
- Integrated core: 64 tests passed in UTC and America/Los_Angeles.
- Integrated iPhone: all 32 native tests and 13 UI tests passed, including
  the source-correction Save guard and AX XXXL card/composer reachability.
- Integrated iPad: all 32 native tests and 13 UI tests passed, run serially
  after the iPhone suite. Includes AX XXXL, history, briefing, exports, reaction
  test access, and proposal expiry across relaunch.
- Integrated unsigned Release simulator build succeeded.
- The integrated Release build was installed and launched on the isolated
  Aurora Assistant iPhone. Device Hub visibly shows the native trends card,
  Snapshot + Refresh, quick actions, and composer. No global developer-tools
  switch or sudo command was needed to open that window.

Evidence: `/private/tmp/aurora-integrated-core-{utc,la}.log`,
`/private/tmp/aurora-integrated-iphone.log`,
`/private/tmp/aurora-integrated-ipad.log`, and
`/private/tmp/aurora-integrated-release.log`. These are temporary local test
artifacts; no conversation, health, or calendar telemetry was uploaded.

Earlier interrupted runs reported UI-runner SIGKILL/SIGTERM and failed
bootstrapping while other Xcode jobs used the same simulator. A later serial
run also exposed a history empty-state timing assertion, addressed by Claude's
wait-for-existence change. Interrupted and failing runs are not counted as
passes. Use one UI-test job at a time and separate build directories when
collaborating on this Mac. Global `xcode-select` was not changed; CLI checks
set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` per command.

No changes to the record or conversation schemas, model providers, or calendar
approval rules were needed. No credentials were entered, live calendars mutated,
pushes performed, or releases published. The other original worktrees remain
at `b0d1419` (`aurora`), `fed770d` (`aurora-premium`), and `a04b3dc`
(`aurora-design`). The physical-device and live-account release gates above
remain open.


## Aurora flowing motion — 2026-10-08

- Replaced hardcoded rainbow decoration with shared sea-glass teal, mint,
  and muted indigo tokens. Processing bands travel around the perimeter,
  varying width, length, and brightness. A subdued ribbon lives beside the title.
- Animation timelines are created only for active scenes without Reduce Motion.
  The perimeter remains bound to actual `assistant.processing`; no model,
  record, calendar, card, or storage behavior changed and no artificial delay was added.
  Decorations ignore touches and are hidden from accessibility.
- Release simulator build passed. The conversation-home and AX XXXL
  card/composer tests passed on both iPhone and iPad (2/2 per device, serial).
  Evidence: `/private/tmp/aurora-flow-release.log`,
  `/private/tmp/aurora-flow-iphone.log`, `/private/tmp/aurora-flow-ipad.log`.
- Inspected Release layouts in light and dark appearances on both devices,
  including real local-model processing on iPhone and completion clearing
  the perimeter. Status text and Stop remain readable. Reduce Motion was
  enabled through simulator Settings; its static title identity was inspected,
  then the preference was restored to off (confirmed through simulator defaults).
- Manual verification is incomplete for the static processing perimeter,
  Stop/failure transitions, software-keyboard-open visuals, and background
  transitions. Code review confirms timer removal/static rendering branches
  and the unchanged processing lifecycle, but these are not claimed as visual passes.
  Device Hub stopped exposing embedded app accessibility controls after UI tests,
  limiting further manual interaction. Physical-device smoothness, VoiceOver,
  and battery measurements remain release gates. No speed or battery claim is made.

## Conversation Apple Health connection — 2026-10-08

- Added a Connect Apple Health quick action and exact typed connection shortcuts.
  They open a focused review sheet using the existing sleep status and connection
  service. Opening the sheet does not request authorization; Connect to Health
  remains an explicit user action. Access remains sleep-only and read-only.
- The focused reachability UI test passed serially on iPhone and iPad (1/1 each).
  Release simulator build passed and was installed on the isolated iPhone.
  Device Hub inspection confirmed the disclosure and Connect control; no Health
  permission was granted during inspection.
- Evidence: `/private/tmp/aurora-health-shortcut-test.log`,
  `/private/tmp/aurora-health-shortcut-ipad.log`, and
  `/private/tmp/aurora-health-shortcut-release.log`.
- Physical-device entitlements, authorization, and live sleep import remain
  release gates. Record storage and inference behavior are unchanged.


## Release integration and erase recovery — 2026-10-08

Checkpoint: Claude's card polish is preserved at `26396c2`. Its isolated website
pass (`d715e66`) was reviewed and integrated as `f715b54`. This subsequent local
integration commit adds recovery, verification and release drafts; nothing is pushed.

### Erase diagnosis and protection

The full-erase failure was reproduced in the isolated simulator: account cleanup
returned Keychain status **-34018** (missing entitlement). Unsigned simulator tests
cannot validate Keychain deletion. Ad-hoc simulator signing (`CODE_SIGNING_ALLOWED=YES
CODE_SIGN_IDENTITY=-`) fixes that setup without a Developer account, production
bypass, or swallowed credential error. CI uses this configuration for tests and
retains a separate unsigned Release build check. Earlier failures are not passes.

Deletion now records durable intent before cleanup, resumes before loading records
or importing retained originals, reports the failing stage/status, verifies empty
record read-back, and removes the pending marker last. Retries are idempotent. Only
Aurora-owned files/credentials/reminders are removed. Record-only deletion remains
separate and accurately described. Generation guards discard late Health, calendar,
OAuth exchange and reminder results after full erase. Isolated dependency injection
permits deterministic failure tests while production failures remain explicit.

### Completed combined checks

| Check | Actual result |
|---|---|
| Core, UTC | 64/64 passed |
| Core, America/Los_Angeles | 64/64 passed |
| Native services/cards, iPhone | 39/39 passed |
| Native services/cards, iPad | 39/39 passed |
| iPhone UI, serial | 16/16 passed |
| iPad UI, serial | 16/16 passed |
| Focused erase → onboarding → relaunch | Passed using actual signed-simulator cleanup |
| Unsigned Release | Build succeeded |
| Ad-hoc signed Release demo | Built, installed and visibly running on isolated phone/pad |
| Website | Production build and synthetic-preview interactions passed |
| Compatible website lockfile updates | npm audit: 0 known vulnerabilities at verification time |
| Design-token check, workflow YAML, privacy plist, diff whitespace | Passed |

Seven deletion tests cover owned/unrelated files, interrupted relaunch, retry,
credential failures, real empty Keychain/notification cleanup and delayed calendar
results. UI coverage includes largest accessibility text and the retained Debug-only
synthetic Design Gallery. Receipt times now use snapshot time zones; conversation
width uses the shared token, and decorative symbol transitions respect Reduce Motion.

Evidence (temporary local files): `/private/tmp/aurora-final-core-utc.log`,
`/private/tmp/aurora-final-core-la.log`, `/private/tmp/aurora-final-iphone.log`,
`/private/tmp/aurora-final-ipad.log`, `/private/tmp/aurora-final-release.log`,
`/private/tmp/aurora-final-demo-build.log`,
`/private/tmp/aurora-website-final-audit.json`. Phone xcresult:
`/private/tmp/aurora-signed-simulator/Logs/Test/Test-Aurora-2026.10.08_19-32-11--0700.xcresult`;
pad xcresult:
`/private/tmp/aurora-signed-ipad/Logs/Test/Test-Aurora-2026.10.08_19-37-43--0700.xcresult`.

### Visual and publication limits

Manually inspected the combined Release's phone caffeine card in light/dark and
iPad centered clarification/trends column in light appearance. Restored phone
appearance to System. Device Hub's embedded app accessibility tree was incomplete
after testing; coordinate inspection confirmed rendering separately. Largest text
is covered by the passing automated flows. Full current-checkpoint manual Reduce
Motion, keyboard and appearance matrix remains open, along with physical VoiceOver,
animation smoothness, control latency, thermal and battery measurements. Source
review and earlier motion checks are not substitutes for those acceptance results.

Privacy/support and store/beta drafts now describe the native assistant, local AI,
optional Google network access, explicit calendar approval and full erase. Claude's
website removes the obsolete tab demo, dose recommendations and purchase claims;
its interactive preview is explicitly synthetic and does not create real records.
Support contact: nmapaye@outlook.com (owner approved 2026-10-24). Deployed policy/support URLs remain required.
No website was deployed. Remote CI has not run. Apple enrollment, signed hardware
archive, production Google OAuth, live Health/calendar/dictation/background tests,
real prior-version upgrade, TestFlight and App Review remain separate release gates.
Other checkouts and personal records remain untouched.
# Expanded energy foundation — 2026-10-09

Local integration checkpoint `3952667` includes reviewed Claude foundation
`4b899bf` and correction `7abc32e`. Cards/layout remain unchanged; this is the
evidence/provenance/migration/provider-interface foundation, not complete Health
or energy UI delivery.

- Independent core: 103 tests pass in UTC and America/Los_Angeles.
- Independent native services/migration/erase: 43 tests pass on isolated iPhone,
  ad hoc simulator signing; `/private/tmp/aurora-energy-foundation-native.xcresult`.
- Unsigned Release simulator build passed.
- Serial iPhone UI: 15/16 pass; `testTrendsSwitchSignalsAndRange` failed at the
  Month heading assertion. Unchanged isolated rerun passed (1/1); rendered
  screenshot showed the Month reaction chart. Root cause remains intermittent.
  Heading assertions now wait for the updated elements; full recheck is pending.
- Serial iPad: native 43/43 and UI 16/16 passed; result bundle
  `/private/tmp/aurora-energy-foundation-pad.xcresult`.
- Morning iPhone retries on the existing isolated device failed during runner
  startup before tests executed. These runs establish no app regression or pass.
  A fresh dedicated QA iPhone passed native 43/43 and UI 15/16. The caffeine
  Save/Undo flow failed again in isolation: the whole-app swipe hit the fixed
  quick-action strip, leaving Save beneath the keyboard inset. Finishing source
  editing with Return and checking keyboard dismissal/Save reachability passed
  the affected flow (1/1). The updated full suite remains pending. Demo devices
  and data are retained.
- Website type-check/build and brand-token check passed at the morning checkpoint.
- New package hardware/Health writes/observer delivery remain unverified.

Review corrections preserve calculation constants, fix older contributing caffeine
evidence/sample status, retain snapshot inputs, exclude metadata-only ownership
claims, preserve unmatched Aurora exports as read-only Health data, and make
failed migration restoration explicit with retained source intact.

Logs/results live under `/private/tmp/aurora-energy-foundation-*` and
`/private/tmp/aurora-energy-trends-repro.xcresult`; trend screenshot is
`/private/tmp/aurora-energy-trends.png`. One simulator runner at a time.

# Health integration — 2026-10-09 morning

Reviewed Claude commits `4731aaa`, `ca93efc`, `595a525` individually and
cherry-picked as `6ae7647`, `7eff4d8`, `e589df6`. The Health worktree is clean
and stopped. Source/provenance, local-first receipts, separate choices, bounded
anchored reads, explicit corrupt-anchor recovery and sleep-change policy are
implemented; physical Health behavior remains unverified.

Independent checks on the integrated branch:

- Core: 164/164 in UTC and America/Los_Angeles.
- iPhone: native 51/51 and UI 16/16, serial, including erase/relaunch and
  Save/Undo after the keyboard interaction correction.
- Website type-check/build and brand-token check passed.
- Unsigned Release simulator build passed and opened on the demo phone.
- iPad combined native 51/51 and UI 16/16 passed. The original largest-text
  flow passed after 445 seconds with runner animation-idle waits; this is not
  evidence of physical-device speed.
- Health connection sheet inspected in light/dark: separate read sleep, read
  caffeine, own-caffeine export and background choices; no permission requested.
  Screenshots: `/private/tmp/aurora-health-release-choices-{light,dark}.png`.

Evidence: `/private/tmp/aurora-health-integrated-{utc,la}.log`,
`/private/tmp/aurora-health-integration-phone.xcresult`,
`/private/tmp/aurora-health-integration-pad.xcresult` (pending), and
`/private/tmp/aurora-health-integration-release.log`.

Remaining Health release gates: signed physical-device allow/deny/revoke and
write-only lookup, sample ownership/version reconciliation, background delivery,
permission/failure/pending UI variants at largest text and VoiceOver. Simulator
fixtures do not establish those outcomes. Settings privacy-row copy still needs
the optional writes described; `.hourly` is a requested opportunity, not a
promised wake schedule. Energy UI, planning/history and widgets are not delivered.

## Health cancellation correction

An independently added held-page test failed before the fix: cancelling its
refresh task still applied the held page and fetched more data. Read paging now
checks task cancellation/current read state before each fetch and after the await,
retaining only already-committed pages and anchors. Core 165/165 passes in UTC
and America/Los_Angeles; the same fixture subsequently resumes to all six records.
Logs: `/private/tmp/aurora-health-cancellation-red.log` and
`/private/tmp/aurora-health-cancel-{utc,la}.log`. Native checks below must be rerun
for this final code checkpoint; earlier 51/16 results remain earlier evidence.

## Final morning Health service and accessibility follow-up

A native rerun exposed a fixture race: its old AppModel still had an automatic
export dispatch while a second model simulated relaunch. The tracked MainActor
dispatch now chains queued record exports, can be awaited, and is cancelled by
data deletion with generation checks before external work. The relaunch fixture
awaits its original dispatch; its duplicate-write assertion remains unchanged.
A new native test confirms deletion before a dispatch starts writes nothing.

- Final native: 52/52 on phone and iPad;
  `/private/tmp/aurora-health-final-native-phone.xcresult` and
  `/private/tmp/aurora-health-final-pad.xcresult`.
- New largest-text Health UI: 1/1 phone and iPad. Scrolls to each separate
  control, verifies unchanged off values, and closes the sheet. These focused
  runs add coverage to earlier 16/16 suites; a combined 17-flow suite was not run.
- Final unsigned Release passed: `/private/tmp/aurora-health-dispatch-release.log`.
- Visual finding remains open: the horizontal switch row splits “background”
  as “back-ground” at accessibility XXXL. Claude must stack label and control
  using full available width, preserving permission and accessibility semantics.
  Screenshot: `/private/tmp/aurora-health-large-phone-attachments/` (manifest).
- Claude reached its subscription quota before changing Energy; session
  `4b25b22a-bd2d-4e29-8100-8ea37b6377d8` is preserved. One-time follow-up
  `aurora-energy-reset-resume` runs at 10:55 AM after the reported 10:50 reset.
  Overnight usage guard is paused. No billed fallback or banked reset used.

No pushes, publication, signing identity/profile changes or live account setup.
All real Health/account/device/performance/signing/TestFlight gates remain open.

The five native HealthSyncAppTests passed ten repetitions each, including the
previously flaky relaunch and new pre-dispatch deletion case. Evidence:
`/private/tmp/aurora-health-relaunch-repeat.xcresult` / `.log`.

## October 9, 11:23 AM Pacific: Energy provisional review

Health-only Claude commit `458dd4b` was reviewed separately and accepted as
`8de9c0f`: accessibility labels now use full width with the native switch beneath,
permission/disabled behavior is preserved, and background delivery/privacy copy is
accurate. Largest-text Health UI test passed; screenshot visually confirmed whole-word
“background” and reachable controls with all choices still off.

Energy implementation `1b2b561` and handoff `3efd5e6` remain provisional. Independently
ran 183 core tests in UTC and America/Los_Angeles (both pass), brand tokens (pass),
and 58 native tests on the isolated phone with ordinary simulator ad-hoc signing
(pass). The initial unsigned native run failed real Keychain deletion with -34018;
ordinary simulator signing resolved it without identity/profile configuration changes.

Focused phone UI: check-in Save/Undo, missing-data Energy curve, and largest-text
Health passed; Energy gallery failed before card selection because the test expected
exact “Experience” while the AX label was “Experience, caffeineDraft”. This 3/4 run
is not a complete acceptance pass. No pad Energy or final Release acceptance yet.

Requested bounded Claude corrections: align the new headline/evidence/current curve
inputs when sleep records extend beyond capture; avoid routing unrelated N/5 ratings
to energy check-ins; give the gallery picker a stable test selector. Existing scalar
algorithms and compatibility fixtures must remain unchanged. Claude is active in its
isolated tree; no Energy integration until corrections and independent reruns pass.

Evidence: `/private/tmp/aurora-energy-review-core-{utc,la}.log`,
`/private/tmp/aurora-energy-review-signed-native-phone.xcresult`,
`/private/tmp/aurora-energy-review-focused-phone.xcresult`, and exported screenshots
under `/private/tmp/aurora-energy-review-attachments/`. Physical-device and live
Health acceptance remain release gates. No push/publication or signing changes.

## October 9, 11:46 AM Pacific: corrected Energy acceptance

Reviewed Claude correction `6a3972f` individually: new cards consistently exclude
unfinished/future records from headline, metrics and curve; unrelated ratings no longer
route deterministically to check-ins; gallery has a stable test selector.

Codex found a signed-rating bug: “-2/5” became positive 2. A regression against the
actual planner failed with six expectations before the fix; local candidate commit
`7d81d7c` preserves the sign and leaves off-scale ratings unspecified. Independent
core tests now pass 186/186 in UTC and Los Angeles. Scalar compatibility remains intact.

Phone candidate acceptance: 58/58 native tests pass. Full UI run: 19/20 pass; caffeine
Save/Undo failed tapping an offscreen Return button in a simulator keyboard preview
(the source field was focused and contained Tea). Test-only correction `2d0183e` sends
Return to the focused source field; the unchanged Save/Undo assertions then pass in a
focused 1/1 rerun. This is 19 full-run passes plus one focused rerun, not a single
combined 20/20 result. The corrected gallery and full erase/relaunch pass.

Unsigned Release and token check pass. Visually inspected the populated phone Energy
gallery screenshot: solid modeled line, dashed projected line, current marker, sleep
band and separate caffeine marks are visible. Health largest-text screenshot preserves
whole words and reachable switches. Dark, broader Energy variants and physical
accessibility/performance remain unverified.

Full iPad native/UI runner is active, serially after phone stopped. Do not overlap it.
Energy remains provisional until remaining checks finish; only Health visual polish
is integrated. Evidence: `/private/tmp/aurora-energy-signed-core-{utc,la}.log`,
`/private/tmp/aurora-energy-negative-rating-before.log`,
`/private/tmp/aurora-energy-final-phone.xcresult`,
`/private/tmp/aurora-energy-keyboard-phone.xcresult`,
`/private/tmp/aurora-energy-final-pad.log`, and
`/private/tmp/aurora-energy-final-release.log`.

## October 9, noon Pacific: Energy integrated locally

Energy implementation and handoff were reviewed individually, followed by bounded
corrections and Codex regressions. Original commits 1b2b561, 3efd5e6, 6a3972f,
7d81d7c and 2d0183e integrate as 2c0d9d9, f2eda0b, 66224bc, 730e923 and
85ecd49 respectively. Health visual correction was already accepted at 8de9c0f.
Candidate and integrated source trees are identical except this verification document.

Independent candidate verification: 186 core tests in each UTC/Los Angeles run;
58 native tests on each phone/pad; iPad full serial UI 20/20. Phone full run 19/20,
plus corrected remaining Save/Undo flow 1/1 separately. Do not represent that as
one combined 20/20 phone run. The final pad suite includes the parser/harness fixes.
Unsigned candidate Release and integrated token checks pass. Ordinary simulator
ad-hoc test signing was necessary for the real Keychain dependency; no signing
configuration, identity or profiles were changed.

Visual evidence: populated Energy projection inspected on light phone and iPad;
centered iPad width, solid modeled/dashed projected line, current marker and separately
labeled observations are readable. Dark phone projection and check-in inspected.
Health largest-text correction inspected previously. Largest-text Energy/check-in
inspection remains incomplete: the QA text size changed, but Device Hub scroll/drag
did not reliably move through the gallery. Restored QA light appearance/standard size.
Check-in repeats its descriptive source sentence; nonblocking polish follow-up.

Release gates remain: complete Energy variant/accessibility/motion visual matrix,
physical VoiceOver/touch/animation/battery, live Health/Google permission and data
behavior, signed-device upgrade, support/OAuth/signing and TestFlight. Planning/history
and widgets/performance packages are not implemented. Local integration is not a
release approval. No push, publication, live accounts, personal-data erase or banked
reset occurred.

Evidence: /private/tmp/aurora-energy-signed-core-{utc,la}.log;
/private/tmp/aurora-energy-final-phone.xcresult;
/private/tmp/aurora-energy-keyboard-phone.xcresult;
/private/tmp/aurora-energy-final-pad.xcresult;
/private/tmp/aurora-energy-final-release.log.

Integrated unsigned Release build passed at noon and was installed without erasing
the demo simulator. Initial cold launch showed only a blank screen; a normal terminate/
relaunch restored the conversation, and opening the new energy-curve card rendered
the truthful missing-data state. This startup observation requires follow-up; do not
claim cold-start acceptance from this demo. Evidence: integrated Release log at
/private/tmp/aurora-energy-integrated-release.log and Device Hub inspection.

## October10 overnight reliability acceptance

Reviewed and integrated individually:8b85c65→dacf9ed, b221170→b1c2c55,813c4a2→c4af855,e622637→48e2ed8,4130a3a→0c7269a. Integrated tree matches tested candidate4130a3a before this documentation update.

Codex independently verified:
- Core189/189 in UTC and America/Los_Angeles. Logs `/private/tmp/aurora-night-codex-core-r2-{utc,la}.log`.
- Native60/60 on iPhone and iPad, including lifetime teardown and per-card focus ownership. Original runtime crash was reproduced and its stack identified the unowned AppModel callback during asynchronous Health reconciliation. Retry completes without that crash.
- Focused iPhone keyboardUI1/1; focused iPad keyboard and Save/UndoUI2/2. Serial runs, no simultaneous UI runners. These are focused checks, not a new full-suite pass. Bundles `/private/tmp/aurora-night-codex-reliability-r2.xcresult` and `/private/tmp/aurora-night-codex-reliability-pad.xcresult`.
- Keyboard screenshots inspected on both devices: complete44pt Save above composer and software keyboard; quick actions collapsed while editing, explicit Save produced receipt and restored quick actions.
- Unsigned Release build succeeded, `/private/tmp/aurora-night-codex-release.log`. Brand-token and whitespace checks pass.
- Fresh Release installed in new disposable simulator1E142134-1060-476E-B548-133545EFF174, no existing demo/record erase. First launch visibly reached onboarding. Fixed-name signposts show calendar setup9ms, storage4ms and OnboardingVisible about166ms after initial marker. These simulator observations are not physical-device latency claims. Screenshot `/private/tmp/aurora-night-cold-first.png`, log `/private/tmp/aurora-night-cold-first.log`. Prior blank demo launch is not reproduced here and no speculative root cause/fix is claimed.

Remaining overnight checks: adapted onboarding and polish, full serial iPhone/iPad suites on final combined build, light/dark/largest text/Reduce Motion, completed-user cold launch and background-return behavior. iPad composer width is wider than card column in capture; send to polish package for shared-width treatment. Physical/live/accessibility/performance/signing/TestFlight/publication gates remain open. No pushes or global configuration changes.

## October10 onboarding acceptance

Reviewed sourcecommits5dea303,6d15da5,807039d,f8152d5,aac442b,f698213 individually, integrated as3d99705,9c6a72f,e0ac522,4203aa9,462c550,10cd37c. Tree identical to independently testedf698213 before this verification update. Optional setup fields decode from old storage without changing record/schema formats. Setup outcomes prevent fabricated user replies; answer+progress and finish/sample actions save atomically and preserve the step on failure.

- Core216/216 in UTC and Los Angeles; `/private/tmp/aurora-night-onboarding-core-r2-{utc,la}.log`.
- Native68/68 on iPhone and iPad, including failed setup writes and retries; focused correctedUI4/4 on each device: global skip leaves no invented answers, sleepNotnow retains stored target as Aurora note, largesttextHealth controls request no permissions, held welcome releases conversation immediately on tap. Bundles `/private/tmp/aurora-night-onboarding-r2-{phone,pad}.xcresult`.
- Prior candidate807039d passed five focused iPhone flows including erase/relaunch, story/resume, keyboardSave and largesttextcomposer; these are prior-candidate evidence, not a new full combined acceptance run.
- Phone and pad heldwelcome/Health-largesttext screenshots inspected under `/private/tmp/aurora-night-onboarding-r2-{phone,pad}-captures`. Health controls andNotnow visible, controls remain separate from scrollable conversation; welcome uses readable teal/mint/indigo identity.
- Independent unsignedRelease and brandtoken/whitespace checks pass. Release log `/private/tmp/aurora-night-onboarding-release.log`, with standard AppIntents metadata warning (no dependency).

Final fullserial suites, light/dark/ReduceMotion and representative error/gallery visuals remain after polish. VoiceOver, older supported systems, physical-device performance/battery/accessibility, liveHealth/calendar, signing and TestFlight remain release gates. No push/publication/live account setup or personal record erase.

## October 10 combined premium-demo acceptance

Claude polish candidate `9e84717` was reviewed commit by commit and integrated as:
69842e2→45b3984, 94ec4bc→71c0f73, b7b2fb4→1e23128,
50ec451→9763d23, c4762ed→0c3a8f9, 83ce853→94b428a,
9e84717→a5f7b21. Before this documentation update, integrated and tested candidate
trees were identical (`git diff 9e84717 HEAD --stat` empty).

Codex independently verified the combined candidate:
- Core 216/216 in UTC and America/Los_Angeles.
- Native 76/76 on each iPhone and iPad.
- Full serial UI suites 31/31 on each device, without parallel simulator runners.
- Additional focused phone polish checks 5/5.
- Actual simulator Dark appearance and Reduce Motion enabled: three representative
  flows passed on each device. QA phone and pad restored to Light and motion off.
- Unsigned Release build, brand-token check and whitespace check passed.

Evidence lives under `/private/tmp/aurora-night-polish-`: core-{utc,la}.log,
native-phone.xcresult, full-phone.xcresult, full-pad.xcresult,
focused-phone.xcresult, dark-reduced-{phone,pad}.xcresult, and
independent-release.log. Attachment exports with matching capture directories
were inspected for shared composer/card alignment, long-card title visibility,
held earlier replies, keyboard Save clearance, largest-text Health setup/settings,
and readable dark error/retry states on phone and pad.

The Release app was upgraded without erasing records on the isolated Aurora
Assistant iPhone simulator. Device Hub visibly displayed its preserved conversation,
interactive cards, local composer and Aurora identity. Synthetic gallery remains
available in the development build with isolated fixtures.

Remaining gates: manual observation of actual model-processing Stop/background
transitions and frame-continuous rim fade; physical-device motion smoothness,
VoiceOver, accessibility, latency, thermal and battery measurements; live Health
and calendar permission/data behavior; older supported OS acceptance; production
OAuth/support/signing, signed upgrade, TestFlight and publication. Synthetic motion
state labels and three reduced-motion UI flows do not establish these manual gates.
Planning/history and widgets/performance remain outside this completed overnight
premium-demo queue. No push, publication, account setup, personal-record erase,
global tool configuration change, paid fallback or banked reset was performed.
