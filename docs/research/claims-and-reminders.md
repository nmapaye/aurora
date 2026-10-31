# Health claims, regulatory positioning and reminders

Research note, 2026-10-15. Branch `claude/research-claims` from `claude/ui-review` (10b6b34).
No app code was changed.

**This is not legal advice.** It compares Aurora's copy and behaviour with primary regulatory
texts and peer-reviewed studies. Items marked **Lawyer** need a qualified opinion before release.

## 1. Summary

- **Classification.** Aurora fits the FDA's *General Wellness: Policy for Low Risk Devices*
  (6 January 2026) as a first-category product: sleep management, energy and mental acuity, with no
  disease reference. It is low risk because it is software only, non-invasive and has no
  intervention. It is not Clinical Decision Support software, because the CDS carve-out covers
  software aimed at healthcare professionals. Aurora's equivalent position in the UK, Canada,
  Australia and New Zealand is "not a medical device" for the same reason: it has no medical
  intended purpose.
- **What would move it.** The 2026 guidance now lists what disqualifies a product: references to
  diseases or diagnostic thresholds, alerts that prompt clinical action, treatment guidance,
  claims of clinical accuracy, and disease-targeted intended use. A caffeine limit presented as
  safe, or advice tied to insomnia, pregnancy, anxiety or heart conditions, would be the most
  likely ways for Aurora to drift.
- **Copy is mostly sound.** The `CopyRules` guard, the "Modeled" labels and the Settings
  disclaimer already do the work. The audit found **16 items**, one of which is preventive (never call the reaction test a "PVT"). The ones that matter most:
  - The daily **cutoff notification**, "Last call for caffeine… likely to affect tonight's sleep",
    makes an outcome prediction and gives a directive, at a 4 PM time that Aurora chose.
  - The **400 mg default** for the "personal caffeine reference" equals the FDA's figure for
    healthy adults, while its footnote says it is not a safe amount. The setting isn't used
    anywhere else.
  - App Review 1.4.1 asks for a **check-with-a-doctor reminder**, and Aurora has none.
  - The **TestFlight notes** say HealthKit is read-only, but Aurora can write caffeine.
- **Reminders.** In-app suggestions are capped at 2 a day, but there is **no combined cap on push
  notifications**. A person who turns everything on can get up to about 10 a day. All of them play
  a sound at the default interruption level.
- **Drink follow-ups.** These fire **at the same time as yesterday's drink**. That is the moment
  when a question naming the drink is most likely to act as a cue to have it (cue reactivity and
  the question–behaviour effect). Moving the prompt to about 60 minutes after that time keeps the
  logging help and lowers the cueing risk. Batching notifications and making them passive helps
  too.
- **"Wait 90 minutes" for caffeine** has no direct trial evidence. Aurora's wake reminders don't
  endorse it, but the one-tap presets include 90 minutes.

## 2. Regulatory positioning

### United States: FDA

**General Wellness (January 2026).** A general wellness product has "an intended use that relates
to maintaining or encouraging a general state of health or a healthy activity" and is low risk
(guidance §II–III). The first category covers sleep management and mental acuity. Examples include
"Claims to promote sleep management, such as to track sleep trends" and claims to "improve energy".
Section 520(o)(1)(B) of the FD&C Act takes healthy-lifestyle software out of the device definition
altogether.

The 2026 revision adds an explicit list. A product is **not** general wellness if its labeling,
advertising, user interface or functionality includes any of the following (§III):

1. references to specific diseases, clinical conditions or diagnostic thresholds;
2. alerts that recommend clinical action;
3. treatment guidance;
4. claims of clinical equivalence or accuracy, or of being medical grade;
5. intended-use statements that target diagnosis, screening, monitoring or management of a disease.

Wellness products "may display values, ranges, trends, baselines, or longitudinal summaries". A
nudge to see a professional is allowed only if it names no condition and doesn't call the output
abnormal. Labeling, including the UI, must not exceed the stated intended use.

**Clinical Decision Support (January 2026, re-issued 29 January 2026).** The non-device CDS
criteria in §520(o)(1)(E) apply to software that supports a **healthcare professional's**
decision. Aurora is for consumers, so the CDS route doesn't apply. If Aurora ever gave specific
caffeine or sleep directions for a condition, it would fall under device software function
policy, not CDS.

**Where Aurora sits.** It is first-category general wellness. Its estimate is a modeled score from
records, not a sensed physiological value. Its reaction test measures speed and does not claim to
diagnose impairment. Aurora's safest position is no disease references at all, rather than
second-category "may help reduce the risk of" claims.

### Phrases that move Aurora toward device claims

| Avoid | Why | Use instead |
|---|---|---|
| "detects / measures fatigue", "drowsiness alert", "impairment" | Diagnostic or monitoring claim about a state | "reaction speed", "modeled alertness" |
| "diagnose", "treat", "insomnia", "sleep disorder", "anxiety", "ADHD", "pregnancy", "heart" | Disease reference (2026 §III item 1) | No condition names; keep the generic Settings disclaimer |
| "safe caffeine level", "limit", "overdose", "too much", "mg remaining" | A safety threshold acts as a diagnostic threshold or treatment guidance | "your reference amount", "recorded today" |
| "stop caffeine now", "last call", "you should…", "recommended dose or bedtime" | A directive that guides management | "your cutoff time", "a time you set" |
| "clinically validated", "accurate", "medical-grade", "as good as a sleep lab" | Accuracy or equivalence claim (item 4) and App Review 1.4.1 | "estimate", "modeled", "your records" |
| "improves sleep", "prevents crashes", "boosts focus" | Outcome claims need substantiation under FTC rules, even for wellness | "see how caffeine and sleep line up in your records" |

**Safe wellness wording, in Aurora's voice:** "Track sleep and caffeine." "Modeled alertness,
0–100." "Reaction speed, 30 seconds." "A time you set." "Your records." "Estimate."

### UK, Canada, Australia and New Zealand: what differs

- **UK (MHRA).** The question is intended purpose under UK MDR 2002. The MHRA's software and apps
  guidance treats lifestyle and wellbeing apps as outside regulation unless they have a medical
  purpose. It singles out symptom checkers and clinical calculators as borderline. Aurora's
  cutoff scenario and half-life maths are calculators, so they must stay framed as non-clinical:
  no dose and no condition. For UK advertising, the CAP Code (section 12) requires documentary
  evidence for health claims. **Lawyer:** confirm UK marketing copy.
- **Canada (Health Canada).** The SaMD guidance (2019, §2.2) excludes "software intended for
  maintaining or encouraging a healthy lifestyle, such as general wellness apps". This is broadly
  the same as the US.
- **Australia (TGA).** Excluded Goods Determination 2018, Schedule 1, item 14B, covers consumer
  health and wellness software that measures or monitors parameters such as sleep. It does not
  apply if the software makes claims about a *serious* disease. If any one feature fails the test,
  the whole product loses the exclusion. That makes one bad string riskier in Australia than
  elsewhere. **Lawyer:** confirm the exact item 14B text. The TGA site was unreachable while this
  was written, so the item comes from TGA summary pages.
- **New Zealand.** No separate wellness guidance was found. Classification depends on whether the
  app has a therapeutic purpose under the Medicines Act. **Lawyer:** confirm before the NZ
  storefront.

## 3. App Store and HealthKit checklist

| Requirement | Source | Aurora today | Action |
|---|---|---|---|
| Health-measurement accuracy claims must disclose methodology, or the app is rejected | ASRG 1.4.1 | Estimates are labeled "Modeled". The reaction score uses Aurora's own fixed bands. | Name the score "on Aurora's scale" (audit #6) |
| "Remind users to check with a doctor… before making medical decisions" | ASRG 1.4.1 | Missing | Add one clause to the Settings disclaimer (audit #4) |
| Privacy policy link in App Store Connect and inside the app | ASRG 5.1.1(i) | Settings › About links it. The page is a draft. | Deploy before submission (already a gate) |
| Consent before collection, an easy way to withdraw, accurate purpose strings | ASRG 5.1.1(ii) | Three separate Health opt-ins; notifications are requested only when turned on | Fix the purpose-string wording (audit #12) and remove the unused clinical-records key (audit #13) |
| Alternatives when consent is declined | ASRG 5.1.1(iv) | Manual logging everywhere | None |
| HealthKit data never used for marketing, advertising or data mining | ASRG 5.1.2(vi), 5.1.3(i) | No analytics or ads | Keep this rule if any SDK is ever added |
| Never write false data to HealthKit; no health data in iCloud | ASRG 5.1.3(ii) | Writes only caffeine saved in Aurora; stores are excluded from backup | None |
| Disclose the specific health data collected | ASRG 5.1.3(i) | Purpose string and privacy page | Keep the App Privacy answers (Health and Fitness, read and write) in step |
| Name the HealthKit integration in the description | ASRG 2.5.1 | Description says "Apple Health" | None |
| Accurate metadata | ASRG 2.3 | TestFlight notes say read-only; App Store description omits wake reminders and follow-ups | Audit #14 and #15 |
| Notifications aren't required, carry no sensitive information and aren't marketing | ASRG 4.5.4 | Opt-in and not marketing. Follow-up titles show drink and mg on the lock screen. | Leave mg out of notification text (§6) |
| Don't infer whether read access was granted | HealthKit privacy docs | Copy says "Requested", never "Granted" | None |

**Category:** submit as Health & Fitness, not Medical. That avoids the extra 1.4.1 scrutiny and
matches the wellness intended use.

## 4. Claims audit

Risk levels: **H** means it contradicts the wellness position or Aurora's own rules, **M** means
it is an unsubstantiated or confusing implication, and **L** means clarity or the
one-honesty-label rule.

| # | File:line | Current text | Risk | Rewrite | Source |
|---|---|---|---|---|---|
| 1 | `AuroraCore/Sources/AuroraCore/Onboarding+Copy.swift:132-133` | "Last call for caffeine" / "After 4 PM, caffeine is likely to affect tonight's sleep." | **H.** A directive plus an outcome prediction that ignores dose and bedtime. The effect depends on both (8.8 h for about 107 mg and 13.2 h for about 217 mg in the meta-analysis), so "likely" isn't substantiated for everyone. It breaks PRODUCT.md's "does not prescribe". | Title: "Your cutoff time". Body: "4 PM · the time you set." | FDA GW 2026 §III items 2–3; FTC Health Products Compliance Guidance; Gardiner 2023 |
| 2 | `AuroraCore/Sources/AuroraCore/Models.swift:131` | `cutoffHour: 16` (the default behind the reminder and chart marker) | **M.** The cutoff time is Aurora's choice, not the person's. The reminder copy calls it "the cutoff time you chose". | No default: the marker and reminder stay off until the person sets a time, as the cutoff scenario already does. | design.md §Cutoff scenario; Gardiner 2023 |
| 3 | `Aurora/Screens/Settings/SettingsView.swift:66-69` with `Models.swift:130` | "Personal caffeine reference" … "It is not a recommended or safe amount." Default `dailyLimitMg: 400`. | **M.** 400 mg is the FDA's healthy-adult figure, so the default contradicts its own footnote; the FTC judges the net impression. Nothing else reads the value. | Remove the setting. If it stays, start empty: "Your reference · not set". Keep the one footnote. | FTC guidance (net impression); FDA "Spilling the Beans" |
| 4 | `Aurora/Screens/Settings/SettingsView.swift:103` | "Aurora is informational only and does not diagnose, treat, cure, or prevent any disease or condition." | **M.** It lacks the reminder App Review asks for. | "Informational only. Doesn't diagnose, treat, cure or prevent any condition. Check with a doctor before medical decisions." (only here) | ASRG 1.4.1 |
| 5 | `AuroraCore/Sources/AuroraCore/Vigilance.swift:4-7, 176-180` | Ratings "Sharp / Steady / Slipping / Sluggish" from fixed score bands of 80, 60 and 40 | **M.** Words about the person's state, from unvalidated absolute bands, read like a fatigue assessment. (Legacy "Fatigued" was already renamed.) | Describe the run, not the person: "Fast / Typical / Slower / Slowest". Once a baseline exists, compare to it ("Faster than your baseline"). | FDA GW 2026 §III item 4; ASRG 1.4.1 |
| 6 | `Aurora/Screens/ReactionTest/ReactionTestView.swift:132` (score) | The large score is shown with no scale | **L.** Accuracy and methodology disclosure | Add the scale caption "of 100 · Aurora's scale" | ASRG 1.4.1 |
| 7 | `AuroraCore/Sources/AuroraCore/Welcome.swift:306` | "Log a drink in a tap and see its effect rise and fade." | **M.** "Its effect" implies a measured effect on the body. The chart shows modeled caffeine. | "Log a drink in a tap and see its modeled caffeine rise and fade." | FDA GW 2026 §III item 4; FTC (implied claims) |
| 8 | `AuroraCore/Sources/AuroraCore/RepeatDrinks.swift:67, 100` | "Had your 9:30 Drip today?", delivered at 9:30 | **M** (behavioural). A question naming the drink, at the habitual time, acts as a cue. | Deliver about 60 min later. Text: "Did you have a Drip around 9:30?" (see §6) | Wood et al. 2016; Shephard & Barrett 2021 |
| 9 | `Aurora/Screens/Settings/DrinkFollowUpControls.swift:21` | "At the time you had one, Aurora asks whether you had it again, so logging it takes one tap." | **L.** "Again" frames a repeat; it describes the cue timing. | "After yesterday's time passes, Aurora asks whether you had that drink, so logging it takes one tap." | §6 |
| 10 | `Aurora/App/AssistantModel.swift:734` | Briefing notification body: "Open Aurora to review today's recorded energy and commitments." | **L.** Energy is modeled, not recorded. | "Today's sleep, caffeine and commitments." | design.md (one honesty label per fact) |
| 11 | `AuroraCore/Sources/AuroraCore/Summary.swift:68` | "Estimated alertness … This is an estimate, not a measurement." | **L.** Says "estimate" twice, and the cards already carry "Modeled". It also feeds the briefing text (`AssistantPlanner.energyExplanation`). | Drop the last sentence where the card shows the Modeled label. Keep it only in spoken or VoiceOver-only text if it has no visual label. | design.md |
| 12 | `Aurora/Info.plist:31` | "…to show your records and estimate sleep debt and alertness." | **L.** "Sleep debt" isn't used in the UI ("Recorded sleep against your goal") and sounds clinical. | "…to show your records, compare sleep with your target and estimate alertness." | ASRG 5.1.1(ii) |
| 13 | `Aurora/Info.plist:28-29` | `NSHealthClinicalHealthRecordsShareUsageDescription`: "Aurora does not read clinical health records…" | **L.** A purpose string for a capability Aurora doesn't use. It invites review questions and implies a clinical surface. | Remove the key. Verify that nothing in HealthKit authorization requests clinical types. It's a shared file, so agree with Codex first. | ASRG 5.1.1 |
| 14 | `docs/testflight-beta-metadata.md:20` | "HealthKit is read-only and optional." | **M.** Inaccurate: there is an optional caffeine write. | "Apple Health is optional: separate reads for sleep and caffeine, and an optional write for caffeine saved in Aurora." | ASRG 2.3, 5.1.3(i) |
| 15 | `docs/app-store-metadata.md:19` | "Opt into morning briefings and cutoff reminders." | **L.** Leaves out wake reminders and drink follow-ups. | "Opt into a morning briefing and reminders at times you set." | ASRG 2.3 |
| 16 | All reaction-test copy (`ReactionTestView.swift`, `Insights.swift:230`, `AssistantCard.swift:185`, metadata); type names such as `Vigilance` are internal only | No user-facing "PVT" or "psychomotor vigilance" today. Keep it that way. | **M** (preventive). The shortest validated brief PVT (PVT-B) runs 3 minutes; the standard PVT runs 10. Calling Aurora's 30–60 s test a "PVT" would claim validity it doesn't have and lean on the name of a sleep-loss research instrument. Input from the parallel sleep research. | Always "Reaction Test" / "reaction speed". Add `pvt` and `psychomotor vigilance` to `CopyRules.forbiddenPattern`. | Basner, Mollicone & Dinges 2011; ASRG 1.4.1; FDA GW 2026 §III item 4 |

These lines need no change: `CutoffScenario.swift:10-11` (assumption and disclaimer),
`ReactionTestView.swift:141` ("not a medical assessment"), the `EnergyEstimate.swift:56-59`
assumptions, `docs/app-store-metadata.md:23` and the `CopyRules` regex itself. One suggestion for
`CopyRules.forbiddenPattern` (`Onboarding+Copy.swift:145`): add `last call`, `detects?`,
`diagnos`, `fatigue` (outside the allowed disclaimer sentences), `safe (level|intake)`, `pvt` and
`psychomotor vigilance`, so the
existing test catches future drift. Sentences that negate the term, like the ones in
`allowedSentences`, stay allowed.

## 5. Reminder and notification recommendations

**Current load.** For a person who turns everything on, Aurora can send these pushes in a day:

| Notification | Most per day |
|---|---|
| Briefing | 1 |
| Cutoff reminder | 1 |
| Wake reminders | 4 |
| Drink follow-ups | 3 |
| Cutoff scenario (one-time) | 1 |

That is **10 at most**, and each one plays a sound at the default ("active") interruption level.
The cap of 2 in `ProactivePolicy` covers only in-app suggestions.

**Evidence, briefly:**

- In a large micro-randomized trial, sending a push raised next-day engagement by only about 3.9%.
  The midday-weekend benefit came from an exploratory analysis (Bidargaddi 2018).
- Batching notifications three times a day improved attention, mood and sense of control compared
  with getting them as they arrive. Turning notifications off entirely raised anxiety and fear of
  missing out (Fitz 2019).
- Perceived disruption depends on how a notification is presented and what the person is doing,
  even when the content is useful (Mehrotra 2016).
- In experience-sampling research, burden comes mainly from the *length* of each prompt, not from
  3–9 prompts a day (Eisele 2022). The average study ran 6 prompts a day with 79% compliance
  (Wrzus & Neubauer 2022). Those were paid study participants, though. Consumers can simply switch
  off Aurora's notifications in iOS, and no study found here measured that opt-out rate. So the
  daily cap is a judgment call, informed by the trade-off between burden and engagement.
- Reminders keep a behaviour going but stop it becoming automatic (Stawarz 2015). That is
  reassuring here: reminders should not build a caffeine habit by themselves. It also means
  logging that depends on reminders stops when the reminders stop.

| Constant | File:line | Current | Recommended | Source | Confidence |
|---|---|---|---|---|---|
| In-app suggestion cap | `Assistant.swift:268` | 2/day | Keep 2 | Bidargaddi 2018; Mehrotra 2016 | Medium |
| Quiet hours | `Assistant.swift:31-32` | 21:00–08:00, applied to suggestions, the briefing and follow-ups | Keep the defaults. Also apply them to wake reminders computed from the *usual* wake time, because the person may still be asleep. Reminders from a *recorded* wake can stay exempt. | Hilditch & McHill 2019; Apple Focus behaviour | Medium |
| Briefing hour | `Assistant.swift:30` | 08:00 by clock | Keep 08:00 as the default. Add an optional "after I wake" setting: recorded wake + 30 min, falling back to the hour. A briefing timed to wake-up avoids arriving before the person is up, and lands after the worst of sleep inertia (the first ~15–30 min). | Hilditch & McHill 2019; Künzler 2019 (receptivity) | Low–medium |
| Combined push budget | none | up to ~10/day | Count user-scheduled reminders (wake, cutoff, briefing) separately from Aurora-initiated ones (follow-ups). Allow **1 Aurora-initiated push a day**. Show the daily total of scheduled reminders in the Reminders card. | Fitz 2019; Mehrotra 2016 | Medium |
| Interruption level | `ReminderService.swift:94,157,217,293` | `.active` with sound | Follow-ups `.passive`, no sound. Briefing `.passive` by default. Wake and cutoff stay `.active`. Never `.timeSensitive`. | Apple `UNNotificationInterruptionLevel`; Mehrotra 2016 | Medium |
| Follow-up daily limit | `RepeatDrinks.swift:21` | 3 | Keep 3 in-app cards. Batch the notification into **one** a day. | Fitz 2019 | Medium–low |
| Follow-up due time | `RepeatDrinks.swift:67` | yesterday's time | Yesterday's time **+ 60 min** | Wood 2016; Shephard & Barrett 2021 | Medium |
| Follow-up window | `RepeatDrinks.swift:23` | 4 h after due | Keep 4 h from yesterday's time, which leaves 3 h after the shifted due time | judgment | Low |
| "Already logged" match | `RepeatDrinks.swift:26` | ±90 min | Keep. With the +60 min shift, it suppresses more prompts. | — | Medium |
| Follow-ups after the cutoff time | none | allowed | Suppress follow-ups at or after the person's cutoff time, as wake reminders already do | consistency | Medium |
| Follow-up auto-pause | none | — | After 5 days in a row with every follow-up dismissed or expired, stop notifying and show one in-app note | habituation (Mehrotra 2016); judgment | Low |
| Wake reminder count | `WakeReminder.swift:37` | ≤4 | Keep. The person chooses each one. | — | Medium |
| Wake reminder presets | `WakeReminder.swift:42` | 30, 60, **90**, 120, 180, 240, 300, 360 | Take 90 out of the one-tap presets so the popular rule isn't echoed. The custom picker still allows it. | §5 below; `CopyRules` already bans "90-minute" | Low |
| Cutoff reminder default | `Models.swift:131` | 16:00 | No default (audit #2) | Gardiner 2023 | Medium |

**Wake-relative caffeine reminders and the "90 minutes" advice.** No trial was found that tests
whether waiting 90 minutes improves alertness or prevents an afternoon "crash". The reasoning
behind it doesn't hold up well:

- Caffeine's effect on cortisol is blunted, though not removed, in daily users (Lovallo 2005).
- Morning grogginess (sleep inertia) mostly clears within 15–60 minutes (Hilditch & McHill 2019).
- The well-supported timing evidence is about *late* caffeine and sleep (Gardiner 2023), not
  morning timing.

Aurora's copy correctly says the times are the person's own, in `WakeReminder.swift:4` and
`Welcome.swift:318` ("Pick when…"). Two small risks remain. The 90-minute preset echoes the
popular rule. The notification title "Your caffeine reminder" is fine as is, because the person
set it. Aurora must never pre-select an offset or rank the presets.

## 6. Drink follow-up design guidance

The product owner's decision stands: follow-ups help with logging and stay. The guidance below
lowers the risk of cueing consumption without removing the feature.

**Why timing matters.** Habits are triggered by context cues such as time, place and preceding
events, more than by intentions (Wood & Neal 2007). Repeating a behaviour at a consistent time
builds that automatic link (Lally 2010). Coffee cues raise craving and heart rate in daily coffee
drinkers (Shephard & Barrett 2021). Separately, *asking* someone about a health behaviour slightly
increases how often they do it. The pooled effect was d = 0.29 in Wood et al. 2016 and g = 0.14 in
better-controlled studies (Wilding 2016). A question that names the drink, delivered at the minute
the person usually has it, combines all three. The same question asked afterwards is mostly a
recall prompt.

Self-monitoring is consistently associated with better outcomes, though the evidence quality is
weak (Burke 2011). No completed trial was found showing that push reminders improve logging
specifically; a meal-logging micro-randomized trial, NCT07555262, is registered. So the logging
benefit is plausible but not proven, and that argues for keeping the follow-ups light.

**Recommendations**

1. **Ask after, not at.** Deliver the card and the notification about 60 minutes after yesterday's
   time. If the person logged the drink in the meantime, the existing ±90-minute match suppresses
   the prompt.
2. **Use past-tense wording about recording.** "Did you have a Drip around 9:30?" The actions are
   **Log it** (opens the draft, as now) and **Not today** (dismisses).
   - "Not today" must not write a zero, because missing records are not zero.
   - Avoid "again", "usual", "time for", "ready for", and drink imagery or emoji in notifications.
3. **Keep the lock screen plain.** Notification title: "Log yesterday's drinks?" Body: "Drip ·
   around 9:30." Leave out mg and stack several drinks into one notification. Show the mg in-app
   only ("Yesterday · 95 mg"). This keeps the notification less like a cue and keeps intake
   details off a shared screen (ASRG 4.5.4).
4. **Send one passive notification a day.** Make it `.passive` and silent, and batch it at the
   latest due time of the day's prompts. In-app cards still appear one by one, up to 3.
5. **Respect the person's boundaries.** Send nothing in quiet hours (already done), and nothing at
   or after their cutoff time.
6. **Back off when ignored.** Use the auto-pause above, and have the Settings row say "Paused after
   several unanswered days."
7. **Settings copy** (audit #9): "After yesterday's time passes, Aurora asks whether you had that
   drink, so logging it takes one tap."
8. **Unchanged:** off by default, notifications as a separate opt-in, drinks logged in Aurora only,
   no Sample Data, and never suggesting a drink.

## 7. Open questions for the product owner

1. **Reaction test length.** Resolved: the test runs 30 s, as the research brief and the sleep
   research proposed (#39; earlier 60 s sessions stay labelled "Earlier 60-second test"). It is
   still shorter than any validated PVT, so audit #16 applies.
2. **Defaults:** may Aurora keep *any* default cutoff time (16:00) or reference amount (400 mg)? My
   recommendation is no to both.
3. **Follow-up shift:** is +60 minutes acceptable, or would you rather send one evening recap? The
   recap carries less cue risk but more recall error.
4. **Combined push budget:** may Aurora-initiated notifications be limited to 1 a day?
5. **Age rating.** Caffeine guidance for children and teens differs from adult guidance. Should the
   App Store age-rating answers keep Aurora out of younger age bands? **Lawyer or App Review.**
6. **Shared files.** The `Info.plist` changes (audit #12–13) and `ReminderService` touch Codex-owned
   files. Who makes them?
7. **Lawyer:**
   - Does the **FTC Health Breach Notification Rule** (as amended 2024, in force 29 July 2024)
     apply? Aurora draws on several sources (manual entries plus HealthKit), which fits the FTC's
     description of a personal-health-record vendor even with no cloud. A breach includes any
     *unauthorized disclosure*, so the practical exposure is any future SDK, crash reporter or
     network call carrying health data. With no server and no analytics, a reportable breach is
     unlikely today, but coverage may still exist.
   - State consumer-health-data laws, such as Washington's My Health My Data Act.
   - Controller status under UK GDPR and PIPEDA when processing happens only on the device.
   - The TGA item 14B text, and New Zealand's classification.
   - UK CAP Code compliance for the store copy.

## 8. Sources

Regulatory and platform:

- FDA, *General Wellness: Policy for Low Risk Devices*, 6 Jan 2026 (docket FDA-2014-N-1039). https://www.fda.gov/media/90652/download
- FDA, *Clinical Decision Support Software*, final guidance, 6 Jan 2026, re-issued 29 Jan 2026; CDRH town hall transcript, 11 Mar 2026. https://www.fda.gov/regulatory-information/search-fda-guidance-documents/clinical-decision-support-software
- FDA, "Spilling the Beans: How Much Caffeine is Too Much?" (consumer update). https://www.fda.gov/consumers/consumer-updates/spilling-beans-how-much-caffeine-too-much
- MHRA, *Medical devices: software applications (apps)*, updated 1 Jul 2023. https://www.gov.uk/government/publications/medical-devices-software-applications-apps
- Health Canada, *Software as a Medical Device (SaMD): Definition and Classification*, 18 Dec 2019, §2.2. https://www.canada.ca/en/health-canada/services/drugs-health-products/medical-devices/application-information/guidance-documents/software-medical-device-guidance-document.html
- TGA, *Understanding the general health or wellness software exclusion* (item 14B, Therapeutic Goods (Excluded Goods) Determination 2018). https://www.tga.gov.au/resources/guidance/understanding-general-health-or-wellness-software-exclusion
- Apple, App Store Review Guidelines (1.4.1, 2.3, 2.5.1, 4.5.4, 5.1.1–5.1.3). https://developer.apple.com/app-store/review/guidelines/
- Apple, HealthKit "Protecting user privacy". https://developer.apple.com/documentation/healthkit/protecting-user-privacy
- Apple, `UNNotificationInterruptionLevel`; WWDC21 session 10091. https://developer.apple.com/documentation/usernotifications/unnotificationinterruptionlevel
- FTC, *Complying with FTC's Health Breach Notification Rule* (2024 amendments). https://www.ftc.gov/business-guidance/resources/complying-ftcs-health-breach-notification-rule-0
- FTC, *Health Products Compliance Guidance* (Dec 2022). https://www.ftc.gov/business-guidance/resources/health-products-compliance-guidance

Peer-reviewed and trial registry:

- Bidargaddi N, et al. To prompt or not to prompt? A microrandomized trial of time-varying push notifications. *JMIR mHealth uHealth* 2018;6(11):e10123. https://mhealth.jmir.org/2018/11/e10123
- Fitz N, et al. Batching smartphone notifications can improve well-being. *Computers in Human Behavior* 2019;101. https://scholars.duke.edu/publication/1402953
- Mehrotra A, et al. My phone and me: understanding people's receptivity to mobile notifications. *CHI* 2016. https://discovery.ucl.ac.uk/id/eprint/1502364/
- Künzler F, et al. Exploring the state-of-receptivity for mHealth interventions. *Proc ACM IMWUT* 2019; Mishra V, et al. Detecting receptivity for mHealth interventions. *IMWUT* 2021. https://arxiv.org/abs/2011.08302
- Eisele G, et al. The effects of sampling frequency and questionnaire length on perceived burden, compliance, and careless responding in experience sampling data. *Assessment* 2022. https://cris.maastrichtuniversity.nl/en/publications/the-effects-of-sampling-frequency-and-questionnaire-length-on-per/
- Wrzus C, Neubauer AB. Ecological momentary assessment: a meta-analysis on designs, samples, and compliance across research fields. *Assessment* 2022;30(3). https://pmc.ncbi.nlm.nih.gov/articles/PMC9999286
- Klasnja P, et al. Efficacy of contextually tailored suggestions for physical activity (HeartSteps). *Ann Behav Med* 2018/2019;53(6):573–582. https://pmc.ncbi.nlm.nih.gov/articles/PMC6401341
- Stawarz K, Cox AL, Blandford A. Beyond self-tracking and reminders: designing smartphone apps that support habit formation. *CHI* 2015:2653–2662. https://discovery.ucl.ac.uk/id/eprint/1468224/
- Wood W, Neal DT. A new look at habits and the habit–goal interface. *Psychological Review* 2007;114(4):843–863.
- Lally P, et al. How are habits formed: modelling habit formation in the real world. *Eur J Soc Psychol* 2010;40(6):998–1009.
- Wood C, et al. The impact of asking intention or self-prediction questions on subsequent behavior: a meta-analysis. *Pers Soc Psychol Rev* 2016;20(3):245–268; Wilding S, et al. *Eur Rev Soc Psychol* 2016. https://www.frontiersin.org/articles/10.3389/fpsyg.2016.00879/full
- Shephard A, Barrett SP. Cue reactivity in daily coffee consumers (balanced-placebo design), 2021. https://pmc.ncbi.nlm.nih.gov/articles/PMC8905124
- Burke LE, Wang J, Sevick MA. Self-monitoring in weight loss: a systematic review. *J Am Diet Assoc* 2011;111(1):92–102. https://pubmed.ncbi.nlm.nih.gov/21185970/
- NCT07555262, Reminder strategies to improve meal-logging adherence (registered, no results). https://clinicaltrials.gov/study/NCT07555262
- Gardiner C, et al. The effect of caffeine on subsequent sleep: a systematic review and meta-analysis. *Sleep Med Rev* 2023;69:101764. https://doi.org/10.1016/j.smrv.2023.101764
- Lovallo WR, et al. Caffeine stimulation of cortisol secretion across the waking hours in relation to caffeine intake levels. *Psychosom Med* 2005;67(5):734–739. https://pubmed.ncbi.nlm.nih.gov/16204431/
- Basner M, Mollicone D, Dinges DF. Validity and sensitivity of a brief psychomotor vigilance test (PVT-B) to total and partial sleep deprivation. *Acta Astronautica* 2011;69(11–12):949–959.
- Hilditch CJ, McHill AW. Sleep inertia: current insights. *Nat Sci Sleep* 2019;11:155–165. https://pmc.ncbi.nlm.nih.gov/articles/PMC6710480
