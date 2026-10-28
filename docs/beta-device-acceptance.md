# Beta device acceptance

Owner-assisted protocol for the Apple-synced-calendar beta. This is a checklist,
not executed evidence. Use dedicated synthetic records and calendar events.
Physical results never inherit simulator passes.

## Setup and evidence

- Owner connects/unlocks and trusts the physical iPhone and iPad, enables the
  required development support, and handles protected signing prompts locally.
  Do not change Keychain ACLs or enable provisioning updates without approval.
- Record commit, archive/build, signing method, profile expiry, device model,
  OS and date. Verify the installed build matches that artifact. Current known
  hardware is iPhone 17e / iOS 27.0.1 and iPad Air (M2) / iPadOS 26.6.2;
  refresh these observations when connected.
- Establish whether an installation is disposable or contains needed records.
  Preserve an existing installation for the upgrade/migration case. Do not
  uninstall, corrupt files or run full erase on needed data. Use a separate
  disposable installation for destructive recovery checks.
- Inspect signature, embedded profile, HealthKit/background entitlements,
  privacy manifest and beta calendar scope before installation. The existing
  local development profile expires October 30 at 05:23:54 UTC; it does not
  establish TestFlight distribution eligibility.
- For each row, record **PASS**, **FAIL**, or **NOT RUN**, the device/build,
  exact steps, observed result and a redacted evidence reference. Missing
  prerequisites mean NOT RUN. Keep Health/calendar details off public issues.

## Mandatory physical matrix

Execute on both device families unless a row specifies its own prerequisite.

| Journey | Steps and required observation |
|---|---|
| Clean installation | On a confirmed disposable installation, install the signed artifact, launch, skip optional integrations and finish setup. Manual controls work without account/Health/calendar access. |
| Persistence and lifecycle | Save a synthetic manual caffeine/sleep record; terminate/relaunch and background/return. Exactly the saved records and completed setup survive, controls respond, and no receipt invents an external write. |
| Records and Undo | Edit a draft, Save once and double-tap, review history, then Undo the current eligible receipt. Observe one intended mutation; stale receipts cannot alter a different record. |
| Missing and sample records | On separate empty/sample fixtures, missing data says No record, samples are labelled/read-only, and insufficient evidence does not produce a baseline or comparison. |
| Missing-night model | Use synthetic sleep fixtures spanning either side of the 3h/18h boundaries; include an ongoing record and fragmented intervals. Eligibility, clipping, explanation and snapshots agree. These are display assumptions, not sleep recommendations. |
| Health read choices | Exercise sleep and caffeine reads separately: allow, deny, revoke and empty data. Declining one choice does not request another. Never infer read permission from empty results or say access was granted. |
| Health imports | With dedicated Health-app samples, refresh/import, relaunch and remove one source sample. Imports remain read-only, refresh does not duplicate them, and deletion removes the corresponding sample without removing another equal-time record. |
| Health caffeine export | Independently enable caffeine export. Save a synthetic Aurora entry: local Save survives and the Apple Health row confirms success only after Health confirms it. Verify edits/deletes affect Aurora-owned samples and preserve a separate matching sample from another source. |
| Health failure and retry | Deny/revoke write access on a fixture installation, then log locally. Local data persists, the Health outcome is truthful, and retry is explicit. Restoring permission/retrying does not duplicate a previously completed write. Network-off alone does not simulate HealthKit denial. |
| Health background and erase | Test background opt-in on/off, launch reconciliation and observer refresh. On a disposable installation, full erase cancels queued Health work and leaves previously exported samples in Health. Delivery timing is controlled by iOS; missing delivery is not a pass. |
| Apple calendars | Select dedicated EventKit calendars, including an OS-synced Google calendar if available. No direct Google sign-in is offered. Optional access can be denied/revoked without breaking manual logging. |
| Calendar writes | Preview a change to a dedicated writable event and approve exactly that change. Cancelled, expired/stale, read-only, conflicting or unapproved proposals do not write. Verify recurrence-instance scope, timezone/DST handling, and actual outcome before offering Undo. Do not use attendee-bearing real events. |
| Reaction Test | Complete the displayed 30-second test and review its measured result. Backgrounding/interruption does not silently save an incomplete test. Baseline appears only after the required recorded tests. |
| CSV export | Export all three CSVs through the share sheet to an owner-controlled location. Inspect synthetic values, dates, sources and missing-record handling. The files match saved records and remain private. |
| Reminders and background | Exercise notification allow/deny, chosen reminder offsets/cutoff, app background/return and cancellation. No inferred schedule or stale reminder is presented as an authorized action. |
| Dictation and model fallback | Test speech permission denial and interruption. Unsupported/offline local-model states leave typing and explicit actions usable; no cloud/key-entry fallback appears. |
| Accessibility and layout | On phone/pad, test VoiceOver reading order/actions, largest text, Reduce Motion, light/dark, keyboard entry/Done/Save, orientation and iPad multitasking. Every critical control remains reachable and accurately labelled. |
| Prior-version upgrade | On a device that actually ran the earlier build, preserve its source data, install the candidate as an upgrade, and verify records, retained originals, snapshots and no duplicate imports. If no genuine prior-version installation is available, record NOT RUN. |
| Storage recovery | On a disposable fixture only, follow the existing corrupt/future-file and interrupted-erase procedures. Originals survive, unsupported state is not overwritten, and incomplete erase resumes without resurrecting records. Fixture unit tests remain separately labelled. |

## Compatibility and operational gates

- Verify the declared iOS 17 minimum in a compatible runtime/device environment.
  The currently known physical OS versions and 26.5 simulator runs do not cover
  iOS 17. Compile-time availability checks alone cannot close that runtime gate.
- Owner confirms a monitored TestFlight/private feedback route and performs a
  synthetic feedback check. No agent sends a security report or message without
  explicit authorization. Private security reporting is enabled, but delivery
  and response are separate observations.
- Independent installation requires a separately approved internal TestFlight
  upload/invitation and an actual tester installation. Prepare the artifact and
  instructions first; do not dispatch the upload workflow during preparation.
- Rehearse rollback using a disposable fixture and a verified compatible build
  or forward fix. Do not downgrade over newer stored schemas or erase records
  to make a rollback appear successful.

P0/P1 failures or unexecuted mandatory gates block beta. SwiftUI frame warnings
remain P2 only when no critical control, data or accessibility behavior is
impaired; acceptance requires an owner, evidence, and explicit written approval.
