# Apple on-device local features — isolated implementation, not acceptance

Base: PR77 `ea3dec1bfc7ab8d016ae3e8e9c86578e0cb57ee0`. This work does not
change the green branch, main, app deployment minimum (iOS17), Health policy,
release gates #71/#72, beta eligibility policy, or release authority.

## Implemented supported subset

The new runtime route uses **SystemLanguageModel.default explicitly**, never a
dynamic FoundationModels provider. Conditional imports and iOS26 availability
checks preserve the iOS17 app target. Ineligible/disabled/not-ready/unknown or
unsupported locale states return honest manual recovery. English only in this
bounded first slice. No third-party/cloud model fallback or mutating tools.

Existing deterministic routing takes precedence over the new positive logging
boundary. Caffeine cutoff/scenario, export/history and advice questions retain
their existing capabilities; a coffee/caffeine keyword alone does not select the
new path. Only a positive direct consumed-drink/log instruction with drink context
and no known non-logging capability enters the new feature. A model classifier label
alone cannot open a guessed manual logging draft for an unrelated question.

Typed drink requests must fully match `I had`, `I drank`, or `log`, followed by
one optional explicit mg/g amount, an exact supported drink name, and an explicit
`now` or local `at 8am`, `today at 8am`, `yesterday at 8am` time. An optional
literal `one` is supported. App code—not the model—converts grams, resolves
listed Aurora presets and a recorded usual, resolves local times, validates
whole 1–1999mg values, and rejects future/nonexistent/ambiguous supported wall
times. Generic coffee has no guessed dose. Unknown types, volumes, relative
hour/minute times, free-form dates, counts/batches, corrections, quotes,
negations, hypotheticals, medical requests and extra instructions produce no
model review or partial writes. The whitelist is deliberately conservative;
this is not broad natural-language competence. The model really extracts route
and exact spans from the typed message, while the independent grammar/provenance
validator may only admit a narrow supported subset; model-veto agreement alone
is NOT evidence of broad semantic understanding or completed feature acceptance.

For a supported input, guided generation extracts exact lowercase spans and
intent. Independent code must match all spans to the input-derived proposal.
A mismatch is not repaired by trusting the model or silently using rule parsing.
Original drink text and extracted spans remain ephemeral; the conversation shows
`Drink-entry request · text not retained`, then only the normal reviewed snapshot
and receipt. No new prompt/transcript/analytics logging or personal model context
is persisted. Existing manually entered conversation history is otherwise unchanged.

The UI shows immutable source, code-resolved mg/provenance, local date/time and
zone. Discard starts over; generated proposals cannot be patched by the manual
correction parser. No incomplete proposal has a Save control. Explicit Save uses
the existing durable addCustomDose path; repeated taps cannot save twice. Failed
persistence retains the review without a success receipt. Existing exact-record
receipt Undo and Health ledger handling are reused, not replaced. Health export
failure must leave the local record intact. No new Health writer/permission.

Energy explanations call a **real local generation session** with a minimized
structured snapshot transformed into supported **actual estimator-contribution**
clauses. EnergyEstimate.capture already calculates baseline + circadian + caffeine
minus sleep debt and inertia using Alertness's named weights. The new mapping
reuses captured signed points (EnergyContribution.pointsText), never invents or
recomputes attribution percentages. Available clauses explain the generic daily
curve, recorded-sleep debt, recorded-caffeine effect (only when evidence exists),
and recent-wake inertia (only when applied). App code orders factors by actual
absolute contribution; the model selects/composes one or two factor clauses from
that snapshot. Each clause explains a signed share of the **unclamped model**, not
a measured cause or diagnosis; rounded shares need not sum to the clamped score.
The model returns a composed sentence containing placeholders, not personal numbers.
Only an exact allowed composition is accepted. App code substitutes numbers
from the captured EnergyEstimate and appends the estimate/Sample Data qualifier.
This is intentionally **extractive constrained factor composition**, not only
score restatement and not open-ended paraphrasing or causal/medical reasoning.
Missing contribution evidence is stated as a gap instead of invented weights. Missing sleep remains No record, not
zero. Invalid/unavailable generation displays `Deterministic summary` explicitly;
that recovery does NOT establish model capability acceptance. The composed result
is integrated into the energy card and rendered, not just an offline harness.

## Autosave is hard disabled

`LocalDrinkUnderstanding.autosaveEnabled = false`; no runtime setting, preference,
model tool or call path can turn it on. The new model route has no automatic
mutation call. This manual-confirm slice does not waive the owner's future choice.

Before any enabling change Nathan must accept the exact predicates and evidence:
- One unambiguous already-consumed supported drink, with independently traced
  type, amount/unit and explicit time/default visible before mutation.
- Zero unsafe/unsupported/quoted/injected/correction/multi writes; unresolved
  fields clarify with zero partial writes, never count as false-success parses.
- Frozen drink-only labels/holdout and comparator; extraction, clarification and
  safety denominators separate. Historical mixed 300/40 metrics are not this gate.
- Request identity, cancellation/dismissal, stale results, repeated Save, persistence
  failure/recovery, exact Undo and failure receipts tested through real app paths.
- Own Health export failure retains the local record; exact linked-sample Undo only
  inside the independently verified already-authorized Health flow. Never imported edits.
- Real SDK compile, named physical eligible device/OS/model/locale receipts for
  both functions and unavailable/readiness/UI cases; no Linux/fixtures substitution.
- End-to-end latency proposal: warm p90 Submit→persisted record+Undo <=1.5s;
  >1.5–3s misses target; >3s stops/reworks candidate, not permission to drop either
  required feature. Clarification, cold start/download and explanations separate.

These are proposals, NOT accepted autosave criteria or measured gates. No new
benchmark/inference runs, CI, pushes, merge, release or acceptance in this work.

## Verification status / next action

Historical: all 23 new tests were initially unexecuted because Swift6.4.1 could
not load libncurses.so.6. An authorized official Homebrew installer and the
single official ncurses6.6 Linux bottle subsequently succeeded. Its standard
libncurses.so.6 alias targets libncursesw.so.6; actual ELF relocation/startup and
the targeted run below worked for this binary, not a blanket ABI claim.

The first actual compile exposed a new-test defect: Swift Testing's #expect
macro cannot call a mutating struct method through its immutable captured value.
The four gate.offer calls now execute into local Boolean values first; every
original positive/negative assertion is retained. No production behavior changed.

The default Swift Build engine's link child still failed library lookup despite
process-local LD_LIBRARY_PATH and successful standalone swift/swiftc startup.
The documented SwiftPM native build backend preserved the needed lookup. Exact
working command from AuroraCore (same installed toolchain, no global changes):

```sh
LD_LIBRARY_PATH=/home/linuxbrew/.linuxbrew/opt/ncurses/lib \
  swift test --build-system native \
  --filter 'LocalDrinkUnderstandingTests|GroundedLocalExplanationTests'
```

**13 core tests / 2 suites passed**, exit0. The native SwiftPM backend is deprecated;
that portability/maintenance caveat is not concealed. Ten authored app/native
fixtures, including observable routing and card rendering, remain **UNEXECUTED**.
No full core suite or CI ran. Linux package compilation/tests do NOT validate the
iOS framework, @Generable macros, availability/signatures, actors or SwiftUI.
No actual Apple inference, physical device/model/language, Save/Undo/Health/UI
or latency receipts exist. Both capabilities remain implemented but not accepted
or ready to ship. Autosave remains hard disabled.

Next: sanctioned native SDK compile and named eligible physical-device receipts,
including actual model usefulness and unavailable/manual recovery behavior.
The existing #71/#72 gates remain independent. Preserve the historical failure
logs and exact patch/commit/test receipts in the adjacent implementation handoff.

## Narrow API verification (Nov8,2026 PT)

Only three Apple pages opened; existing SPIKE-1 schemas/estimator/save-path evidence
were reviewed but not blindly cherry-picked:
- https://developer.apple.com/documentation/foundationmodels/languagemodelsession/init(model:tools:instructions:).md
- https://developer.apple.com/documentation/foundationmodels/languagemodelsession/respond(to:generating:includeschemainprompt:options:).md
- https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/supportslocale(_:).md

These live docs do not prove compatibility with an installed Xcode26 SDK.
