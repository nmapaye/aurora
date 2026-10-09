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
