# Aurora product truth

Native SwiftUI iPhone/iPad assistant for energy and daily rhythm. Helps people
record sleep/caffeine, review deterministic estimates and measured reaction tests,
and review selected commitments. It does not diagnose fatigue, prescribe caffeine
or sleep schedules, or act as an unrestricted general assistant.

Conversation contains finite native cards. Logging requires Save; calendar changes
require fresh explicit approval. Historical cards are snapshots with Refresh.
Missing records are not zero. Sample and Health sleep records are read-only.

Inference is local intent classification only. Quick actions work offline without
Apple Intelligence. Foundation Models requires runtime availability; Mac Ollama is
simulator-only development tooling. No cloud inference, AI keys, analytics SDK,
cross-device health/conversation sync, or autonomous calendar edits.

Launch (v0.1.0): paid upfront US$4.99 with no in-app purchases, free TestFlight;
Current TestFlight beta uses Apple-synced calendars only; direct Google OAuth is
deferred. Revisit paid App Store calendar scope before submission. App Privacy label: Data Not Collected (Health data never
leaves the device; Google Calendar, when connected, exchanges data directly between
the device and the user's own Google account, so nothing is sent to or stored by the
developer, and Aurora runs no server; CSV export happens only through the
user-initiated share sheet). English initial storefronts: US, Canada, UK, Australia,
New Zealand after regional checks.
Target iOS 17+ with explicit native controls when local AI is unavailable.

User owns physical devices but Apple Developer enrollment is pending. Distribution signing, real-device acceptance, performance and battery evidence,
privacy/store metadata, TestFlight, and App Review are gates, not completed facts.

Design authority: `design.md`. Execution rules: `agents.md`. Codex owns integration,
services, privacy, storage and release correctness; Claude owns reviewed UI/theme
improvements in an isolated worktree. Both preserve other checkouts and local data.
