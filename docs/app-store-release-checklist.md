# Aurora release checklist

## Locked release

Native iPhone/iPad, English, paid US$4.99 upfront, free TestFlight. App Privacy
label: Data Not Collected. Initial storefronts:
US, Canada, UK, Australia, New Zealand after regional business/privacy checks.
Google Calendar is optional: v0.1.0 ships with Apple Calendar only, because Google
OAuth isn't configured (owner decision, 2026-10-24). No in-app purchases in v0.1.0.
No cloud AI, keys, subscriptions, analytics SDK, cross-device conversation/health
sync, or medical/dosing prescriptions.

## Owners and milestones

| Gate | Owner | Status / evidence required |
|---|---|---|
| Design tokens and synthetic gallery | Claude + Codex | Shared tokens and Debug synthetic gallery implemented; physical visual acceptance pending |
| Native style / motion polish | Claude | Reviewed card polish and website preview integrated from isolated Claude commits |
| Full erase and interruption recovery | Codex | 39 native tests and focused signed-simulator erase/relaunch pass; final combined runs recorded in verification doc |
| Privacy manifest / data-flow audit | Codex | UserDefaults declaration added; signed archive report pending |
| Core UTC/LA, native, phone/pad UI, Release | Codex | 64/64 both zones, 39/39 native and 16/16 UI per device, unsigned Release passed; xcresults in verification doc |
| Public CI | Codex | Serial ad-hoc simulator tests, time-zone parity, token checks and xcresult artifacts configured; remote run unverified |
| Apple enrollment / paid agreements | User | Pending; user completes legal agreements and payment |
| Signing and App Store Connect record | User + Codex | Team unset; no signed archive or upload yet |
| Google public iOS client / consent / verification | User + Codex | Not a v0.1.0 gate (Apple Calendar only). Before Google Calendar ships: client ID, callback registration, verified project/domain pending |
| Health allow/deny/revoke/empty/import | User + Codex | Physical signed-device tests pending; sleep read-only |
| Apple/Google calendars | User + Codex | Live account matrix pending; fixtures do not establish live acceptance. v0.1.0 needs Apple calendars only |
| Migration / storage recovery | Codex + User | Fixtures plus real prior-version device upgrade required |
| VoiceOver / large text / Reduce Motion | Claude + User | Physical phone/pad acceptance pending |
| Dictation / notifications / background refresh | User + Codex | Real-device allow/deny/interruption tests pending |
| Latency / scrolling / thermal / battery | Codex + User | Measured hardware evidence required; no speed claim yet |
| Website / privacy / support / metadata | Codex + Claude | Local drafts updated; verified hosting/contact required |
| TestFlight beta | User + Codex | Signed build, beta feedback and blocking defects resolved |
| App Review / publication | User | Final approval and store submission pending |

## Required acceptance matrix

- Every response: populated, missing, samples, insufficient history; corrections,
  Save/Undo, duplicates, failed writes, snapshots/Refresh and expired proposals.
- Models: available/unavailable, unsupported language/device, offline, cancelled,
  ambiguous/unsupported/invented requests; no model-supplied values or controls.
- Calendar (v0.1.0: Apple only; Google cases apply once Google Calendar ships):
  Apple-only, Google-only, mirrored authority, readonly/revoked, pagination,
  recurrence occurrence scope, DST/timezones, stale versions, conflicts, ambiguous
  transport failure, outcome/reversal. Use dedicated test events; no attendee notices.
- Storage: verified legacy import, version-1 conversation migration, corrupt/future
  files, retained originals, erase interruption/failure/relaunch, no re-import after
  erase, no stale asynchronous reads restoring snapshots or credentials.
- UI: iPhone/iPad light/dark, largest text, VoiceOver, Reduce Motion, keyboard,
  orientation/multitasking, touches through decoration, Stop/failure/background.
- Export actual CSVs; run all 60 seconds of reaction test on hardware; confirm results
  and thresholds. Measure <100 ms local control feedback and cold/warm model costs.

## Account preparation

The user enrolls with Apple and completes agreements/payment/tax/banking. Then set
the real Developer team for bundle `com.nmapaye.aurora`, validate HealthKit capability,
archive for generic iOS hardware, validate in Organizer, and upload internally.

Not needed for v0.1.0. Before Google Calendar ships, register an iOS OAuth client
for this bundle, enable Calendar API, use the reversed client callback scheme, and
configure AuroraGoogleClientID and AuroraGoogleCallbackScheme in Info.plist plus
that scheme in CFBundleURLTypes.
These are public OAuth identifiers, not API keys or client secrets. Keep a separate
test project/accounts. Verify exact scopes, consent branding, domain ownership,
policy links, and public production eligibility before release. Sign-in testing
does not authorize changing personal events; test only explicitly approved fixtures.

## Publication evidence

Final tag/commit, test logs and xcresults, signed archive validation/privacy report,
device checklist, Google production approval, methodology/claims review, real support
contact and working URLs, actual screenshots, age rating, export compliance, accurate
privacy/accessibility answers, price/storefronts and reviewer instructions.
No blocking data-loss, unauthorized-write, crash or accessibility defects may remain.
Google production approval applies only once Google Calendar ships, not v0.1.0.
