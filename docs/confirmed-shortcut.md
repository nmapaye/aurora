# Review Drink Shortcut — bounded modification of SPIKE1

This candidate adds **Review Caffeine Entry / Review Drink**, not the historical
background-saving LogDrinkIntent. It carries no type, amount, time, free text or
Health data. `openAppWhenRun = true` opens Aurora; an app-process-memory request
opens the existing manual Log caffeine review only when storage/conversation,
onboarding and foreground state permit it. No URL payload, universal link,
App Group, extra state writer or model/provider is introduced.

Repeated requests coalesce. Existing draft/edit/in-flight work wins and consumes
the request without overwriting or replaying it after that work finishes. Before
storage/foreground readiness a request waits only in memory; onboarding must be
completed normally. A new process starts without a request. The shortcut performs
NO save/Undo/Health operation; the person still fills/reviews the ordinary editor
and taps explicit Save. Existing durable Save/receipt/exact-record Undo are reused.
Autosave remains hard disabled. No background last-record Undo intent is added.

## Experiment decisions
- SPIKE1 2bfd2dd1: **MODIFY / implemented here**. Its direct `addDose +
  queueHealthSave + exportToHealth` and background Undo entry points are rejected
  for this stream. Keep the useful Shortcuts entry point, but only as a reviewed
  foreground handoff without model-parsed or preset/usual values.
- SPIKE2 bb810450: **MODIFY / reuse existing implementation**. Its deterministic
  WhyThisNumberCard and duplicate AlertnessExplanation are not copied. Current
  GroundedLocalExplanation already maps captured signed estimator factors and
  supplies validated Apple composition plus clearly labeled deterministic fallback.
  Keeping one grounding pipeline avoids divergent numbers/copy and does not
  pretend a deterministic card satisfies actual model capability acceptance.
- SPIKE3 0e21e6e2: **DEFER dev evaluation, not a phone feature**. Its mixed
  sleep/drink schema, range sanitizer,300phrase scoring and Documents JSON output
  are not the current narrow drink-only provenance contract. Do not ship/run it
  as an end-user feature, new model benchmark, personal-data logger or acceptance
  substitute. A later explicitly scoped synthetic device evaluation must freeze
  candidate-specific labels and report safety/clarification/latency separately.

## Actual verification and gaps
Original5portable tests failed to compile before implementation (missing type),
then passed. CPO found missing Reaction Test/Health covers. An added behavioral
portable test REALLY FAILED twice: a covered request stayed queued while not ready
and replayed after dismissal. Fixed policy now consumes covering work before
readiness. The6handoff+13existing drink/explanation tests:19tests/3suites PASS
on Linux using process-local ncurses and SwiftPM native backend. Six app fixtures
are AUTHORED, UNEXECUTED here: original4plus2for actual Router Reaction Test and
canonical Health sheet state, asserting preservation/no card/draft/dose/replay.
Linux syntax parse is not Apple SDK typechecking.

Consumption now lives in AssistantView, the actual presentation owner. Health
presentation state is hoisted once to Router and bound to BOTH composer and sheet;
Router.coversCaffeineReview also includes Reaction Test and pending Settings route.
AssistantView passes live cover state at consumption (and after start suspends),
including its Clear animation and a live getter of RootView's blocking welcome.
Existing model-owned sheets/reviews stay in the model's gate. Covered requests
are consumed without dismissing/changing any cover. No cover-dismissal handler
queues or replays a request. App-level handling only discards onboarding requests.

AppIntents metadata generation/discovery, actual foreground process handoff,
onboarding/recovery/scene lifecycle, physical UX and OS17 compatibility need real
SDK/native verification. No actual Apple inference or phone install follows from
these portable tests. This change is staged locally only; parent owns publication and one
appropriate CI cycle. Personal install, #71/#72, autosave criteria and merge/release
remain independent gates. Do not copy unknown Mac source or enable test reset flags.

## Integration update (2026-11-12, integration branch)
The experiment decisions above were superseded when the experiments were
integrated on one branch, following PRODUCT.md ("a log saves immediately with a
clear, reliable Undo, and every log can be undone"):
- SPIKE1 **Log Drink** now ships beside Review Drink. It saves at once through
  the same local-first path (dose and queued Health action in one change), only
  with a Quick Add preset amount or the person's usual drink (never a guess),
  refuses until onboarding and the current Terms are done, ignores a retry of
  the same drink within 5 s, and offers exact-entry Undo in its result, by voice
  ("Undo drink", 10 minutes), and on the conversation's receipt. One
  `AppShortcutsProvider` (`AuroraShortcuts`) lists Log Drink, Undo Drink and
  Review Drink. Tests: `AuroraTests/LogDrinkShortcutAppTests`,
  `AuroraCoreTests/LogDrinkShortcutTests`.
- SPIKE2 **Why This Number** ships as the current energy card's disclosure,
  reading the captured `EnergyEstimate` (same contributions as
  `GroundedLocalExplanation`, so the numbers cannot diverge).
- SPIKE3 stays an evaluation: Debug-only, test bundle, `AURORA_FM_EVAL=1`.
