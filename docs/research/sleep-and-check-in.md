# Sleep inputs and the energy check-in: research and spec

Status: research proposal, 2026-10-15. No app code changed. Branch `claude/research-sleep`.
Scope: sleep need, sleep episodes, the recent-sleep summary, usual timing, and the self-rated check-in.
The alertness model, caffeine and the Reaction Test belong to other agents. This report supplies their sleep inputs and definitions.

Throughout, **[E]** marks an established finding from a cited source. **[I]** marks our inference or a product choice.

## 1. Summary

1. Stop pre-selecting 8 h. Ask for a target with nothing selected. Show the AASM/SRS "7 or more hours" and NSF "7–9 hours" as context. Do not derive the target from history: habitual sleep can sit about 1 h below need.
2. Use one episode rule everywhere. Join asleep intervals across gaps under 90 min. The main sleep is the longest episode of at least 3 h on a wake day. Never count `inBed` as asleep.
3. One night is not enough evidence for the model. Deficits build over 7–14 nights and take several nights to clear. Give the model last-24 h, last-48 h and a 7-wake-day summary. Missing nights are not imputed, and the 7-day summary needs 5 recorded nights.
4. Show usual timing as the circular median of sleep midpoint and wake time. Require 7 main sleeps in 14 days, and 14 in 30 days before showing a spread. Defer the Sleep Regularity Index (SRI).
5. Replace the 1–5 energy item with the Karolinska Sleepiness Scale (KSS, 1–9, every step labelled), once the licence is confirmed. Keep old 1–5 ratings as a labelled earlier scale; never convert them. Show ratings and Reaction Tests separately, comparing each only with the person's own history.

## 2. Current behaviour

| Area | What the code does | Where |
|---|---|---|
| Target default | `defaultTargetSleep = 8`, in `Prefs.defaults` | `AuroraCore/Sources/AuroraCore/Models.swift:124`, `:128` |
| Setup | Range 5–10 h, step 0.5, presets 7/8/9. A skip keeps 8 h ("Sleep target stays at…"). The outcome is stored in `onboarding.setupOutcomes` | `Onboarding+Copy.swift:7-9`, `Welcome.swift:264`, `Models.swift:177` |
| Display episodes | Grouped by `SleepType`. A session joins when its start is less than 90 min after the group's latest end (`<`). Duration is the union | `Sleep.swift:57`, `:86-127` |
| Brief awakening | 30 min, joined with `<=`. Used for inertia, the evidence episode and Health night counts | `Algorithms.swift:36`, `:40-53`, `:80-93`; `EnergyEstimate.swift:176`; `HealthImport.swift:89-91` |
| Main sleep | Longest `.sleep` episode per local wake day, with no minimum length. The chart sums every episode of the day, naps included | `Sleep.swift:146-157`, `:236`, `:240-248` |
| Health categories | Reads asleep raw values {1, 3, 4, 5}. Drops `inBed` (0) and `awake` (2). Every Health session is typed `.sleep` | `HealthImport.swift:85`, `:69`; `Aurora/Services/HealthKitService.swift:99` |
| Sleep debt | `clamp((target − asleep last 24 h)/target, 0, 1)`, weight 40. No sleep in 24 h gives `.needsSleep` | `Algorithms.swift:61-74`, `:102`; `Summary.swift:46-47` |
| Usual night | Manual `.sleep` only, last 30 days, 3–16 h, at least 3 nights. Median bedtime with a fixed +12 h shift, then median duration. Used to propose a manual draft | `Assistant.swift:220-243` |
| Check-in | `rating` 1–5, "Your energy, from 1 (very low) to 5 (very high)". Labels Very low…Very high. Segmented picker with nothing selected | `EnergyCheckIn.swift:8-9`, `:24-33`; `AssistantCardView.swift:488-499` |
| Check-in display | Listed under "Recorded by you · shown separately", never plotted against the model. CSV export has a `rating,label` column | `EnergyCardViews.swift:134-160`; `EnergyCards.swift:32`, `:201-205` |

**Problems found.**

- Two different gap rules (90 min `<`, 30 min `<=`) both define an "episode". A night with one 45-minute awakening counts as two nights on import, but as one on the chart.
- With no minimum length, a 40-minute sample can become "Most Recent Sleep" and be compared with the nightly target.
- An iPhone-only user, whose Health data holds only `inBed`, gets "No recent sleep found".

## 3. Evidence

### Q1. Sleep need and the default target

- **[E]** The AASM/SRS consensus says adults should sleep **7 or more hours** a night regularly. It adds that more than 9 h may be appropriate for young adults, people recovering from sleep debt, and people who are ill (Watson 2015).
- **[E]** The NSF recommends **7–9 h** for adults aged 18–64 and **7–8 h** from age 65. It added a "may be appropriate" band to reflect individual variation: 6 h or 10 h for ages 26–64, and 6 h or 10–11 h for ages 18–25 (Hirshkowitz 2015). The 65+ band of 5–6 h or 9 h is recalled from the paper's Table 1; we could not fetch the table to confirm it.
- **[E]** Individual need varies. In Kitamura 2016, 15 young men were given 12 h in bed for 9 nights. Their optimal duration averaged 8.41 h, ranging from 7.29 to 9.26 h. Their habitual home sleep averaged 7.37 h, a potential debt of about 1.04 h.
- **[I]** History is therefore a poor stand-in for need. A target derived from the last N nights would treat chronic short sleep as normal.
- **[I]** A pre-selected 8 h breaks the "no pre-filled values" rule. It also silently drives the debt term for anyone who skipped setup.

### Q2. Defining an episode from consumer data

- **[E] HealthKit structure.** `inBed` samples mark time in bed. Stage samples (`awake`, `asleepCore`, `asleepDeep`, `asleepREM`, `asleepUnspecified`) overlap the in-bed sample but not each other. Apple Watch writes `awake` only between two sleep samples (Apple, HKCategoryValueSleepAnalysis).
  - Stage segments abut. A union with zero gap rebuilds the asleep time; Aurora already does this.
- **[E] Duplicate sources.** Developers report that the Health app's displayed totals differ from a raw union of samples. Apple publishes no reconciliation rule.
  - **[I]** Keep the union for now (duplicates count once), but treat cross-source overlap as an open question.
- **[E] iPhone without a Watch** records time in bed from phone use, not sleep (Apple support, iOS 13 archive; Apple Community 2026).
  - **[I]** Time in bed overstates sleep by the time taken to fall asleep plus time awake in bed. It must stay separately labelled.
- **[E] Gap thresholds used in research pipelines:**
  - GGIR's sleep-period detector merges rest blocks of at least 30 min that are separated by gaps under **60 min** (`spt_min_block_dur = 30`, `spt_max_gap_dur = 60`) (GGIR docs; van Hees 2018).
  - The ABCD Study Fitbit pipeline starts a new episode after a **90 min** gap. It needs **180 min** for main sleep and anchors days at 12:00 (`gap = 90`, `main_duration = 180`, `offset = "12:00"`).
  - Fitbit's default `isMainSleep` splits a night at wake bouts of 1 h or more. In 8,563 All of Us participants, a user-centric re-grouping reclassified 4.75% of logs as primary sleep, and found 17.6 min more total sleep in the most variable sleepers (Master 2025).
- **[E] Naps.** GGIR classifies naps only within a configured window and duration. Its example is 15–240 min between 09:00 and 18:00, and there is no universal standard.
- **[E] Accuracy of the trackers:**
  - In a 2025 study of six trackers against polysomnography (PSG), the Apple Watch Series 8 detected sleep with 96.3% sensitivity but wake with only 52.2% specificity. It overestimated total sleep by +19.6 min and underestimated waking after sleep onset by 21.2 min. Stage agreement was moderate (κ = 0.53, the best of six). It caught 50.7% of deep sleep and 68.6% of REM (Schyvens 2025, n = 20 with usable data).
  - Other studies show the same pattern: sleep sensitivity of 93–95% or more and weak wake detection (Chinoy 2021; Robbins 2024).
  - **[I]** Use asleep and wake *timing* from wearables. Do not use stage minutes in any calculation. Never show stages as fact.

### Q3. Sleep debt and recovery

- **[E] Van Dongen 2003.** 48 adults spent 4, 6 or 8 h in bed for 14 days.
  - Lapses rose near-linearly with cumulative wakefulness beyond **15.84 h** a day, which implies about 8.2 h of sleep a day.
  - 6 h or less for 14 days matched up to 2 nights of total sleep deprivation.
  - Sleepiness ratings rose at first, then barely moved. They did not separate the 6 h and 4 h groups.
- **[E] Belenky 2003.** People spent 3, 5, 7 or 9 h in bed for 7 nights, then had 3 recovery nights of 8 h.
  - Only the 9 h group stayed at baseline.
  - The 3 h group improved after one recovery night but stayed below baseline. The 5 h and 7 h groups did not recover in 3 nights.
- **[E] Banks 2010.** After 5 nights at 4 h, one recovery night of 10 h in bed (8.96 h asleep) still left PVT lapses, KSS ratings and fatigue short of full recovery.
- **[E] Kitamura 2016.** About 1 h of potential debt took **about 4 days** to recover.
- **[E] Dawson & McCulloch 2005.** This fatigue-risk model judges fatigue from sleep in the **prior 24 h and 48 h**. It is a published, simple, prior-sleep summary.
- **[I] Implications:**
  - A 24 h window misses the multi-night accumulation these studies show.
  - Recovery is slower than one hour back for each hour lost, so a surplus night should not fully cancel earlier shortfall.
  - No validated consumer weighting exists, whether exponential or otherwise. A plain 7-wake-day window, with a count of recorded nights, is the most defensible choice and the easiest to explain.

### Q4. Usual timing and regularity

- **[E] Midpoint and social jetlag.** The MCTQ uses mid-sleep on free days, corrected for sleep debt (MSFsc), as a chronotype marker (Roenneberg 2003/2004). Social jetlag is the difference in mid-sleep between workdays and free days (Wittmann 2006).
  - Aurora does not know which days are free days. **[I]** Do not compute social jetlag.
- **[E] SRI.** The SRI is the probability of being in the same sleep/wake state at time points 24 h apart (Phillips 2017). It predicted mortality better than duration did in UK Biobank (Windred 2024).
  - It needs continuous, consecutive-day state data.
  - Two open-source calculators put only about two-fifths of people in the same quintile (Cedernaes 2025, on Czeisler et al.).
- **[E] How many nights.**
  - Standard deviation and interdaily stability need more than a week for unbiased estimates (Fischer 2021).
  - Total sleep time from actigraphy needs more than 7 nights; diary-based measures need at least 6 (Aili 2017).
  - A large wearable cohort found 1–2 weeks insufficient for variability metrics (WHOOP-affiliated press material, secondary).
- **[I]** Show the circular median midpoint and wake time from main sleeps. Hold back any spread until there are 14 nights, matching Aurora's existing 14-night gate for caffeine timing.

### Q5. Check-in scale

| Scale | Construct | Points, wording | Validity against objective measures | Licence |
|---|---|---|---|---|
| **KSS** (Åkerstedt & Gillberg 1990) | Sleepiness, preceding 5 min | 9 points, verbal anchors. Version B labels every step | Correlates with EEG alpha/theta and with performance (Kaida 2006). Within-person r = 0.75 with PVT lapses over 40 h awake; ratings rose about 3 h before performance fell (Manousakis 2021). Versions A and B agree (weighted κ = 0.73; Miley 2016) | No formal licence found. Widely reproduced; the Springer chapter says to obtain it from the authors. **Needs confirmation** |
| **SSS** (Hoddes 1973) | Sleepiness | 7 descriptive statements | Good for total deprivation, less sensitive to partial restriction. May mix activation and sleepiness | Widely reproduced; no formal licence found |
| **Samn-Perelli** (USAF 1982) | Fatigue | 7 points, "fully alert, wide awake" to "completely exhausted" | Most sensitive subjective measure in a firefighter simulation, but explained little PVT variance (Ferguson 2016) | US Air Force report, probably a public-domain US government work **[I]** |
| **VAS** (e.g. VAS-F, Lee 1991) | Fatigue/energy | 100 mm line | Concurrent validity with SSS and POMS. Criticised for blurring fatigue and sleepiness | Varies |
| **1–5 energy** (current) | Energy, undefined | 5 points | No validation found | Ours |

- **[E]** Fatigue and sleepiness are distinct constructs (Shen 2006).
- **[I]** Aurora's model estimates *alertness*, and the Reaction Test measures vigilance. Both line up with sleepiness, so the KSS fits best.
- **[I]** A 9-row list fits an iPhone at large text sizes. A 9-segment control does not.

### Q6. Showing self-ratings with objective measures

- **[E]** Under chronic restriction, subjective sleepiness levels off while performance keeps falling (Van Dongen 2003).
  - Within a person, KSS and PVT move together. Between people, the link is weak (Manousakis 2021).
  - Short PVTs lose sensitivity: the 3-minute PVT-B is the shortest validated brief form (Basner 2011).
  - **[I]** A 30-second test is shorter than any validated form. Call it a Reaction Test, never a PVT.
- **[I] Display rules:**
  - Show each measure in its own unit and with its own label.
  - Compare only with the person's own records.
  - Never combine them into one score, apply population cut-offs (for example "KSS ≥ 7 = impaired"), or tell people they are "more tired than you feel".

## 4. Recommendations

**R1. Sleep target**

- Remove the pre-selection: `targetSleep: Double?`, nil until chosen.
- Setup question: "How much sleep do you aim for on a typical night?"
- Context line: "Sleep experts recommend 7 or more hours for most adults; 7–9 hours is the usual adult range."
- Range 5–11 h, step 0.5, preset chips 7 / 8 / 9 with none selected.
- With no target set, show "No target set" wherever a comparison would appear.
- The model's reference when no target is set is product-owner option A or B (§8).

**R2. Episodes**

- Use only asleep values {1, 3, 4, 5} and form their union (touching intervals join).
- Group into episodes when the gap between consecutive asleep intervals is **under 90 min**, across sources and types. One constant replaces `episodeGapMs` and `briefAwakeningMs`.
- Episode asleep time is the union. The span (first start to last end) is kept separately.
- Kinds per local wake day:
  - `main`: the longest episode of **at least 180 min**. Ties go to the later wake.
  - `secondary`: any other episode of at least 180 min.
  - `short`: any other episode under 180 min.
  - `nap`: an episode containing a session the person typed as `.nap`, and not main.
- Naps and short sleep count toward the 24 h, 48 h and day totals, but not toward "last night versus target".
- Read `inBed` (0) separately as `TimeInBed`. Show it labelled "In bed (iPhone estimate)" only for intervals with no asleep data. Never count it as asleep unless the product owner chooses otherwise (§8).

**R3. Sleep summary for the model**

| Input | Definition |
|---|---|
| `asleepLast24h`, `asleepLast48h` | Union of asleep time overlapping `[now−24 h, now]` and `[now−48 h, now]` |
| `lastMain` | Most recent `main` episode ending at or before now, or nil |
| `nights` | 7 wake days, each `nil` (no record) or total asleep. The window ends today if today has a main sleep, otherwise yesterday |
| `recordedNights`, `meanAsleep` | Recorded days only, shown at 1 night or more |
| `shortfall` | Needs a target and at least 5 recorded nights: `max(0, Σ(target − dayTotal))` over recorded nights. Otherwise `nil` with the reason |
| `hoursSinceMainWake` | From `lastMain.end` |

A missing night is never 0. If the energy model wants recency weighting, that is its own choice and should be labelled **[I]**.

**R4. Usual timing**

- Use main sleeps from all sources in the last 14 days, requiring **at least 7**.
- Compute the circular median of the midpoint, sleep start and wake time: rotate so the circular mean sits at 12:00, take the median, then rotate back. This replaces the fixed +12 h shift, which fails for daytime sleepers.
- Show "Usual midpoint 3:00 AM · wake 7:00 AM · 8 nights".
- Show the middle-80% range only with at least 14 main sleeps in 30 days.
- `usualNight` (Assistant) should use the same function. Whether a draft may be proposed from history is §8 Q4.
- Defer SRI and social jetlag.

**R5. Check-in.** Use KSS version B verbatim, subject to the licence.

- Card title: "Sleepiness check-in"
- Instruction: "Rate your sleepiness during the 5 minutes before this rating."
- Anchors:
  1. Extremely alert
  2. Very alert
  3. Alert
  4. Rather alert
  5. Neither alert nor sleepy
  6. Some signs of sleepiness
  7. Sleepy, but no effort to keep awake
  8. Sleepy, some effort to keep awake
  9. Very sleepy, great effort to keep awake, fighting sleep
- Source line: "Karolinska Sleepiness Scale · your rating"
- Control: a 9-row single-choice list with nothing selected. VoiceOver reads "7, Sleepy, but no effort to keep awake".
- Higher means sleepier. That is the reverse of the old scale, so never draw the two on one axis.
- If the licence can't be confirmed, use the Samn-Perelli 7-point scale. It sits under the same `scale` field.

**R6. Joint display.** Keep "Recorded by you · shown separately".

- Each row: "Sleepiness 6 of 9 · Some signs of sleepiness" or "Reaction Test · 312 ms median".
- Each measure gets its own sparkline, against the person's own baseline only. Gate it at 3 tests in 30 days for Reaction, as today, and 5 ratings in 14 days for KSS **[I]**.
- No cross-measure statements, thresholds or diagnosis words.

## 5. Constant trace table

| Constant | Current | Recommended | Source | Confidence |
|---|---|---|---|---|
| `Prefs.defaultTargetSleep` | 8 h, pre-selected | nil until chosen; consensus reference 7 h only if §8 Q1 = B | Watson 2015; Hirshkowitz 2015; Kitamura 2016 | High (evidence), Medium (policy) |
| `sleepTargetRange` | 5–10 h | 5–11 h | NSF "may be appropriate" 6–11 (18–64); 5–9 (65+, recalled) | Medium |
| `sleepTargetStep` | 0.5 h | 0.5 h | — | — |
| `sleepTargetPresets` | 7/8/9, one pre-selected after skip | 7/8/9, none selected | NSF 7–9 | High |
| `SleepModel.episodeGapMs` | 90 min, `<`, per type | `episodeJoinGapMs` = 90 min, `<`, all types | ABCD Fitbit `gap = 90`; Master 2025; GGIR 60 | Medium |
| `SleepIntervals.briefAwakeningMs` | 30 min, `<=` | Retire (use 90 min) | As above | Medium |
| `HealthImport.countNights` gap | 30 min | Episode rule (90 min) | As above | Medium |
| Main-sleep minimum | none (`usualNight` 3 h) | 180 min | ABCD `main_duration = 180` | Medium |
| `HealthImport.asleepValues` | {1, 3, 4, 5} | Unchanged; `inBed` read separately | Apple HKCategoryValueSleepAnalysis | High |
| Stage minutes | not used | Never used in calculations | Schyvens 2025; Chinoy 2021 | High |
| `SleepDebt` window | 24 h only | 24 h + 48 h + 7 wake days | Van Dongen 2003; Belenky 2003; Dawson 2005 | High (multi-night), Low (weighting) |
| 7-day minimum | none | 5 recorded of 7 for `shortfall` | Aili 2017 (≥5 nights for sleep efficiency; >7 nights for total sleep time) | Low–Medium |
| Surplus credit | n/a | Signed sum, floored at 0 | Kitamura 2016; Banks 2010 suggest slower recovery | Low |
| `usualNight` window / minimum | 30 d / 3 nights, manual only | 14 d / 7 main sleeps, all sources | Fischer 2021; Aili 2017 | Medium |
| `usualNight` duration filter | 3–16 h | 3 h minimum (main), 16 h maximum for plausibility | ABCD; [I] | Low |
| Circular centre | fixed +12 h | rotate to circular mean | [I] (circular statistics) | Medium |
| Spread gate | none | 14 main sleeps in 30 d | Fischer 2021; Aurora's 14-night gate | Low–Medium |
| `EnergyCheckIn.scale` | 1...5 | 1...9 (`kss9`) | Åkerstedt 1990; Kaida 2006 | High (validity), pending (licence) |
| `scaleLabel` | "Your energy, from 1 (very low) to 5 (very high)" | "Rate your sleepiness during the 5 minutes before this rating." | Miley 2016 (5-minute frame) | High |
| `label(forRating:)` | Very low…Very high | KSS version B anchors (R5) | Miley 2016 | High |
| Legacy ratings | — | Keep as `energy5`, no conversion | Shen 2006 (distinct constructs) | High |
| `SleepInertia` 90 min / τ 45 / 0.15 | as coded | Out of scope (energy model agent) | — | — |

## 6. Implementation spec (AuroraCore, pure functions)

```swift
public enum SleepEpisodeKind: String, Codable, Sendable { case main, secondary, short, nap }

public struct SleepEpisodeV2: Equatable, Sendable {
    public var start: Millis, end: Millis        // span
    public var asleepMs: Millis                  // union of asleep intervals
    public var kind: SleepEpisodeKind
    public var wakeDayKey: String
    public var sessionIDs: [String]
}

public enum SleepEpisodes {
    public static let joinGapMs: Millis = 90 * minuteMs      // gap < joinGapMs joins
    public static let mainMinimumMs: Millis = 180 * minuteMs
    /// Sessions with end <= now and end > start; all sources and types.
    public static func build(_ sessions: [SleepSession], now: Millis, clock: LocalClock) -> [SleepEpisodeV2]
}

public struct RecentSleepSummary: Equatable, Sendable {
    public var asleepLast24hMs: Millis, asleepLast48hMs: Millis
    public var lastMain: SleepEpisodeV2?
    public var nights: [(dayKey: String, asleepMs: Millis?)]   // 7, oldest first
    public var recordedNights: Int
    public var meanAsleepMs: Millis?
    public var shortfallMs: Millis?
    public var shortfallUnavailable: ShortfallReason?   // .noTarget, .tooFewNights(recorded: Int, required: Int)
}
public enum RecentSleep {
    public static let minimumRecordedNights = 5
    public static func summarize(_ sessions: [SleepSession], targetHours: Double?, now: Millis, clock: LocalClock) -> RecentSleepSummary
}

public struct UsualTiming: Equatable, Sendable {
    public var midpointMinute: Int, startMinute: Int, wakeMinute: Int, nights: Int
    public var middle80Midpoint: ClosedRange<Int>?     // only at >= 14 in 30 d
}
public enum UsualSleepTiming {
    public static func compute(_ episodes: [SleepEpisodeV2], now: Millis, clock: LocalClock) -> UsualTiming?
    static func circularMedian(_ minutes: [Int]) -> Int
}

public enum CheckInScale: String, Codable, Sendable { case energy5, kss9 }
// EnergyCheckIn gains `scale: CheckInScale`; decodeIfPresent default .energy5.
```

Health service: add `inBedIntervals(after:)` beside `sleepChanges`, read-only, stored as `TimeInBed` records. These are never merged into `sleeps`.

**Check-in data migration**

- No rewrite and no schema bump is needed. A missing `scale` key decodes as `energy5`. Encode `scale` only when it is `kss9`, so old records keep their keys (the same pattern as `health`).
- `validate` checks per scale. New entries must be `kss9`. Editing a legacy entry keeps `energy5` and its 1–5 range.
- CSV adds a `scale` column (`energy5` / `kss9`).
- `ratingText` for legacy entries: "4 · High (earlier 1–5 energy scale)". For KSS: "7 of 9 · Sleepy, but no effort to keep awake".

**Golden tests** (clock UTC, D = 2026-03-02, times in local time, durations in minutes)

| # | Input | Expected |
|---|---|---|
| E1 | Health core 23:00–23:40, deep 23:40–00:20, core 00:20–01:30, awake 01:30–01:40 (dropped), REM 01:40–02:10, core 02:10–06:50 | 1 episode, span D-1 23:00–D 06:50, asleep **460**, kind main |
| E2 | Watch core 23:00–07:00 plus third-party asleepUnspecified 22:45–06:30 | 1 episode, asleep **495** (union), main |
| E3 | Asleep 23:00–02:00 and 03:15–07:00 (75-min gap) | 1 episode, asleep **405**, span 480, main. `countNights` = **1** (today 2) |
| E4 | Asleep 23:00–02:00 and 03:30–07:00 (gap exactly 90) | 2 episodes: main 03:30–07:00 **210**; secondary 23:00–02:00 **180**. Day total 390 |
| E5 | Asleep D-1 23:30–D 07:00, plus D 14:10–14:35 | main **450**, short **25**. Wake-day D total **475**. Last night = 450 |
| E6 | Only `inBed` D-1 23:00–D 07:00 | No episodes. `TimeInBed` 480 labelled. Estimate `.needsSleep` (Q2 option A) |
| E7 | Manual `.nap` 13:00–16:30, no other sleep that day | Kind **nap** (person's label wins), not main |
| E8 | Only Health asleep 03:00–05:00 on D | Kind **short** (120). No main for D. `lastMain` = previous main |
| E9 | Session ending after now | Excluded (current behaviour) |
| S1 | Target 8 h; 7 wake days = 7.0, 6.5, nil, 8.0, 5.5, 7.5, 6.0 h | recorded **6**, mean **405**, shortfall **450** |
| S2 | As S1 but the 8.0 night is 9.0 | mean **415**, shortfall **390** |
| S3 | 4 recorded nights | mean shown; shortfall nil, `.tooFewNights(4, 5)` |
| S4 | S1 with target nil | shortfall nil, `.noTarget` |
| S5 | now = D 18:00; D-2 23:30–D-1 06:30, D-1 23:00–D 07:00, nap D 14:00–14:30 | last 24 h **510**, last 48 h **930** |
| S6 | now = D 06:00, today has no main yet | `nights` ends D-1; D is not counted as missing |
| U1 | 8 mains: 4× 23:00–07:00, 3× 00:30–08:30, 1× 22:30–06:30 | midpoint **03:00**, wake **07:00**, nights 8, no range |
| U2 | 7 mains with midpoints 23:30, 23:40, 23:50, 00:00, 00:10, 00:20, 00:30 | midpoint **00:00**. A naive linear median would give 00:30 |
| U3 | 6 mains in 14 d | nil |
| U4 | 7 mains with midpoints near 12:30 (night worker) | circular median near 12:30, not shifted to 00:30 |
| C1 | Decode `{"id":"x","recordedAt":0,"rating":4}` | scale `energy5`, text "4 · High (earlier 1–5 energy scale)" |
| C2 | New `kss9` ratings 0, 10 / 1, 9 | invalid / valid |
| C3 | New entry with `energy5` | invalid ("Choose a rating from 1 to 9.") |
| C4 | Fresh draft | rating nil, save blocked, no row selected |
| C5 | Export of one legacy and one KSS rating | rows carry `energy5` and `kss9` in the `scale` column |
| C6 | Recent list mixing scales | KSS rows and "Earlier scale" rows grouped apart; no shared mean or chart |

## 7. Migration and labelling

- **Target.** On load, if `setupOutcomes["2"] == "skipped"` and `targetSleep == 8`, set the target to nil. Show "No target set" once, beside the target control in Settings. Targets the person chose are kept.
- **Episodes.** These are display and model changes only; stored sessions are untouched. Health night counts may fall, because split nights now merge. Release notes: "Nights with a long awakening now count as one night."
- **Check-ins.** Keep a labelled break: legacy rows read "Energy · earlier 1–5 scale". The first KSS card shows one line: "Check-ins now use the Karolinska Sleepiness Scale (1–9, higher is sleepier). Earlier ratings keep their 1–5 energy scale." Never convert or average across scales.
  - **[I]** A linear crosswalk (for example 5→1, 1→9) would invent precision between different constructs that run in opposite directions.
- **Copy rules.** Never use "debt" as a verdict, "impaired", "should sleep" or "need". Use "Recorded sleep, last 7 days: 6 of 7 nights, average 6 h 45 min · 7 h 30 min under your 8 h target across recorded nights."

## 8. Open questions for the product owner

1. **Model reference with no target.**
   - A: omit the debt term and label it.
   - B: use the 7 h consensus floor, labelled "Consensus reference, not yours".
   - Recommendation: B for the model, nothing pre-selected in the UI.
2. **iPhone time in bed.**
   - A: show it labelled, never counted.
   - B: count it as sleep with a "Time in bed (iPhone)" label.
   - Recommendation: A.
3. **KSS licence.** Will you ask Prof. Åkerstedt / Karolinska Institutet for written permission to use the KSS in a paid app? If not, adopt Samn-Perelli, after confirming the 1982 USAF report's public-domain status.
4. Does proposing a manual draft from the person's own history (`usualNight`) count as a pre-filled value? It is their data, but they did not enter it for this night.
5. **Cross-source overlap.** Should Aurora prefer Apple Watch over third-party sources in an overlap? Today it uses the union. A preference needs a source-priority setting, and HealthKit does not expose Health's priority list for sleep.
6. Is a 9-row list acceptable for the check-in card's height, or should it move to a sheet?

## 9. Sources

- Watson NF et al. Recommended amount of sleep for a healthy adult. *Sleep* 2015;38(6):843–4. doi:10.5665/sleep.4716; *J Clin Sleep Med* 2015;11(6):591–2. doi:10.5664/jcsm.4758. https://www.aasm.org/resources/pdf/adultsleepdurationconsensus.pdf
- Hirshkowitz M et al. NSF sleep time duration recommendations. *Sleep Health* 2015;1(1):40–3. doi:10.1016/j.sleh.2014.12.010
- Kitamura S et al. Estimating individual optimal sleep duration and potential sleep debt. *Sci Rep* 2016;6:35812. doi:10.1038/srep35812
- Van Dongen HPA et al. The cumulative cost of additional wakefulness. *Sleep* 2003;26(2):117–26. doi:10.1093/sleep/26.2.117
- Belenky G et al. Patterns of performance degradation and restoration during sleep restriction. *J Sleep Res* 2003;12(1):1–12. doi:10.1046/j.1365-2869.2003.00337.x
- Banks S et al. Neurobehavioral dynamics following chronic sleep restriction. *Sleep* 2010;33(8):1013–26. doi:10.1093/sleep/33.8.1013
- Dawson D, McCulloch K. Managing fatigue: it's about sleep. *Sleep Med Rev* 2005;9(5):365–80. doi:10.1016/j.smrv.2005.03.002
- Apple. HKCategoryValueSleepAnalysis. https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis
- Apple. Estimating Sleep Stages from Apple Watch (Oct 2025). https://www.apple.com/kr/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf
- Apple Support, iPhone time in bed (iOS 13 archive). https://support.apple.com/HT208655; Apple Community thread. https://discussions.apple.com/thread/256256776
- Apple Developer Forums, overlapping sleep samples. https://developer.apple.com/forums/thread/842919
- Schyvens AM et al. Performance validation of six wrist-worn sleep trackers vs PSG. *Sleep Adv* 2025;6(2):zpaf021. doi:10.1093/sleepadvances/zpaf021
- Chinoy ED et al. Performance of seven consumer sleep-tracking devices. *Sleep* 2021;44(5):zsaa291. doi:10.1093/sleep/zsaa291
- Robbins R et al. Accuracy of three commercial wearables for sleep tracking. *Sensors* 2024;24(20):6532. doi:10.3390/s24206532
- van Hees VT et al. Estimating sleep parameters using an accelerometer without sleep diary. *Sci Rep* 2018;8:12975. doi:10.1038/s41598-018-31266-z
- GGIR parameters vignette. https://cran.r-project.org/web/packages/GGIR/vignettes/GGIRParameters.html
- ABCD Study `compute_fitbit_sleep_table_ext`. https://software.nbdc-datahub.org/ABCDscores/reference/compute_fitbit_sleep_table_ext.html
- Master L et al. User-centric algorithm for Fitbit sleep in All of Us. *J Med Internet Res* 2025;27:e71718. doi:10.2196/71718
- Aili K et al. Reliability of actigraphy and subjective sleep measurements in adults. *J Clin Sleep Med* 2017;13(1):39–47. doi:10.5664/jcsm.6384
- Fischer D, Klerman EB, Phillips AJK. Measuring sleep regularity. *Sleep* 2021;44(10):zsab103. doi:10.1093/sleep/zsab103
- Phillips AJK et al. Irregular sleep/wake patterns… *Sci Rep* 2017;7:3216. doi:10.1038/s41598-017-03171-4
- Windred DP et al. Sleep regularity is a stronger predictor of mortality risk than sleep duration. *Sleep* 2024;47(1):zsad253. doi:10.1093/sleep/zsad253
- Cedernaes J, Sielaff B, Benedict C. Time to regularize sleep regularity. *Sleep* 2025. doi:10.1093/sleep/zsaf289
- Roenneberg T, Wirz-Justice A, Merrow M. Life between clocks. *J Biol Rhythms* 2003;18(1):80–90. doi:10.1177/0748730402239679; Roenneberg T et al. *Curr Biol* 2004;14(24):R1038–9. doi:10.1016/j.cub.2004.11.039
- Wittmann M et al. Social jetlag. *Chronobiol Int* 2006;23(1–2):497–509. doi:10.1080/07420520500545979
- WHOOP press release on sleep-variability data length (secondary). https://www.whoop.com/us/en/press-center/whoop-study-finds-one-to-two-weeks-of-sleep-data-isnt-enough-to-measure-sleep-variability/
- Åkerstedt T, Gillberg M. Subjective and objective sleepiness in the active individual. *Int J Neurosci* 1990;52(1–2):29–37. doi:10.3109/00207459008994241
- Kaida K et al. Validation of the KSS against performance and EEG variables. *Clin Neurophysiol* 2006;117(7):1574–81. doi:10.1016/j.clinph.2006.03.011
- Åkerstedt Miley A, Kecklund G, Åkerstedt T. Comparing two versions of the KSS. *Sleep Biol Rhythms* 2016;14(3):257–60. doi:10.1007/s41105-016-0048-8
- Manousakis JE et al. Awareness of sleepiness. *Psychophysiology* 2021;58(8):e13839. doi:10.1111/psyp.13839
- Hoddes E et al. Quantification of sleepiness. *Psychophysiology* 1973;10(4):431–6. doi:10.1111/j.1469-8986.1973.tb00801.x
- Samn SW, Perelli LP. Estimating aircrew fatigue. USAF SAM-TR-82-21, 1982.
- Ferguson SA et al. Fatigue in emergency services operations. *Int J Environ Res Public Health* 2016;13(2):171. doi:10.3390/ijerph13020171
- Lee KA, Hicks G, Nino-Murcia G. Validity and reliability of a scale to assess fatigue. *Psychiatry Res* 1991;36(3):291–8. doi:10.1016/0165-1781(91)90027-M
- Shen J, Barbera J, Shapiro CM. Distinguishing sleepiness and fatigue. *Sleep Med Rev* 2006;10(1):63–76. doi:10.1016/j.smrv.2005.05.004
- Basner M, Mollicone D, Dinges DF. Validity and sensitivity of a brief PVT (PVT-B). *Acta Astronaut* 2011;69(11–12):949–59. doi:10.1016/j.actaastro.2011.07.015
- Penn CBTI scale sheets (KSS, SSS, VAS-F), reproduced from Shahid et al., *STOP, THAT and One Hundred Other Sleep Scales*, Springer 2012. https://www.med.upenn.edu/cbti/
