# Aurora product truth

Native SwiftUI iPhone/iPad assistant for energy and daily rhythm. Helps people
record sleep/caffeine, review deterministic estimates and measured reaction tests,
and review selected commitments. It does not diagnose fatigue, make medical or
health claims, or act as an unrestricted general assistant.

Conversation contains finite native cards. Logging is low-friction and reversible:
a log saves immediately with a clear, reliable Undo, and every log can be undone.
Sleep logs may still use a confirm card. Calendar changes require fresh explicit
approval. Historical cards are snapshots with Refresh. A day with no record is
"No record", never 0. Sample Data is labeled and read-only; Health records are
read-only.

Personal suggestions (e.g. a caffeine cutoff from the person's own logs) are
allowed when labeled as estimates, explained, opt-in, and never framed as medical
advice. No hard limits, allowances, "remaining" amounts, health claims, or
diagnosis/treatment language. Aurora may propose a setting value with its reason;
the person confirms it with one tap, never silently applied. Insights may show
before full thresholds as an "early read" labeled with the data used (e.g. "early
read, 5 nights"); full-confidence thresholds are unchanged.

Inference is local. On-device generated text is allowed, but every number in it
comes from deterministic app code; models never invent values. Quick actions work
offline without Apple Intelligence. Foundation Models requires runtime
availability; Mac Ollama is simulator-only development tooling. No cloud
inference, AI keys, analytics, or autonomous calendar edits. Health data stays on
device apart from the person's own iCloud sync. The person sets the daily cap on
notifications Aurora starts itself (default 1).

Sync (pending verification): cross-device sync through the person's own private
iCloud (CloudKit private database) is allowed in principle. Before shipping,
confirm the App Privacy label stays Data Not Collected. Not yet settled.

Launch (v0.1.1): paid upfront US$4.99 with no in-app purchases, free TestFlight;
Current TestFlight beta uses Apple-synced calendars only; direct Google OAuth is
deferred. Revisit paid App Store calendar scope before submission. App Privacy label: Data Not Collected (Health data never
leaves the device; Google Calendar, when connected, exchanges data directly between
the device and the user's own Google account, so nothing is sent to or stored by the
developer, and Aurora runs no server; CSV export happens only through the
user-initiated share sheet). English initial storefronts: US, Canada, UK, Australia,
New Zealand after regional checks.
Target iOS 17+ with explicit native controls when local AI is unavailable.

Apple Developer enrollment is active: agreements are active, the App ID is
registered, and the App Store Connect record "Aurora: Energy & Daily Rhythm"
exists. Distribution signing, real-device acceptance, performance and battery
evidence, privacy/store metadata, TestFlight, and App Review are gates, not
completed facts.

Design authority: `design.md`. Execution rules: `agents.md`. Work on isolated
branches with verification evidence; nothing merges to main without the owner's
explicit approval, and main is never force-pushed. Preserve other checkouts and
local data.
