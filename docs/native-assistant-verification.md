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
A verified private support contact and deployed policy/support URLs remain required.
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
