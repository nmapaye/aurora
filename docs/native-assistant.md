# Native Aurora assistant

Implementation branch: `codex/native-assistant`, based on the SwiftUI cutover
at `1e7a1d8`. Existing React Native worktrees remain unchanged.

## Experience and trust boundaries

The primary screen is a native SwiftUI conversation. Quick actions work
without AI or a network connection. Requests can propose editable caffeine
entries, edit sleep inline, show recorded energy evidence, explore caffeine/
sleep/reaction charts, review calendars, browse history, export CSVs, and manage
reminders. Routine responses use native cards; prose is reserved for clarification
and failures.
Amounts, dates, sources, and calculations never come from generated prose.
Explicit amounts and simple local times are parsed from the user's text;
ambiguous details remain editable and require Save. Unknown usuals have no
invented amount. Pending drafts are discarded across relaunches, not executed.
Corrections such as “Actually 120 mg yesterday at 8am” update the pending draft.

Apple's on-device Foundation Models classify unfamiliar requests when
available (iOS 26+ and enabled Apple Intelligence). On iOS 17–25 or unsupported
devices, the same native controls and explicit commands remain available.
The model chooses one typed capability; it cannot execute arbitrary tools or
write records. Explanations are deterministic, sourced from local records,
and explicitly distinguish modeled alertness from measured reaction results.
They do not establish causes of fatigue or prescribe doses/sleep schedules.

The animated aurora reflects actual processing and stops on cancellation or
failure. Reduce Motion produces a static treatment. Dictation requires local
speech support and sets `requiresOnDeviceRecognition`; unsupported languages
fall back to typing. There are no AI API keys, cloud models, or cloud requests.

## Local Mac model

In the simulator, Settings can opt into the installed `gemma4:26b` model through
Ollama on `127.0.0.1:11434`. Only the request text is sent, never health records,
calendar descriptions, or the conversation history. Remote/cloud models are
rejected. The app does not expose Ollama on the LAN or change its configuration.
This adapter is for simulator development, not running an 18 GB model on iPhone.

Synthetic model acceptance:

```sh
python3 scripts/evaluate-local-assistant.py --output /tmp/aurora-local-acceptance.json
```

The ten cases cover supported intents and unsupported medical/dosing/general
requests. This is a narrow intent-classification check, not a guarantee of
general conversational competence. Reasoning is disabled for this short task.

## Calendar connections

Apple calendars use EventKit full access with a disclosed purpose. Google
calendars synced to Apple can use this connection. Users explicitly select
included calendars; no calendar is automatically included.

Direct Google access uses system-browser OAuth with PKCE and state checking.
Tokens stay in device-only Keychain storage. It needs a registered **public**
iOS OAuth client identifier; no API key/client secret is accepted. Before
enabling it, configure `AuroraGoogleClientID` and `AuroraGoogleCallbackScheme`
in `Info.plist`, and register that reversed-client scheme under
`CFBundleURLTypes`. The connection is visibly unavailable until all three
are configured. Live OAuth was not exercised without this registration.

When a calendar exists through both providers, the user links the mirrored
connections and picks the authority. Reads/writes then use that connection
only. The app does not guess calendar identity from a title alone.

Schedule review is deliberately event-by-event. A later slot must preserve
duration, fit within the same day, and avoid selected commitments. Shared
invitations, read-only events, and all-day events are fixed. The preview shows
dates, timezone, and occurrence scope. Approval is single-use, and the app
re-reads event state and conflicts before writing. Google uses `If-Match` with
the preview's etag; EventKit saves `.thisEvent`. A stale preview cannot write.
Reversal is another reviewed, freshness-checked proposal. Ambiguous network
failure does not trigger an automatic repeat write.

No batch changes, attendee notifications, appointment cancellations, routing,
travel-time guarantees, or continuous autonomous scheduling are provided.

## Proactivity and storage

Proactivity defaults off. When enabled, meaningful sleep/calendar changes and
the opt-in briefing are evaluated on foreground refresh, EventKit change
notifications, and OS-granted background refresh opportunities. Quiet hours
default to 21:00–08:00; at most two unsolicited conversation suggestions are
delivered per local calendar day. Dismissal and delivery keys survive relaunch.
Known reminders use local notifications; the briefing notification invites
the user to open Aurora rather than presenting stale calculated results.
iOS may deny or delay background work, so no always-running agent is promised.

Conversation data uses a separate versioned protected JSON file in the
backup-excluded Application Support folder. Core record saves roll back the
in-memory change on failure. Native state keeps a `state.pre-assistant.json`
snapshot on first successful read. Legacy MMKV is imported, saved, decoded
again, and compared with the imported state; the original store is retained.
Unreadable records enter recovery; unreadable conversations are preserved.
No analytics or telemetry was added.

## Verification and release gates

Run Swift core tests in UTC and America/Los_Angeles, native storage/service
tests, iPhone/iPad UI tests, and Debug/Release simulator builds. UI coverage
includes first-run setup, the conversation home, explicit Save/Undo, missing
data, weekly charts/history, disconnected calendars, and absence of key entry.

Before TestFlight: exercise read-only HealthKit allow/deny/import on physical
devices; connect live Apple/Google test calendars; verify revocation, recurring
instances, mirrored authority, conflicts, etag failures, and reversal; measure
touch feedback (<100 ms), scrolling, animation, and battery use; test VoiceOver,
largest text, Reduce Motion, local model availability, dictation, and background
delivery. Configure signing, archive, validate, then distribute internally.
These gates remain pending; simulator success is not TestFlight readiness.

## Responsive local intelligence

The composer’s first three user turns show a gentle quick-action hint. Quick
prompts use deterministic intent routing and avoid model latency entirely;
people can always type their own request. There is no simulated thinking delay.

When the composer gains focus, Apple’s local classifier prewarms one fresh
session with the fixed classification instructions. The next model request
consumes that session; transcripts never accumulate across classifications.
Prewarming is best effort and does not hold up send or run in the background.

Successful local model classifications are cached in memory for five minutes,
up to 32 exact text/model pairs, with least-recently-used eviction. Corrections,
provider/model switches and expired entries miss the cache. Unsupported or
failed responses are not cached. Leaving the foreground clears the cache and
releases the prepared session. No cached conversation is persisted.

Only the intent is reused. Caffeine drafts, energy calculations, charts and
calendar previews still read current records/time on every request, and writes
still require the normal review and validation. No personalized answer or
calendar tool result is replayed. Physical-device cold/warm latency and energy
cost still require measurement before claiming a performance improvement.

## Interactive responses and snapshots

A finite `AssistantCard` library supplies caffeine/sleep editors, evidence,
six captured chart series (three signals across week/month), dated commitments,
reaction readiness/results, filtered record history, exports, reminders, and
briefings. Only deterministic Swift builders populate cards. Past results keep
their capture time and time zone; Refresh adds a fresh result. Export buttons and
reminder toggles explicitly act on current device records/settings.

Drafts and calendar reviews close across relaunches and require a new review.
Save receipts persist, and Undo re-reads the exact saved record including note
changes before removing it. Corrections have a receipt but use history for further
editing rather than an Undo that would delete the record. Calendar outcomes are
reported for the single approved event; no automatic retries or batch-success
claims are made. Reaction results return to conversation after an actual save.

Conversation version 2 adds optional card payloads. Loading version 1 retains
`conversation.v1-source.json`, saves version 2 and verifies full equality; failures
restore the source. Legacy messages remain text, without attaching newly computed
charts or live actions to historical answers. Explicit Clear conversation also
removes the retained conversation migration copy, while preserving app records.

The compact header replaces the large ribbon. A screen-edge multicolor glow
appears only during actual processing, with plain status text and Stop. Reduce
Motion uses a static glow. No timer delays cached or deterministic results.
