# Aurora design system

Status: release design foundation; native implementation is the source of rendered truth.
Audience: people recording sleep and caffeine and reviewing their daily rhythm.
Mood: calm, precise, warm, and quietly responsive. Never imply medical certainty.

## Product and hierarchy

- Conversation is the entry point. Finite native cards show evidence and controls;
  explanatory prose is optional, short, and grounded in records.
- One primary action per card. Put evidence before actions, and expose missing
  information beside the relevant logging control. Samples are always labeled.
- Secondary sheets hold history, settings, and connections. Match native keyboard,
  date-picker, navigation, and share-sheet behavior.
- Keep explanations off the main surface: one honesty label per fact (Sample
  Data, Modeled, read-only, pending/not exported, failure), no repeated
  reassurance sentences.
- Do not imply general-purpose agent capability, automatic calendar approval,
  remote inference, or continuous background reasoning.

## Tokens

Code: `Aurora/Theme/Palette.swift` and `Aurora/Theme/DesignTokens.swift`.
Update this specification and affected tokens together; screenshots confirm intent.

| Role | Light | Dark |
|---|---|---|
| Screen | #F6F2EA | #0F1317 |
| Card | #FFFDF8 | #151A1F |
| Primary text | #1A1F24 | #F3EFE7 |
| Secondary text | #5B6168 | #AEB3B8 |
| Tint / primary action | #1E6B64 | #7CC4B8 |
| Aurora teal | #2A7C73 | #7CC4B8 |
| Aurora mint | #7CC4B8 | #A7DBD1 |
| Aurora indigo | #4A5590 | #A3ADE6 |

Sky (`Sky` in Palette.swift): welcome and first-run backgrounds only, built from the
surface and sea tokens above, with no new colors. Each time of day (night before 5:00,
morning 5–12, afternoon 12–18, evening 18–24) has its own top-to-horizon gradient, and
light/dark appearance still decides the family. Ribbons use only aurora teal, mint and
indigo, blurred, at 0.34 (light) / 0.50 (dark) opacity. Text over a sky always sits on
`auroraGlass`: Liquid Glass on iOS 26+, regular material with a card border before.

| Daypart | Light (top · middle · horizon) | Dark (top · middle · horizon) |
|---|---|---|
| Morning | ivory50 · ivory100 · sea100 | ink900 · ink850 · sea800 |
| Afternoon | sea100 · ivory100 · ivory200 | ink850 · sea800 · ink900 |
| Evening | ivory300 · ivory200 · sea100 | ink900 · ink850 · sea800 |
| Night | ivory300 · sea100 · ivory200 | ink900 · ink900 · ink800 |

Calendar events borrow their source app's look: Google events are solid blocks in
the calendar's own color (text black or white by contrast), Apple events a 4 pt
color bar on a 12% tint. The calendar's color is data, not an Aurora token.

Semantic status, field, selection, chart, and disabled roles remain in Palette.
Do not invent per-screen colors. Do not use tint alone to communicate state:
every `StatusTone` carries a `symbol`, and `StatusBadge` always shows both.

- SF system typography, semantic Dynamic Type styles. Titles `.title2`, card
  headings `.headline`, readable evidence `.body`/`.subheadline`, sources `.caption`.
  `Typography.label` (`.subheadline`) names a field or metric; `Typography.value`
  (`.title3` semibold) is a recorded quantity; `Typography.heroValue` (`.title2`
  semibold) is the lead quantity of an evidence card.
- Use monospaced digits for changing quantities, units, and time comparisons.
- Fields: `LabeledField` puts the label above one field surface (`fieldBackground`,
  control radius, 44 pt) with the unit trailing inside it, so labels, values and
  units align down a card. Metric rows put label leading and value trailing on one
  baseline and stack when large text no longer fits both.
- Drafts show a `StatusBadge` beside the title (Review before saving, Saved,
  Removed, Expired, Discarded, Not saved). Receipts state outcome in the title and
  symbol; a removed entry stays listed, struck through, in secondary text.
- Draft actions: one full-width primary Save, then a quiet full-width Discard,
  stacked at every text size. Inline field problems mirror existing validation and
  never replace Save's own check.
- While a field inside a card has keyboard focus, the composer inset hides its hint
  and quick actions and keeps only the compact composer, so the card's Save stays
  above the keyboard. Both return when editing ends. While editing, the
  conversation can scroll past its end by the keyboard's height so Save is never
  stranded beneath the composer.
- Spacing scale: 4, 8, 12, 16, 20, 24, 32 points. System layout may supply its own
  spacing; document necessary optical exceptions instead of blindly rounding.
- Radii: controls 12, cards 16, hero 24; capsules for quick actions/composer.
- Minimum touch target 44 points. iPhone cards use available width; primary iPad
  conversation column max 600 points. Larger text stacks controls without clipping.
- The composer inset shares that column (`contentMaxWidth`, centered, `lg` from
  the edges): the hint and composer sit in it, and the quick-action strip scrolls
  edge to edge with its first action in line with the column (`Metrics.columnInset`).
  The composer field and card content both start 16 points inside the column.
  Composer: hero radius, tint border while focused, the whole surface focuses the
  field. Send turns into Stop while work runs, so Stop is reachable from anywhere.
- Decorative light is reserved for Aurora identity/processing. Cards use clean
  surfaces and subtle borders, with no decorative linear gradients or muddy shadows.

## Motion and feedback

- Tokens live in Motion. Ordinary state transitions are short and interruptible;
  processing starts immediately and never waits for a decorative animation.
- Rim fades in over 0.45 s and out over 0.70 s, freezing its last frame after work.
  Actual processing owns its visibility; cancellation/failure ends the processing
  timeline immediately. Do not add fake delays or animated mock reasoning.
- Idle motion stays subtle beside the title. Full edge movement is processing-only.
- Reduce Motion uses static identity/glow and disables decorative transitions.
  Inactive scenes do not run decoration timelines. Effects ignore touches and are
  hidden from VoiceOver; status and Stop remain independently accessible.
- Every custom control uses `PressFeedback`: it compresses to 96% with
  `Motion.pressSpring` and a soft haptic on touch-down, then springs back (dims
  with `Motion.press` instead under Reduce Motion). Use `.auroraPress` for rows,
  chips and cards; the primary, secondary and capsule styles already include it.
  `Motion.stateChange` (0.25 s, zero-bounce spring, interruptible) animates a card
  changing state in place: editor to saved summary, Undo leaving, the receipt
  symbol replacing. `Motion.stateTransition` is a fade with a 2% scale from the top;
  under Reduce Motion both become an instant change or plain crossfade. Cards do
  not get entrance animations; evidence text and charts do not move on their own.
- A new reply scrolls so its start (title, evidence) is visible, never its last
  control, when the latest message or the end was on screen. If the person is
  reading earlier messages, the page stays put and a "New message below" capsule
  shows the new reply's start on request. Their own message always shows the end.
  Scrolling uses `Motion.content`, instant under Reduce Motion.
- The rim's fade-out starts from the frame on screen when work ended, was stopped
  or failed; no timeline runs while it fades.
- Save/Undo use compact receipts. The one save moment: a draft that turns Saved
  on screen draws its check in (0.32 s) with a success haptic; saved cards seen
  later stay still. Chart selection moves
  its focus without moving the page. Animation must not affect reaction-test timing.
- No rainbow Siri rim, purple-blue backdrop, unnecessary card nesting, or perpetual
  movement around readable evidence.

### Cutoff scenario

- Every input starts empty: bedtime and drink time are added with a button that
  starts at the current local time, never a proposed one. The half-life is the
  Settings value, shown with its assumption label. Times show their zone.
- Date and time are separate native pickers so a repeated or skipped wall time
  can be chosen; a repeated time needs a First/Second choice with zone
  abbreviations, and a skipped time is an inline error, never shifted.
- Calculate (primary) freezes the result; edited inputs say "Calculate to
  update". The result lists bedtime, existing modeled caffeine with provenance
  (Sample Data badge, later-dated entries not included), the hypothetical and
  combined values with a symbol badge, and one latest-time row for each outcome.
- A future latest time offers a secondary "Preview a one-time reminder"; the
  preview sits on `cardMuted` with Save as the only primary. Outcomes show as a
  badge on the result; only a scheduled reminder gets a receipt.

### Welcome and first run

- The welcome is decoration over an already-loaded conversation, once per cold launch
  for people who finished setup. Any tap ends it in the same update: touches and
  VoiceOver return to the conversation at once, and the 0.25 s fade that follows
  ignores touches. With no tap it ends after 1.2 s. It never delays records, cards
  or processing.
- Under VoiceOver the welcome isn't shown, so focus starts in the conversation and
  nothing is announced twice. Reduce Motion: still ribbons, no scale or offset, and no exit fade. Sky ribbons
  pause whenever the scene isn't active.
- Greeting evidence is at most one captured record: sleep that ended in the last six
  hours, else caffeine recorded today, always with its time and source (Health,
  Manual, Sample Data). Sample Data uses the sample accent. No calendar events,
  estimates or zero values; with no record the line is "Ready when you are."
- First run: three skippable "Your day as a sky" scenes, then setup as a short
  conversation with one glass control panel (capped at accessibility2; the transcript
  scales fully, keeps the latest question above the panel and fades under the status
  bar). Every question has "Not now", and "Skip to the end" is always available.
  The transcript shows only questions actually asked. "You" bubbles are only what the
  person typed, chose or declined ("Not now"). A setting kept by "Not now" (the sleep
  target) appears as Aurora's note on `cardMuted`, never as a reply. Questions passed
  over by "Skip to the end" don't appear. The current question is shown from its
  first line; at the largest sizes, where it's taller than the space above the
  panel, the rest scrolls instead of its start being cut off. A failed save keeps the question, shows an
  error tone with its symbol above the controls, announces it, and leaves the controls
  ready for a retry.
- Setup's Health step shows the three separate choices from Apple Health settings and
  uses the same requests; calendars open the same connection sheet as Settings.
  Nothing is requested, connected or selected until the person chooses it. Sample Data
  is a separate, labeled finish option.

## Review and references

Gallery fixtures run in a temporary folder with a Health provider that refuses
every choice, no calendar providers and private defaults; the Reminders card's
device switches are disabled there. States: populated/missing/Sample Data/earlier
energy and card snapshots, interaction states (loading, saved, removed, expired,
failed, discarded), receipt Apple Health rows (pending, not exported, added,
unconfirmed), setup with failing then working saves, welcome evidence (recorded,
Sample Data, none), processing light (rest, working, stopped, failed, static) and
cutoff scenarios (each outcome, repeated/skipped time, reminder preview, not allowed,
failed, saved, earlier snapshot) with a scheduler that never reaches notifications.
Use the Debug Design Gallery with synthetic records, plus actual simulator captures
and device recordings. Reference the existing Aurora palette and user-approved
flowing identity; study native Apple interaction conventions without copying branding.
Review light/dark, missing/sample/populated data, large text, keyboard, iPad resizing,
VoiceOver order, Reduce Motion, disabled/error/expired states, and interrupted work.
Capture → identify specific defects → fix against tokens → compare → record evidence.

Third-party frontend skills are advisory. Native conventions, accessibility, this
file, and `agents.md` override web-only advice (including anti-system-font rules).
No paid design service, cloud inference, or executable model-generated UI is needed.
