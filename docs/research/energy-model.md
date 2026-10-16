# Energy model: research and implementation spec

Status: research proposal, 2026-10-15. No app code changed. Branch `claude/research-energy-model`.
Scope: the model behind "Modeled alertness": sleep/wake dynamics, circadian phase, multi-day debt, sleep inertia, and the pharmacodynamic (PD) effect of caffeine.
Out of scope: caffeine concentration over time (caffeine research agent) and sleep-episode definitions and the check-in scale (`docs/research/sleep-and-check-in.md`, commit 99928d5). This spec consumes both.

**[E]** marks an established finding from a cited source. **[I]** marks our inference or a product choice.

## 1. Summary

1. Replace `alertness-1` with the **Unified Model of Performance (UMP)** and its caffeine extension (Ramakrishnan 2016a, 2016b). This is the model behind the US Army's open-access 2B-Alert tool, and its group-average parameters are published.
2. It is the only published model that covers all of Aurora's inputs in one validated set of equations: sleep/wake history, multi-night debt (a 7-day time constant), time of day, and dose-dependent caffeine. Validation spans 12 studies, 22 conditions and 301 people. It is closed-form and cheap on device.
3. Feed it recorded asleep intervals only. A missing night is never treated as wakefulness or as zero. The run restarts after a gap from the model's no-debt state, and confidence is shown.
4. Show 0–100 on an honest, anchored scale: 100 is the model's best on a well-rested day, and 0 is its level after a night without sleep. Show the native unit ("≈ N lapses on a 10-min reaction test, group average") in details. Anchor circadian phase to the person's usual sleep timing.
5. Biggest caveats: (a) the circadian time convention must be checked against 2B-Alert before release (§4.2); (b) the UMP has no sleep-inertia or post-lunch-dip term; (c) its caffeine kinetics are fitted to performance, not plasma.

## 2. Current Aurora model

All files are under `AuroraCore/Sources/AuroraCore/`.

| Term | Code | Behaviour |
|---|---|---|
| Score | `Algorithms.swift:96-122` | `clamp(30 + 50C + 40E − 40S − 100I, 0, 100)`. Weights at `:99-103` |
| C, circadian | `Algorithms.swift:25-31` | `0.5 − 0.5·cos(2π(hour−3)/24)` on the **whole** local hour. Trough at 03:00, peak at 15:00, no step within an hour |
| E, caffeine | `Algorithms.swift:6-22` | `1 − e^(−activeMg/100)`. Active mg halves per half-life (default 5 h, `Models.swift:123`). No absorption phase |
| S, sleep debt | `Algorithms.swift:60-75` | `(target − asleep in last 24 h)/target`, target default 8 h (`Models.swift:124`). No memory past 24 h |
| I, inertia | `Algorithms.swift:77-94` | `0.15·e^(−min/45)` for ≤ 90 min after the latest episode. Brief awakenings ≤ 30 min are joined (`:36`) |
| No-score gate | `Summary.swift:46-47` | No sleep in the last 24 h gives `.needsSleep` |
| Snapshot | `EnergyEstimate.swift:207-307` | `modelVersion "alertness-1"` (`:212`); contributions are the five additive terms (`:251-264`); limitation "generic daily curve" (`:57`) |
| Curve | `EnergyProjection.swift:10-82` | 30-min grid, ±12 h. Points after now assume no new records |
| Outlook | `EnergyOutlook.swift:26-34` | Peak and low windows within 3 points; "similar" within 5 points of the 7-day mean |

What the literature says is missing:
- One night of memory. Deficits accumulate over 7–14 nights and take several nights to clear [E] (Van Dongen 2003; Belenky 2003; Banks 2010).
- Caffeine is additive and capped. Its measured effect is larger when impairment is larger [E] (Ramakrishnan 2016b; Priezjev 2023). It also starts with an absorption delay.
- The circadian phase is fixed to the clock. It should follow the person's sleep timing [E] (Burgess & Eastman 2005).
- The weights are unsourced.

## 3. Evidence: models compared

| Model | Inputs | Output | Validation | Complexity | Fit for Aurora |
|---|---|---|---|---|---|
| Two-process (Borbély 1982; Daan 1984) | Sleep/wake | Sleep pressure S vs circadian thresholds | Sleep timing and EEG slow-wave activity. Not an alertness predictor on its own | Very low | Foundation only. It fails on chronic restriction [E] (McCauley 2009) |
| Three-Process Model, TPM (Åkerstedt & Folkard 1997; Åkerstedt 2004) | Sleep/wake (or work hours), chronotype | Alertness 1–21 and **KSS 1–9** (`KSS = 10.6 − 0.6·(S+C)`) | Field data: 136 aircrew and 8,040 KSS ratings (Ingre 2014). Residual SD 1.42 KSS; EEG/EOG and driving-simulator links | Low, closed form | Strong runner-up. Native subjective scale. **No caffeine.** Chronic debt only through a "brake" at S = 12.5 |
| SAFTE/FAST (Hursh 2004) | Sleep/wake, sleep quality, time zone | "Effectiveness" 0–100% | Lab and rail/aviation field use; in the 2004 model comparison (Van Dongen 2004) | Medium. Commercial tool; full current parameters not openly maintained | Its 0–100 is attractive, but caffeine is not in the published equations and the current version is proprietary |
| McCauley 2009/2013 | Sleep/wake | PVT lapses | Chronic restriction and total deprivation lab data. Bifurcation at a critical daily wake duration | Medium (coupled ODEs, dynamic circadian amplitude) | Good science, but the UMP builds on it and adds caffeine |
| **UMP** (Rajdev 2013; Ramakrishnan 2016a) | Sleep/wake | PVT lapses or mean RT | Fitted on one study, tested on five more (14 conditions): average error 7–36%; predictions within 2 SE 87% of the time | Low: 8 parameters, piecewise closed form | **Recommended** |
| **UMP + caffeine / 2B-Alert** (Ramakrishnan 2014, 2016b; Reifman 2016, 2022) | Sleep/wake + caffeine dose and time | PVT lapses or mean RT | 14 conditions, 6–27% error. Caffeine cut error 29–71% vs no caffeine term (2016b). 12 studies, 22 conditions, 301 people: group RMSE 43 ms, 80% within prediction interval; individualised for 81% of people (Priezjev 2023) | Low: +4 parameters | **Recommended.** Only option covering all inputs |
| Arousal-dynamics models (Phillips–Robinson; Postnova 2018) | Sleep/wake + **light** | Sleepiness, performance | Lab and shift-work data | High (stiff ODEs, light history) | Needs light exposure Aurora does not have |
| Prior-sleep rules (Dawson & McCulloch 2005) | Sleep in last 24/48 h | Fatigue-likelihood bands | Fatigue-risk practice | Trivial | No time of day or caffeine; useful as a descriptive summary (the sleep agent already provides it) |

Model comparisons agree that models predict **group averages** reasonably and individuals poorly. Individual vulnerability to sleep loss is trait-like and large [E] (Van Dongen 2004a, 2004b; Mallis 2004).

**Why the UMP over the TPM [I].** Caffeine is half of Aurora, and the TPM has no caffeine term. Its authors noted caffeine was "presently being implemented" in 2004 and nothing was published since. The UMP handles multi-night debt with a validated 7-day time constant. It also has a published path to personalisation from reaction-time tests (Liu 2017; Priezjev 2023), and Aurora already has a Reaction Test. The TPM's advantage is its native KSS output, and the sleep agent recommends adopting KSS for check-ins. See open question Q2.

## 4. Recommended model

Time `t` is in hours. P is predicted 10-minute PVT lapses (RT ≥ 500 ms). Parameters are the group-average **lapse** set (Ramakrishnan 2016b, Table 3; same values in Priezjev 2023 Table S1) [E].

### 4.1 Equations

```
P0(t) = S(t) + κ·C(t)                              performance impairment, caffeine-free
Pc(t) = P0(t) · gPD(t)                             with caffeine, 0 < gPD ≤ 1

Wake  (over dt since the last state change):
  S ← U − (U − S)·e^(−dt/τw)
  L ← max(U − (U − L)·e^(−dt/τLA), −0.11·U)
Sleep:
  S ← −2U + (2U + S)·e^(−dt/τs) + (2U + L)·[τLA/(τLA − τs)]·(e^(−dt/τLA) − e^(−dt/τs))
  L ← max(−2U + (2U + L)·e^(−dt/τLA), −0.11·U)

C(h) = Σ_{i=1..5} a_i · sin(2π·i·(h − φ − shift)/24)     h = local clock hour (see 4.2)

Caffeine (one dose c, in grams, at t0):
  kc   = k0·e^(−z·c),  Mc = M0·c
  gPD  = 1 / (1 + Mc·ka/(ka − kc)·(e^(−kc(t−t0)) − e^(−ka(t−t0))))      t ≥ t0
```

The L equations are the closed form of `L = U·Debt` with `dDebt/dt = (Loss − Debt)/τLA`, where Loss = +1 awake and −2 asleep (Ramakrishnan 2016a, Table 2). Debt is therefore neutral at a 2:1 wake:sleep ratio, which is 8 h of sleep a day. That is the model's built-in sleep need [E/I].

| Parameter | Value | Unit | Source |
|---|---|---|---|
| U (upper asymptote) | 18.4 | lapses | Ramakrishnan 2016b T3 (2016a fit: 18.35) |
| τw (wake time constant) | 40.0 | h | 2016b T3 |
| τs (sleep time constant) | 2.1 | h | 2016b T3 |
| κ (circadian amplitude) | 3.3 | lapses | 2016b T3 |
| φ (circadian phase) | 2.3 | h | 2016b T3 (convention: §4.2) |
| τLA (debt time constant) | 7.0 d = 168 h | h | 2016b T3 |
| L floor | −0.11·U = −2.024 | lapses | 2016b Table 2; Priezjev 2023 Table 2 |
| a1…a5 | 0.97, 0.22, 0.07, 0.03, 0.001 | – | 2016a/b Table 2 |
| M0 | 9.86 | g⁻¹ | 2016b T3 (lapses) |
| k0 | 0.49 | h⁻¹ | 2016b T3 |
| z | 1.63 | g⁻¹ | 2016b T3 (SE 1.61, weakly identified) |
| ka | 2.06 (capsule), 3.21 (gum) | h⁻¹ | 2016b T3, from Kamimori 2002 |

The mean-RT set (U = 497 ms, τw = 23 h, τs = 4 h, κ = 75 ms, φ = 2.5 h, M0 = 3.59 g⁻¹) is an alternative output. Lapses fit Aurora's Reaction Test definition (`Vigilance.swift:118`, 500 ms).

### 4.2 Circadian phase

- **Time convention [I, blocking check].** The papers write `sin(2πi(t + φ)/τ)` without defining t's origin. Reading t as clock hours puts peak impairment at about 02:00. Well-rested people would then be at their worst at 23:00, which contradicts the authors' own simulation statements: worst 06:00–11:00 and best 18:00–23:00 after 4 h of nocturnal sleep (2016a, p. 259), and morning troughs under deprivation (2016b).
  - `h − φ` with h as local clock hour reproduces all of them. It gives circadian impairment peaking at about 06:15 and lowest at about 22:15. Deprivation then peaks at 06:45, and the 4 h night is worst at 09:30 and best at 19:45.
  - This also matches physiology: the performance nadir follows the core-temperature minimum, and there is a wake maintenance zone 2–3 h before habitual bedtime [E] (Strogatz 1987; Lavie 1986; Shekleton 2013; de Zeeuw 2018).
  - Before release, compare one schedule against 2B-Alert Web output or the authors' code.
- **Anchor: recorded sleep timing [E for the principle, I for the rule].**
  - Melatonin onset sits about 2.2–2.3 h before habitual bedtime. Wake time predicts it (r = 0.78 in free sleepers) [E] (Burgess & Eastman 2005; Martin & Eastman 2002).
  - The UMP's φ was fitted on subjects sleeping about 23:00–07:00 (midpoint 03:00). So `shift = usualMidpoint − 03:00`, with `usualMidpoint` taken from the sleep agent's `UsualTiming` (circular median, at least 7 main sleeps in 14 days).
  - Clamp the shift to ±3 h. Most night workers never fully realign [E] (Folkard 2008), and the TPM likewise shifts phase by only 1–2 h for chronotype (Åkerstedt 2004; Ingre 2014: about 0.67 h per chronotype step).
  - With no `UsualTiming`, use shift 0 and keep the "generic daily curve" limitation.
- **Afternoon dip [E].** A post-lunch dip exists independently of meals (Monk 2005). The TPM models it as a 12-h component (amplitude 0.5 of 21; it improved fit, Ingre 2014). The **UMP has none**, so its curve rises steadily through the afternoon. Say so in limitations; do not bolt one on.

### 4.3 Sleep inertia (constants left to this report)

- [E] Inertia dissipates as a saturating exponential. The time constant is 0.67 h for subjective alertness and 1.17 h for cognitive performance, with the asymptote reached after 2–4 h (Jewett 1999).
- [E] The TPM's W term uses a decay of 1.51 h⁻¹ (τ = 0.66 h), consistent with Jewett. Its magnitude is −5.72 on the 1–21 scale, about 3.4 KSS points at waking (Ingre 2014; Åkerstedt 2004). In aircrew field data, adding W *worsened* fit (Ingre 2014).
- [E] Inertia is worse after deprivation and on waking near the circadian low (Tassi & Muzet 2000; Hilditch & McHill 2019).
- **Recommendation [I].** The UMP has no inertia term, and no lapse-scale magnitude is published. Do not add one to the score. Instead:
  - for **90 min** after the end of `lastMain` (about 1.3 τ for performance and 2.2 τ for subjective alertness), mark the score and curve points "Just woke";
  - add the line "Grogginess after waking isn't in this model. It usually fades within the first hour or two."
- This retires `0.15`, `45` and `90` from the score.

### 4.4 Multi-day debt and recovery

- [E] Chronic 4–6 h nights produce dose-dependent, cumulative PVT deficits over 14 days (Van Dongen 2003). Lapses were predicted by cumulative wake beyond 15.84 h/day.
- [E] Three recovery nights of 8 h did not restore performance after 7 nights of 3–5 h (Belenky 2003). One 10-h recovery night was insufficient after 5 nights of 4 h (Banks 2010). One hour of habitual debt took 4 days of extended sleep to repay (Kitamura 2016).
- In the UMP this is the L process with τLA = 7 d. About 51% of a schedule change is absorbed after 5 days and 86% after 14 days [E, model property].
- So **14 days** of history matter. The sleep agent's 5-recorded-night minimum is a sensible confidence threshold.

### 4.5 Caffeine PD and the PK boundary

- [E] gPD is a Hill-type (n = 1) effect on a Bateman-shaped "effective amount". With `A(t) = c·ka/(ka−kc)·(…)`, gPD = 1/(1 + M0·A(t)), so EC50 = 1/M0 ≈ **101 mg** of effective caffeine.
  - The effect is multiplicative: caffeine removes a *fraction* of impairment, so its absolute benefit grows with sleep loss (consistent with Landolt 2012 as cited by Priezjev 2023).
- [E] The UMP's kc (0.49 h⁻¹ at low dose; 0.35 h⁻¹ at 200 mg, a 2.0 h effect half-life) is **fitted to performance**, not plasma. Plasma half-life is about 5 h (the authors cite 4.7–6.4 h).
- **Interface decision [I]:**
  - The score uses the UMP's own fitted kinetics, the only validated PD pairing.
  - The caffeine agent's plasma-concentration model drives the "active caffeine" display and the cutoff features.
  - Feeding a 5-h plasma curve into this Hill function is unvalidated and would roughly double the modeled duration of benefit. The half-life preference therefore no longer changes the score (Q4).
- **Repeated doses [E for the principle, I for the formula].** Ramakrishnan 2014 gives an "equivalent dose" extension: dose j's elimination rate uses `D_j + E(t_j⁻)`, where E is the effective caffeine still present. Only fragments of the exact formula were accessible (patent US 11,241,194). Implement it as:
  - `A(t) = Σ_j A_j(t)`, where `A_j` is the single-dose curve for `D_j` with `k_j = k0·e^(−z·(D_j + A(t_j⁻)))`;
  - gPD = 1/(1 + M0·A(t)). This reduces exactly to the single-dose equation.
  - Check it against the 2014 paper before release.
- Absorption: default ka = 2.06 h⁻¹ (capsule), or 3.21 h⁻¹ for gum. Beverage-specific ka belongs to the caffeine agent. If it differs, pass it in, but the validation used capsule or gum only.

### 4.6 Uncertainty

- [E] Prediction intervals are `Pc ± z·√(σp² + σm²)`. PVT noise σm was about 2.1 lapses (2016b, study V1). Group RMSE was 1.3–2.4 lapses for under 33 h of deprivation.
  - On the display scale (10.6 points per lapse) that is about ±14–26 points of group error before individual differences.
- [I] Show a qualitative **confidence** label, not a numeric band (§6.4).

## 5. Constant trace table

| Constant (file:line) | Current | Recommended | Source | Confidence |
|---|---|---|---|---|
| `Alertness.baseline` (Algorithms:99) | 30 | Remove. Score = anchored map of Pc (§6.5) | Ramakrishnan 2016b | High |
| `circadianWeight` (:100) | 50 | κ = 3.3 lapses | 2016b T3 | High (value), Medium (time convention) |
| `caffeineWeight` (:101) | 40 | Multiplicative gPD; M0 9.86 g⁻¹ | 2016b T3 | High |
| `sleepDebtWeight` (:102) | 40 | S/L dynamics: U 18.4, τw 40 h, τs 2.1 h, τLA 168 h | 2016b T3 | High |
| `inertiaWeight` (:103) | 100 | Remove from score; 90-min "Just woke" flag | Jewett 1999; Ingre 2014 | Medium |
| Caffeine scale `100` mg (:21) | 100 | EC50 = 1/M0 ≈ 101 mg effective | 2016b | High |
| Instant absorption (:9-16) | none | ka 2.06 h⁻¹ (3.21 gum) | Kamimori 2002 via 2016b | High |
| Effect elimination (via `halfLife`, Models:123) | 5 h | k0 0.49 h⁻¹, z 1.63 g⁻¹ (effect, not plasma) | 2016b T3 | Medium (z SE large) |
| `Circadian` cosine, trough 03:00, whole hour (:28-31) | as coded | 5 harmonics a1…a5, φ 2.3 h, continuous time, + `shift` | 2016a/b; Burgess 2005 | Medium |
| `targetSleepHours` in score (Summary:16-24) | 8 | Not used by the score; implicit 8 h need (Loss +1/−2) | 2016a | High (model), Q3 (product) |
| 24-h debt window (Algorithms:61-68) | 24 h | Up to 14 wake days of recorded run | Van Dongen 2003; Belenky 2003 | High |
| `briefAwakeningMs` (:36) | 30 min | Sleep agent's 90-min episode rule | sleep-and-check-in R2 | Medium |
| Inertia 90 min / τ 45 / 0.15 (:92) | as coded | Flag window 90 min; no score term | Jewett 1999 | Medium |
| — (new) S_on, L_on warm start | – | 5.84595, 0.86891 | Steady state of 2016b equations [I] | High (derivation) |
| — (new) P_best, P_zero anchors | – | 1.9736, 11.3779 lapses | Computed, §6.7 [I] | High (derivation) |
| — (new) phase shift clamp | – | ±3 h | Folkard 2008; Ingre 2014 [I] | Low–Medium |
| `EnergyEstimate.currentVersion` (:210) | 2 | 3 | – | – |
| `currentModelVersion` (:212) | "alertness-1" | "ump-lapse-1" | – | – |
| `itemizedMinimumMg` (:86) | 0.01 | Unchanged (evidence only) | – | – |
| `EnergyProjection` 30 min, ±12 h (Projection:12-14) | as coded | Unchanged | – | – |
| `EnergyOutlook.windowTolerance` (Outlook:29) | 3 pts | Keep (≈ 0.28 lapses); re-check on device | [I] | Low |
| `EnergyOutlook.similarWithin` (:34) | 5 pts | Keep (≈ 0.47 lapses) | [I] | Low |

## 6. Implementation spec (AuroraCore, pure functions)

### 6.1 Signatures

```swift
public enum UMP {  // all hours, lapses
    public static let U = 18.4, tauW = 40.0, tauS = 2.1, kappa = 3.3, phi = 2.3, tauLA = 168.0
    public static let harmonics: [Double] = [0.97, 0.22, 0.07, 0.03, 0.001]
    public static let lFloor = -0.11 * U
    public static let onsetS = 5.84595, onsetL = 0.86891   // warm start, no prior debt
    public struct State: Equatable, Sendable { public var s: Double; public var l: Double }
    public static func wake(_ x: State, hours: Double) -> State
    public static func sleep(_ x: State, hours: Double) -> State
    public static func circadian(localHour: Double, shiftHours: Double) -> Double
}

public enum CaffeinePD {
    public static let m0 = 9.86, k0 = 0.49, z = 1.63, kaDefault = 2.06   // g⁻¹, h⁻¹, g⁻¹, h⁻¹
    /// Effective caffeine (g), repeated-dose rule of §4.5.
    public static func effectiveGrams(at t: Millis, doses: [Dose]) -> Double
    public static func factor(at t: Millis, doses: [Dose]) -> Double  // 1/(1 + m0·A)
}

public struct ModelRun: Equatable, Sendable {
    public var startEpisode: SleepEpisodeV2          // first episode of the recorded run
    public var asleep: [Interval]                    // asleep intervals in the run, merged
    public var recordedNights: Int                   // wake days in the run, ≤ 14
    public var shiftHours: Double                    // clamped; 0 without UsualTiming
}

public enum EnergyModel {
    public static let maxRunDays = 14
    public static let pBest = 1.9736, pZero = 11.3779
    public static let inertiaFlagMs: Millis = 90 * minuteMs
    public static func run(episodes: [SleepEpisodeV2], summary: RecentSleepSummary,
                           usual: UsualTiming?, now: Millis, clock: LocalClock) -> ModelRun?
    public static func lapses(at t: Millis, run: ModelRun, doses: [Dose], clock: LocalClock) -> Double
    public static func displayScore(lapses: Double) -> Double   // §6.5, unrounded
    public static func confidence(run: ModelRun, summary: RecentSleepSummary, usual: UsualTiming?) -> ModelConfidence
}
public enum ModelConfidence: String, Codable, Sendable { case high, medium, low }
```

`SleepEpisodeV2`, `RecentSleepSummary` and `UsualTiming` are the sleep agent's types (sleep-and-check-in §6). The energy model adds no sleep definitions of its own.

### 6.2 Inputs and state

- **Sleep [aligned with the sleep agent's R2/R3].**
  - Episodes come from `SleepEpisodes.build` (90-min join; `inBed` never counts).
  - The simulation sleeps only during the episodes' **asleep intervals**. Naps and short episodes inside the run count as sleep.
  - The gate and confidence use `RecentSleepSummary`.
- **Recorded run.**
  - Walk back over wake days from the latest day with a recorded episode. If today has no main sleep yet, start from yesterday (sleep agent S6).
  - Include each day whose `nights` entry is non-nil. Stop at the first day with no record, or after 14 days.
  - The run is never bridged by imputing a night [aligned: the sleep agent's "missing nights are not imputed"].
- **Initial state [I].** At the start of the run's first episode, set `State(s: onsetS, l: onsetL)`. This is the model's no-debt equilibrium at sleep onset; the authors made the same "negligible prior debt" assumption when baseline sleep was unknown (2016b). Then step through episodes in closed form.
- **No state is stored between days.** Recomputing 14 days is under about 60 closed-form steps per point, about 3,000 steps for a 49-point curve. Nothing persists, so edited or deleted records take effect immediately and snapshots stay reproducible.
- **Caffeine.** Doses known at the instant (`EnergyProjection.knownRecords`) within the last 24 h; older doses have gPD ≥ 0.99. All sources count.

### 6.3 The 24-h curve

- Keep `EnergyProjection`'s grid.
- Compute the run once at capture from records known at capture. Each point t is `lapses(at: t)`, with the wake segment extended from the last recorded wake.
- Projected points assume no further sleep or caffeine, as now. Points inside recorded sleep are not drawn.
- Points with t < `lastMain.end + inertiaFlagMs` carry `justWoke = true`.

### 6.4 Missing-data rules

| Situation | Behaviour |
|---|---|
| `asleepLast24h == 0` (including `inBed`-only) | No score, unchanged (`.needsSleep`). The engine could compute a 24-h-awake value, but cannot tell an all-nighter from a missing record |
| Last record > 24 h ago but within 48 h | No score (same gate). Details may say "Last sleep recorded \<day\>" |
| Gap in the run (a wake day with no record) | Restart at the next recorded episode with the warm start. Earlier debt is forgotten: the model then **under-states** debt (golden H vs C) |
| Fewer than 7 main sleeps in 14 days | `shift = 0`; keep the `genericCircadian` limitation |
| Partial night (for example the Watch died) | Counted as recorded short sleep, so debt is **over-stated**. Name this limitation |
| Confidence | High: run ≥ 5 nights **and** `UsualTiming` present. Medium: run 2–4, or ≥ 5 without `UsualTiming`. Low: run = 1. Always show "group-average model" |

### 6.5 Display mapping

`score = clamp(100 · (pZero − Pc) / (pZero − pBest), 0, 100)`, rounded with `jsRoundInt`.

- `pBest = 1.9736` is the lowest waking Pc on the reference day: 14 recorded nights of 23:00–07:00, no caffeine, shift 0. It occurs at 19:34.
- `pZero = 11.3779` is Pc at 07:00 after that schedule plus one night without sleep.
- One display point is 0.094 lapses, and one lapse is 10.6 points.
- Label: **"Modeled alertness · 100 = this model's best on a well-rested day · 0 = after a night without sleep."**
- Details: "≈ 3.3 lapses on a 10-minute reaction test (group average)", rounded to 0.1.
- Never compare this with Aurora's 60-second Reaction Test. A 60-s test is not the 10-min PVT; the validated brief version is the 3-min PVT-B (Basner 2011).
- Contributions (`EnergyContribution`) become `homeostatic` (S), `sleepDebt` (L, as its share of S), `timeOfDay` (κC) and `caffeine` (`Pc − P0`), in lapses. The baseline term goes away.
- KSS-native display was rejected for the score because the UMP does not predict KSS (Q2).

### 6.6 Contribution and evidence

`EnergyEvidence` keeps its record list. Add `runStart`, `runNights`, `shiftHours`, `confidence` and `justWoke`. `limitations` adds:
- `noInertia`: "Grogginess just after waking isn't modeled."
- `noAfternoonDip`: "The early-afternoon dip isn't modeled."
- `groupAverage`: "Based on group averages from published lab studies; individuals differ."

### 6.7 Golden tests

Fixtures:
- Local zone UTC (no DST). "Night d" means 23:00 on day d to 07:00 on day d+1. Day 0 is today. shift = 0 unless stated. All sleep is asleep and recorded.
- Expected values come from an independent Python implementation of §4.1 with the §4.2 convention. Tolerances: Pc ± 0.002 lapses, score ± 0.05 before rounding.

| # | Scenario | Time | Pc (lapses) | Score | Current model |
|---|---|---|---|---|---|
| A | 14 nights 23:00–07:00 (nights −14…−1), no caffeine | 09:00 | 3.343 | **85.43 → 85** | 55 |
| | | 15:00 | 2.686 | **92.42 → 92** | 80 |
| | | 21:00 | 2.056 | **99.13 → 99** | 55 |
| | | 07:30 / 12:00 / 23:00 | 3.072 / 3.166 / 2.608 | 88 / 87 / 93 | 35 / 73 / 42 |
| A1 | Only last night 23:00–07:00 recorded | any | = A (warm start) | = A | = A |
| B | A, but last night 02:00–07:00 | 09:00 / 15:00 / 21:00 | 4.610 / 3.776 / 2.994 | 72 / 81 / 89 | 40 / 65 / 40 |
| C | 7 nights 23:00–07:00, then 7 nights 01:00–07:00 | 09:00 / 15:00 / 21:00 | 6.366 / 5.287 / 4.295 | 53 / 65 / 75 | 45 / 70 / 45 |
| C2 | 14 nights 01:00–07:00 | 09:00 / 15:00 / 21:00 | 7.377 / 6.158 / 5.044 | 43 / 56 / 67 | 45 / 70 / 45 |
| D | A + 200 mg at 08:00 | 08:00 / 09:00 / 12:00 / 15:00 | 3.187 / 1.412 / 2.007 / 2.238 | 87 / 100 / 100 / 97 | 79 / 88 / 100 / 100 |
| D2 | C + 200 mg at 08:00 | 09:00 / 12:00 / 15:00 | 2.688 / 3.784 / 4.405 | 92 / 81 / 74 | 78 / 90 / 91 |
| E | A + 100 mg 08:00 + 100 mg 13:00 (repeated-dose rule) | 13:00 / 14:00 | 2.595 / 1.611 | 93 / 100 | 100 / 100 |
| F | 14 nights 01:00–09:00, shift +2 h | 11:00 / 17:00 / 23:00 | 3.343 / 2.686 / 2.056 | 85 / 92 / 99 (= A, 2 h later) | 68 / 77 / 42 |
| F0 | Same sleeps, shift 0 | 11:00 / 17:00 | 2.450 / 1.540 | 95 / 100 | – |
| H | C, but wake day −2 has no record (run = last 2 nights) | 09:00 / 15:00 | 4.482 / 3.666 | 73 / 82 (vs C 53 / 65) | – |
| I | Engine only: A, then no sleep last night | 07:00 | 11.378 | 0 (UI shows no score) | 2 |

Unit checks:
- gPD for one dose at +0.5/1/2/4/8 h:
  - 100 mg: 0.640 / 0.603 / 0.659 / 0.811 / 0.958
  - 200 mg: 0.466 / 0.422 / 0.468 / 0.634 / 0.877
- Steady state: at wake S = −0.3284, L = −0.8828; at onset S = 5.8460, L = 0.8689.
- C(h) maximum at 06:15, minimum at 22:15 (15-min grid).

## 7. Migration

- **Shifts.**
  - Well-rested days rise sharply, especially in the evening (A: 55/80/55 → 85/92/99). The new curve is flat and high for rested people, and lowest mid-morning.
  - Short single nights read milder (B at 09:00: 40 → 72).
  - Repeated short nights read lower and carry forward over days (C2 at 15:00: 70 → 56).
  - On rested days caffeine often saturates at 100. After debt it helps much more (D2: 53 → 92 at 09:00).
  - The "Highest / Lowest around" outlook will move later in the day.
- **Labelling.** Bump `modelVersion` to `ump-lapse-1` and `EnergyEstimate.currentVersion` to 3.
  - Old snapshots keep `alertness-1` and their stored numbers, labelled "Earlier model".
  - Show a one-time card: "Modeled alertness now uses a published model (Unified Model of Performance, Ramakrishnan et al. 2016) and your last 14 days of sleep. Scores before \<date\> used Aurora's earlier model and aren't comparable."
  - `EnergyOutlook`'s 7-day comparison recomputes from records, so it is consistent; never compare stored old-model scores with new ones.
- **Tests.** Existing `Alertness.score` golden values all change. Keep `alertness-1` reachable only for decoding old snapshots.

## 8. Open questions for the product owner

1. **Q1 (blocking): circadian time convention.** Approve verifying §4.2 against 2B-Alert Web, or contacting the authors (BHSAI), before release.
2. **Q2: lapses (UMP) or KSS (TPM)?** The UMP models objective vigilance and has caffeine. The TPM models subjective sleepiness, which matches the KSS check-in the sleep agent recommends, but has no caffeine. Recommendation: UMP for the score, and compare KSS check-ins only with the person's own history.
3. **Q3: personal sleep need.** The UMP assumes 8 h (Loss +1/−2). Scaling the ratio to the user's target is plausible but unvalidated [I]. Recommendation: do not scale in v1; show the sleep agent's shortfall beside the score.
4. **Q4: half-life setting.** Under this spec it no longer affects the score (§4.5). Keep it for "active caffeine" only, or retire it from score-related copy?
5. **Q5: inertia.** Is a "Just woke" flag acceptable instead of a score penalty, given there is no published UMP-scale magnitude?
6. **Q6: confidence display.** A qualitative label only, or also a shaded band (about ±20 points of group error)?
7. **Q7: personalisation later.** The published path needs repeated PVTs (about 27 to learn a person; Priezjev 2023). Aurora's 60-s test would need to become a validated brief PVT (for example the 3-min PVT-B) first.
8. **Q8: travel and night work.** Accept the ±3 h clamp and the rolling usual-timing anchor? The UMP authors note it does not model time-zone change (2016a). The TPM literature uses about 1 h/day (Åkerstedt 2004) or 30%/day (Ingre 2014) re-entrainment.

## 9. Known limitations and failure modes

- **Group averages.** Trait-like individual differences are large (Van Dongen 2004b). Subjects were young to middle-aged healthy adults.
- **Shift work.** Phase is clamped. Daytime sleep after nights is shorter and less restorative than the model assumes (Åkerstedt 2004 notes truncated day sleep). Night-shift estimates will be optimistic.
- **Naps and polyphasic sleep.** Handled by S/L. The UMP's split-sleep predictions were reasonable (2016a). There is no inertia after naps.
- **Travel.** The phase follows recorded sleep within ±3 h, and the immediate post-flight days are wrong (Waterhouse 2007).
- **Caffeine.**
  - Tolerance and withdrawal are not modeled; the authors argue simple RT tasks are little affected (2016b).
  - Effect duration may shorten with high debt, which was observed but not modeled (2016b).
  - z is weakly identified.
- **Missing data.** Restarts forget earlier debt, and partial nights inflate debt.

## 10. Sources

- Åkerstedt T, Folkard S, Portin C. Predictions from the three-process model of alertness. Aviat Space Environ Med 2004;75(3 Suppl):A75–83. PMID 15018268
- Åkerstedt T, Folkard S. The three-process model of alertness and its extension to performance, sleep latency, and sleep length. Chronobiol Int 1997;14:115–123. doi:10.3109/07420529709001149
- Banks S, et al. Neurobehavioral dynamics following chronic sleep restriction: dose-response effects of one night for recovery. Sleep 2010;33:1013–1026. doi:10.1093/sleep/33.8.1013
- Basner M, Mollicone D, Dinges DF. Validity and sensitivity of a brief psychomotor vigilance test (PVT-B). Acta Astronaut 2011;69:949–959. doi:10.1016/j.actaastro.2011.07.015
- Belenky G, et al. Patterns of performance degradation and restoration during sleep restriction and subsequent recovery. J Sleep Res 2003;12:1–12. doi:10.1046/j.1365-2869.2003.00337.x
- Borbély AA. A two process model of sleep regulation. Hum Neurobiol 1982;1:195–204. PMID 7185792
- Burgess HJ, Eastman CI. The dim light melatonin onset following fixed and free sleep schedules. J Sleep Res 2005;14:229–237. doi:10.1111/j.1365-2869.2005.00470.x (abstract figures from SLEEP 2003 abstract 0235.E, https://stacks.cdc.gov/view/cdc/201004)
- Daan S, Beersma DG, Borbély AA. Timing of human sleep: recovery process gated by a circadian pacemaker. Am J Physiol 1984;246:R161–R183. doi:10.1152/ajpregu.1984.246.2.R161
- Dawson D, McCulloch K. Managing fatigue: it's about sleep. Sleep Med Rev 2005;9:365–380. doi:10.1016/j.smrv.2005.03.002
- de Zeeuw J, et al. The alerting effect of the wake maintenance zone during 40 hours of sleep deprivation. Sci Rep 2018;8:11012. doi:10.1038/s41598-018-29380-z
- Folkard S. Do permanent night workers show circadian adjustment? Chronobiol Int 2008;25:215–224. doi:10.1080/07420520802106835
- Hilditch CJ, McHill AW. Sleep inertia: current insights. Nat Sci Sleep 2019;11:155–165. doi:10.2147/NSS.S188911
- Hursh SR, et al. Fatigue models for applied research in warfighting. Aviat Space Environ Med 2004;75(3 Suppl):A44–53
- Ingre M, et al. Validating and extending the three process model of alertness in airline operations. PLoS One 2014;9:e108679. doi:10.1371/journal.pone.0108679
- Jewett ME, et al. Time course of sleep inertia dissipation in human performance and alertness. J Sleep Res 1999;8:1–8. https://pubmed.ncbi.nlm.nih.gov/10188130/
- Kitamura S, et al. Estimating individual optimal sleep duration and potential sleep debt. Sci Rep 2016;6:35812. doi:10.1038/srep35812
- Lavie P. Ultrashort sleep-waking schedule III: "gates" and "forbidden zones" for sleep. Electroencephalogr Clin Neurophysiol 1986;63:414–425
- Liu J, Ramakrishnan S, Laxminarayan S, Balkin TJ, Reifman J. Real-time individualization of the unified model of performance. J Sleep Res 2017
- Mallis MM, et al. Summary of the key features of seven biomathematical models of human fatigue and performance. Aviat Space Environ Med 2004;75(3 Suppl):A4–14
- Martin SK, Eastman CI. Sleep logs of young adults with self-selected sleep times predict the dim light melatonin profile. Chronobiol Int 2002;19:695–707
- McCauley P, et al. A new mathematical model for the homeostatic effects of sleep loss on neurobehavioral performance. J Theor Biol 2009;256:227–239. doi:10.1016/j.jtbi.2008.09.012
- McCauley P, et al. Dynamic circadian modulation in a biomathematical model for the effects of sleep and sleep loss on waking neurobehavioral performance. Sleep 2013;36:1987–1997. doi:10.5665/sleep.3246
- Monk TH. The post-lunch dip in performance. Clin Sports Med 2005;24:e15–e23. doi:10.1016/j.csm.2004.12.002
- Postnova S, et al. Prediction of cognitive performance and subjective sleepiness using a model of arousal dynamics. J Biol Rhythms 2018;33:203–218. doi:10.1177/0748730418758454
- Priezjev NV, Vital-Lopez FG, Reifman J. Assessment of the unified model of performance: accuracy of group-average and individualised alertness predictions. J Sleep Res 2023;32:e13626. doi:10.1111/jsr.13626 (https://bhsai.org/pubs/Priezjev_2023_Assessment_of_the_unified_model.pdf)
- Rajdev P, et al. A unified mathematical model to quantify performance impairment for both chronic sleep restriction and total sleep deprivation. J Theor Biol 2013;331:66–77. doi:10.1016/j.jtbi.2013.04.013
- Ramakrishnan S, et al. Dose-dependent model of caffeine effects on human vigilance during total sleep deprivation. J Theor Biol 2014;358:11–24. doi:10.1016/j.jtbi.2014.05.017
- Ramakrishnan S, Wesensten NJ, Balkin TJ, Reifman J. A unified model of performance: validation of its predictions across different sleep/wake schedules. Sleep 2016a;39:249–262. doi:10.5665/sleep.5358 (https://bhsai.org/pubs/Ramakrishnan_2016_A_Unified_Model_of_Performance.pdf)
- Ramakrishnan S, et al. A unified model of performance for predicting the effects of sleep and caffeine. Sleep 2016b;39:1827–1841. doi:10.5665/sleep.6164 (https://bhsai.org/pubs/Ramakrishnan_2016_A_Unified_Model_Of_Performance2.pdf)
- Reifman J, et al. 2B-Alert Web: an open-access tool for predicting the effects of sleep/wake schedules and caffeine consumption on neurobehavioral performance. Sleep 2016;39:2157–2159
- Reifman J, et al. 2B-Alert Web 2.0, an open-access tool for predicting alertness and optimizing the benefits of caffeine. J Med Internet Res 2022;24:e29595. doi:10.2196/29595
- Shekleton JA, et al. Improved neurobehavioral performance during the wake maintenance zone. J Clin Sleep Med 2013;9:353–362. doi:10.5664/jcsm.2588
- Strogatz SH, Kronauer RE, Czeisler CA. Circadian pacemaker interferes with sleep onset at specific times each day. Am J Physiol 1987;253:R172–R178
- Tassi P, Muzet A. Sleep inertia. Sleep Med Rev 2000;4:341–353. doi:10.1053/smrv.2000.0098
- US Patent 11,241,194, Method and system for measuring, predicting, and optimizing human cognitive performance (repeated-dose fragments). https://patents.google.com/patent/US11241194B2/en
- Van Dongen HPA, et al. The cumulative cost of additional wakefulness. Sleep 2003;26:117–126. doi:10.1093/sleep/26.2.117
- Van Dongen HPA. Comparison of mathematical model predictions to experimental data of fatigue and performance. Aviat Space Environ Med 2004a;75(3 Suppl):A15–36
- Van Dongen HPA, et al. Systematic interindividual differences in neurobehavioral impairment from sleep loss. Sleep 2004b;27:423–433. doi:10.1093/sleep/27.3.423
- Vital-Lopez FG, et al. Caffeine dosing strategies to optimize alertness during sleep loss. J Sleep Res 2018;27:e12711. doi:10.1111/jsr.12711
- Waterhouse J, et al. Jet lag: trends and coping strategies. Lancet 2007;369:1117–1129. doi:10.1016/S0140-6736(07)60529-7
