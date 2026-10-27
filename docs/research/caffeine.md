# Caffeine research: kinetics, contents, sleep evidence

Research report and implementation spec, 2026-10-15. Scope: modeled caffeine
over time, drink contents, half-life and the cutoff math. **Out of scope:** how
caffeine changes alertness (pharmacodynamics), which belongs to the alertness
model owner. No app code was changed for this report.

Conventions: **Established** means stated by a peer-reviewed source or an
authority. **Inference** means my own derivation from those sources, with the
arithmetic shown. Confidence is High / Medium / Low.

## 1. Summary of recommendations

1. Adopt the standard **one-compartment oral model with first-order absorption** (the Bateman function, the same PK form used by 2B-Alert), with `ka = 4 h⁻¹`, `F = 1` and the person's half-life for elimination. Report **mg in the body**, not plasma concentration.
2. **Keep 5 h as the default half-life.** It sits inside the 2.7–9.9 h range measured in healthy adults. Explain the range in a read-only, cited note. Ask no health questions, and offer no factor multipliers.
3. **Cutoff:** solve on "caffeine not yet cleared" (still being absorbed plus already in the body). Unlike the in-body amount, this value always falls over time, so the cutoff stays well-defined. For the same inputs, the latest time moves about 15 minutes earlier.
4. **Presets state their serving:** Espresso 1 shot 63 mg, Drip coffee 8 fl oz 95 mg, Matcha 2 g 70 mg, Energy drink 16 fl oz 160 mg. Cold brew and pre-workout stay custom, because their caffeine varies too much for one preset.
5. Put the sleep evidence and the authorities' reference points in a static, cited "About the evidence" sheet. Never compare them with the person's own numbers. Remove the values that are pre-filled today (400 mg, 16:00, 80 mg) and the "likely to affect tonight's sleep" claim.

## 2. Current Aurora behaviour

Read at `claude/ui-review` 10b6b34.

| Area | Behaviour | Location |
|---|---|---|
| Decay | `Σ mg · 0.5^(elapsed / halfLife)` for doses at or before `now`; no absorption phase, so the full dose counts instantly | `AuroraCore/Sources/AuroraCore/Algorithms.swift:9-16` |
| Effect (pharmacodynamics, not mine) | `1 − e^(−mg/100)`, weight 40 | `Algorithms.swift:18-22`, `:101` |
| Default half-life | 5 h | `Models.swift:123` |
| Half-life range | Stepper from 0.5 to 16 h, step 0.5, footnote "Used to estimate active caffeine." | `Aurora/Screens/Settings/SettingsView.swift:56-59` |
| Personal reference | **Defaults to 400 mg** (the FDA figure); stepper 0–1000 mg | `Models.swift:130`, `SettingsView.swift:66-69` |
| Cutoff hour | **Defaults to 16:00** | `Models.swift:131` |
| Cutoff reminder copy | "Last call for caffeine" / "After {4 PM}, caffeine is likely to affect tonight's sleep." This is an evidence claim attached to a default the person never chose | `Onboarding+Copy.swift:129-136` |
| Presets | Espresso 60, Drip 95, Matcha 70, Energy 160 mg; no serving sizes shown | `CaffeineLog.swift:13-18` |
| Custom entry | **Pre-fills "80" mg and source "Drip"** (which doesn't match the Drip preset's 95) | `CaffeineLog.swift:59-61` |
| Custom sources | Espresso, Drip, Cold Brew, Tea, Matcha, Other | `CaffeineLog.swift:52` |
| Amount validation | Whole mg from 1 to 1999 | `CaffeineLog.swift:72` |
| Cutoff scenario | Every input starts empty. Solves `existing + amount·0.5^(h/t½) ≤ threshold` in closed form and rounds down to the minute. A 0 mg threshold is `unreachable` | `CutoffScenario.swift:203-287` |
| Cutoff labels | "Modeled with your half-life setting. An assumption, not measured." and "Not a recommendation or a safety limit." | `CutoffScenario.swift:10-11` |
| Energy evidence | Repeats the decay term inline instead of calling the shared function; itemizes entries with at least 0.01 mg | `EnergyEstimate.swift:86`, `:149-155` |
| Today chart | `activeMg` on a **60-minute grid** plus `now` | `Summary.swift:244-276` |
| Chart visibility | Shown when a dose was logged today or any point rounds to at least 1 mg | `Summary.swift:183-186` |
| Timing before sleep | Last dose within 12 h before sleep onset; needs 14 paired nights | `Sleep.swift:60`, `:201-203` |
| Insights | Dayparts 5–11, 11–17, 17–21, otherwise "Late"; drink-mix keyword buckets | `Insights.swift:182-191`, `:109-117` |
| Sample data | Drip 95, matcha 60, tea 70/40, cold brew 80, espresso 120 mg | `SampleData.swift:14-31` |
| Energy card copy | "{n} mg modeled as active, with a {h}h half-life." | `Aurora/Screens/Assistant/EnergyCardViews.swift:73` |

## 3. Evidence

### 3.1 Pharmacokinetics

**Absorption (Established).**
- Oral caffeine is essentially completely bioavailable: F = 108 ± 4 % versus IV (Blanchard & Sawers 1983).
- An aqueous solution peaks at 29.8 ± 8.1 min (Blanchard & Sawers 1983).
- Saliva caffeine peaks at about 42 min after coffee, 39 min after cola, and 67 min after capsules (Liguori 1997).
- Caffeine is absorbed in the small intestine in under 1 h (Temple 2017).

**Published model structure (Established).** In the unified model of performance and 2B-Alert (Ramakrishnan 2014, 2016; Reifman 2016, 2022), the caffeine factor uses the one-compartment, first-order absorption kernel `ka/(ka−kc)·(e^(−kc·t) − e^(−ka·t))`. Its parameter table, as reproduced in the group's patent (US 11,241,194 B2), gives:
- `ka` = 2.06 h⁻¹ for capsules and 3.21 h⁻¹ for gum;
- `k0` = 0.49 h⁻¹ as a dose-dependent basal elimination rate, with `kc = k0·e^(−z·dose)` and z = 1.63 g⁻¹.

Those rates were **fitted to vigilance (PVT) data, not to plasma**. A `kc` of 0.49 h⁻¹ means an effect half-life of about 1.4 h, far shorter than plasma caffeine.

- **Inference:** Aurora should adopt the 2B-Alert *PK form* but use *plasma* parameters for "mg in body". 2B-Alert's effect-rate constants belong to the alertness owner, if anywhere.
- **Coordination warning:** feeding Aurora's mg-in-body into 2B-Alert's `g_PD`, which already contains its own kinetics, would count the kinetics twice.
- **Confidence:** Medium. The parameter values come from the patent's table; the paper's supplement couldn't be retrieved (PMC blocked automated access).

**Choosing `ka` (Inference).** For a one-compartment model, `tmax = ln(ka/ke)/(ka−ke)`. With t½ = 5 h (ke = 0.1386 h⁻¹):

| ka (h⁻¹) | tmax | Matches |
|---|---|---|
| 2.06 (2B-Alert capsule) | 84 min | Capsules (67 min, Liguori) |
| **4.0 (recommended)** | **52 min** | Between beverages (39–42 min) and capsules; allows for sipping over 10–20 min |
| 5.0 | 44 min | Coffee and cola saliva peak |
| ≥ 6 | ≤ 39 min | Aqueous solution (30 min) |

`ka = 4 h⁻¹` gives tmax from 43 min (t½ 2.5 h) to 62 min (t½ 10 h). That falls within the observed 30–120 min. Confidence: Medium.

**Elimination half-life and modifiers.**

| Factor | Effect on half-life | Status | Source |
|---|---|---|---|
| Healthy adults | 2.7–9.9 h across individuals (n = 10); reviews give 3–7 h | Established | Blanchard & Sawers 1983; Temple 2017 |
| CYP1A2 activity | CYP1A2 does about 95 % of the metabolism; activity varies 5–6-fold; in one twin study, genetics explained 89 % of the variance in AUC | Established | Nehlig 2018; Grzegorzewski 2021 |
| Smoking | Roughly doubles clearance, so about halves half-life | Established | Temple 2017; Grzegorzewski 2021 |
| Oral contraceptives | About doubles half-life | Established | Temple 2017; Grzegorzewski 2021 |
| Pregnancy | On average 8.3 h longer, up to 16 h longer (late pregnancy) | Established | Temple 2017 |
| Fluvoxamine | 4.9 h → 56 h (single dose); 5 h → 31 h (steady state) | Established | Culm-Merdek 2005; Jeppesen 1996 |
| Other CYP1A2 inhibitors | Pipemidic acid and norfloxacin flagged; most drugs show no effect | Established | Grzegorzewski 2021 |
| Liver cirrhosis | Moderate to strong drop in clearance, highly variable | Established | Grzegorzewski 2021; Desmond 1980 |
| Age | Neonates 65–130 h; adult rates by about 6 months; no large young-versus-elderly difference reported | Established | Temple 2017; Blanchard & Sawers 1983b |
| Sex / menstrual phase | No marked difference | Established | Temple 2017 |

**Units (Established and inference).** Caffeine distributes throughout total body water (Grzegorzewski 2021), commonly reported as about 0.6 L/kg (Medium confidence). Plasma concentration is `C = A/V`, which needs body weight. Aurora doesn't ask for weight and shouldn't, so it should keep reporting the **amount in mg** (inference). A per-litre value is offered only as an optional function for the alertness owner, with V supplied by the caller.

### 3.2 Default half-life

- **Established:** healthy adult values cluster around 3–7 h, with an observed range of about 2.7–10 h.
- **Inference:** 5 h is near the centre, and it is already the default. Changing it would shift every existing user's curves for no gain in accuracy. Keep 5 h (Confidence: Medium-High).

Ways to present the range:

| Option | Description | Assessment |
|---|---|---|
| A. Editable number only (current) | Settings value with no explanation | Gives no help understanding the range |
| **B. Editable number + "What changes half-life" sheet (recommended)** | Read-only text: the typical range, then the factors in §3.1 with direction and source. Nothing is asked or stored | Informs without collecting health data |
| C. Factor chips that multiply the default | Smoking ×0.5, contraceptives ×2, pregnancy… | Collects sensitive health data, is imprecise (the effects interact and vary), and nudges a medical self-assessment |

Recommended sheet copy: "Half-lives measured in healthy adults range from about 3 to 10 hours. Smoking tends to shorten it. Hormonal contraceptives, pregnancy, some medicines (for example fluvoxamine) and liver disease can lengthen it a lot. Aurora uses only the number you set."

Also: raise the stepper's upper bound from 16 h to 24 h, because late pregnancy can exceed 16 h. The 0.5 h lower bound is below any reported adult value; see §8.

### 3.3 Drink contents

| Drink | Serving | Typical mg | Variability | Source | Confidence |
|---|---|---|---|---|---|
| Espresso | 1 shot (1 fl oz, about 30 g) | 63 (212 mg/100 g) | 48–317 mg per shop serving | USDA FDC SR Legacy 171891; Ludwig 2014 | High (lab value), Low (shops) |
| Brewed / drip coffee | 8 fl oz (237 g) | 95 (94.8) | 8 oz brewed 135, filter drip 179 (Health Canada) | USDA FDC "coffee, brewed, tap water" | High |
| Brewed coffee | 12 fl oz | 142 (scaled) | 113–247 per 12 oz | FDA | High |
| Specialty brewed coffee | 16 fl oz | 188 ± 36 | 58–259 per serving; one outlet 259–564 over 6 days | McCusker 2003 | High |
| Cold brew | 12–16 fl oz | about 150–205 | Recipe- and brand-dependent; no verified USDA entry | Brand disclosures (not verified) | Low |
| Black tea | 8 fl oz | 47 | 30–50 per 8 oz | FDA (71 per 12 oz); Health Canada | High |
| Green tea | 8 fl oz | 25–28 | 30–50 per 8 oz (Health Canada) | FDA (37 per 12 oz) | High |
| Matcha | 2 g (about 1 tsp) | about 38–89 | 18.9–44.4 mg/g of powder | Koláčková 2020 (as cited in reviews) | Medium-Low |
| Energy drink | 8.4 fl oz | 80 | 41–246 per 12 oz across brands | FDA; label (Red Bull) | Medium |
| Energy drink | 16 fl oz | 160 | as above | Label (Monster) | Medium |
| Cola | 12 fl oz | 34 (diet about 46) | 23–83 per 12 oz | FDA; Health Canada 36–46 | Medium-High |
| Pre-workout | 1 scoop | 150–300; meta-analysis standard 217.5 | Label-dependent | Gardiner 2023 | Low |

**Preset recommendations (Inference).**
- Use one label pattern: "Name · serving", for example "Drip coffee · 8 fl oz".
- Espresso: change 60 → **63 mg**.
- Drip: keep **95 mg**.
- Matcha: keep **70 mg**, labelled "2 g". It sits within the range, and there's too little data to justify moving it.
- Energy: keep **160 mg**, labelled "16 fl oz can".
- Optional additions: Black tea 8 fl oz 47 mg, Cola 12 fl oz 34 mg.
- Cold brew and pre-workout: don't make presets. Their caffeine varies 2–3× and the label is the better source, so Custom entry should say "Use the amount on the label or menu."
- Fix the custom draft (`CaffeineLog.swift:59-61`) to start empty, as the product rule requires.
- Sample data may keep its values: it is labelled sample data and spans realistic amounts.

### 3.4 Caffeine and sleep

| Study | Design | Finding | Model at bedtime, t½ 5 h, `A(t)` (Inference) |
|---|---|---|---|
| Drake 2013 | n = 12, 400 mg at 0, 3 or 6 h before habitual bedtime, at home | All three disrupted sleep. At 6 h, measured total sleep fell by more than 1 h, and people didn't notice | 400 mg at 6 h → 180 mg |
| Gardiner 2023 meta-analysis | 24 studies | Total sleep −45 min, efficiency −7 %, latency +9 min, waking after sleep onset +12 min, deep sleep −11.4 min. To avoid lost sleep: coffee (107 mg) at least 8.8 h before bed, pre-workout (217.5 mg) at least 13.2 h before | 107 mg at 8.8 h → 32.7 mg; 217.5 mg at 13.2 h → 36.2 mg |
| Landolt 1995 | n = 9 men, 200 mg at 07:10, sleep at 23:00 | Lower sleep efficiency and total sleep time, EEG changes. Saliva caffeine 3 µmol/L at bedtime | 200 mg at 15.8 h → 23 mg. 3 µmol/L ≈ 0.58 mg/L, which at V = 42 L is about 24 mg |
| Landolt 1995 (citing earlier work) | 100 mg just before sleep | Lower sleep efficiency and EEG changes | Up to 100 mg (still absorbing) |
| EFSA 2015 | Authority opinion | About 100 mg (1.4 mg/kg) may affect sleep in some adults, especially near bedtime | — |
| Weibel 2021 | n = 20 habitual users, 3 × 150 mg/day, last dose 8 h before bed | No difference in total sleep, latency or architecture; reduced sigma-band EEG | 150 mg at 8 h → 49 mg |
| Clark & Landolt 2017; Reichert 2022 | Reviews | Acute evening caffeine reliably prolongs sleep latency and lowers efficiency. Effects depend on dose, timing, tolerance and ADORA2A genotype | — |

**Inference:**
- The published lab and meta-analytic findings line up with roughly **20–40 mg modeled at bedtime** (under Aurora's 5 h model) as the lowest amounts where studies reported sleep effects, and with clear effects at **100 mg or more**.
- Habitual daytime users may show attenuated effects (Weibel).
- This is a back-calculation through an assumed half-life. It is not a measured threshold, and it shouldn't be presented as one.

Options that stay within the no-recommendation rule:

| Option | Description | Fits the rule? |
|---|---|---|
| A. No evidence context (current) | — | Yes; but the card says nothing about why a threshold matters |
| **B. Static "About the evidence" sheet (recommended)** | A link from the cutoff card and the half-life note to a fixed list of study findings with amounts, timing and citations. Not computed from, or compared with, the person's threshold | Yes: it describes studies and suggests no number |
| C. Contextual line beside the threshold | For example "Studies have reported effects from about 25 mg at bedtime" next to the input | Borderline: it anchors the input, so it acts as a soft default |
| D. Compare the threshold with the evidence | "Your threshold is above levels studied…" | No: it judges the person's choice |

Also replace the reminder body at `Onboarding+Copy.swift:133`. "Likely to affect tonight's sleep" is a claim attached to a time the person may never have chosen. Suggested replacement: "Your cutoff time, {time}."

### 3.5 Safety reference points

All Established:
- **FDA:** 400 mg/day is "not generally associated with negative effects" for most adults. People who are pregnant, trying to become pregnant or breastfeeding should ask their provider. The AAP advises against energy drinks for young people.
- **EFSA 2015:** single doses up to 200 mg and up to 400 mg/day raise no concern for healthy non-pregnant adults; up to 200 mg/day in pregnancy; 3 mg/kg/day for children and adolescents.
- **Health Canada:** 400 mg/day for adults; 300 mg/day when planning pregnancy, pregnant or breastfeeding; 2.5 mg/kg/day up to age 18.
- **ACOG:** under 200 mg/day in pregnancy.
- **AAP:** about 100 mg/day for ages 12–18, according to secondary sources (Medium confidence).

Options:

| Option | Assessment |
|---|---|
| A. Never mention them | Simplest. But today the 400 mg default echoes FDA silently while the footnote denies it is a safe amount, which is incoherent |
| **B. Cited reference section in the "About the evidence" sheet (recommended)** | Lists authorities, figures and populations verbatim with links. Not shown on Today, never compared with logged totals, and no "remaining" language |
| C. Show beside the Personal reference setting | Anchors the personal value to a regulatory figure, which is close to prescribing |
| D. Warn when an intake passes a figure | Prescriptive; violates `CopyRules` |

## 4. Recommended PK model

For dose `D` (mg) taken at `t₀`, with `τ = t − t₀` in hours, `ke = ln 2 / t½`, `ka = 4.0 h⁻¹` and `F = 1.0`:

```
Body amount (absorbed, not yet eliminated):
  A(τ) = F·D · ka/(ka − ke) · (e^(−ke·τ) − e^(−ka·τ)),   τ ≥ 0;   A = 0 for τ < 0

Not yet cleared (still absorbing + in body); always falls:
  N(τ) = F·D · (ka·e^(−ke·τ) − ke·e^(−ka·τ)) / (ka − ke),   N(0) = F·D,   dN/dτ = −ke·A ≤ 0

Peak delay:   tmax = ln(ka/ke) / (ka − ke)
Concentration (optional, alertness owner only):   C(τ) = A(τ) / V,   V ≈ 0.6 L/kg × weight
Limit when |ka − ke| < 1e−9:   A = F·D·ka·τ·e^(−ke·τ)
Several doses:   linear superposition, A_total(t) = Σ A_i(t − t_i)
```

Late in the curve, `A ≈ 1.036 × current` (for t½ 5 h). That is because elimination starts later: the curve is the current one shifted by `ln(ka/(ka−ke))/ke` = 15.3 min. The modeled peak for a dose is below the dose (84 mg for 95 mg), because elimination begins during absorption.

Sources: the Bateman / one-compartment form (Ramakrishnan 2016; 2B-Alert); F (Blanchard & Sawers 1983); `ka` (inference from Liguori 1997 and Blanchard & Sawers 1983, bracketed by the 2B-Alert capsule fit); `ke` from the person's setting.

## 5. Constant trace table

| Constant | Location | Current | Recommended | Source | Confidence |
|---|---|---|---|---|---|
| Decay kernel | `Algorithms.swift:14` | `0.5^(τ/t½)`, instant | `A(τ)` Bateman, ka 4 | §4 | Medium-High |
| `ka` | (none) | ∞ (implicit) | 4.0 h⁻¹, fixed, not user-editable | Liguori 1997; Blanchard & Sawers 1983; 2B-Alert | Medium |
| `F` | (none) | 1 (implicit) | 1.0 | Blanchard & Sawers 1983 | High |
| `defaultHalfLife` | `Models.swift:123` | 5 h | 5 h | Blanchard & Sawers 1983; Temple 2017 | Medium-High |
| Half-life stepper | `SettingsView.swift:56` | 0.5–16 h, step 0.5 | 1.5–24 h, step 0.5 (see §8) | Temple 2017; Culm-Merdek 2005 | Medium |
| `dailyLimitMg` default | `Models.swift:130` | 400 | Unset (nil) until the person chooses | `agents.md` rule; FDA figure must not be implied | High (rule) |
| `cutoffHour` default | `Models.swift:131` | 16 | Unset until chosen | Product rule | High (rule) |
| Cutoff reminder copy | `Onboarding+Copy.swift:133` | "likely to affect tonight's sleep" | "Your cutoff time, {time}." | Product rule | High |
| Espresso preset | `CaffeineLog.swift:14` | 60 mg | 63 mg, "1 shot" | USDA FDC 171891 | High |
| Drip preset | `CaffeineLog.swift:15` | 95 mg | 95 mg, "8 fl oz" | USDA FDC | High |
| Matcha preset | `CaffeineLog.swift:16` | 70 mg | 70 mg, "2 g" | Koláčková 2020 | Low |
| Energy preset | `CaffeineLog.swift:17` | 160 mg | 160 mg, "16 fl oz can" | Label; FDA range | Medium |
| Custom draft | `CaffeineLog.swift:60` | "80", "Drip" | "", "" | Product rule | High |
| Amount bounds | `CaffeineLog.swift:72` | 1–1999 mg | Keep | — | — |
| Cutoff solver | `CutoffScenario.swift:275-287` | Closed form on the instant model | Bisection on `N` (§6.2) | §4 | Medium-High |
| `modelVersion` | `CutoffScenario.swift:9` | cutoff-scenario-1 | cutoff-scenario-2 | — | — |
| Assumption copy | `CutoffScenario.swift:10` | "…half-life setting…" | "Modeled with your half-life setting and a typical absorption time. An assumption, not measured." | — | — |
| Inline decay | `EnergyEstimate.swift:155` | Duplicated formula | Call `CaffeineKinetics` | — | High |
| `itemizedMinimumMg` | `EnergyEstimate.swift:86` | 0.01 | Keep; test on `N` so a just-logged dose isn't "no caffeine" | §6.1 | Medium |
| Chart step | `Summary.swift:247` | 60 min | 15 min, plus each dose's `t + tmax` | A 60-minute grid misses the 52-minute peak | High |
| Chart visibility | `Summary.swift:185` | rounds to ≥ 1 mg | Keep | — | — |
| Timing window | `Sleep.swift:202` | 12 h | Keep (descriptive) | — | — |
| Sample doses | `SampleData.swift:14-31` | 40–120 mg | Keep | Realistic per §3.3 | — |
| Effect `1−e^(−mg/100)`, weight 40 | `Algorithms.swift:21`, `:101` | — | Alertness owner | — | — |

## 6. Implementation spec

### 6.1 Pure functions (AuroraCore, no I/O)

```swift
public struct CaffeinePK: Codable, Equatable, Sendable {
    public var halfLifeHours: Double            // the person's setting
    public var absorptionPerHour: Double = 4.0  // ka; constant, not in Settings
    public var bioavailability: Double = 1.0    // F
    public static let version = "caffeine-pk-2"
}

public enum CaffeineKinetics {
    /// Fraction of one dose absorbed and not yet eliminated, τ hours after intake (0 for τ < 0).
    public static func bodyFraction(hours τ: Double, pk: CaffeinePK) -> Double
    /// Fraction not yet cleared (still absorbing + in body). 1 at τ = 0, then strictly decreasing.
    public static func unclearedFraction(hours τ: Double, pk: CaffeinePK) -> Double
    /// Hours from intake to the modeled peak of `bodyFraction`.
    public static func peakDelayHours(pk: CaffeinePK) -> Double
    /// Σ mg in body at `t`; doses after `t` contribute 0.  ← interface for the alertness model
    public static func bodyMg(at t: Millis, doses: [Dose], pk: CaffeinePK) -> Double
    /// Σ mg not yet cleared at `t` (cutoff scenario, "has caffeine" evidence).
    public static func unclearedMg(at t: Millis, doses: [Dose], pk: CaffeinePK) -> Double
    /// Optional: mg/L given a caller-supplied distribution volume. Aurora never asks for weight.
    public static func plasmaMgPerL(at t: Millis, doses: [Dose], pk: CaffeinePK, volumeL: Double) -> Double
}
```

**Interface to the alertness owner:** `bodyMg(at:doses:pk:)` returns mg absorbed and not yet eliminated. That is the quantity a plasma concentration is proportional to (`C = A/V`). If their pharmacodynamic model brings its own kinetics (2B-Alert's `g_PD`), they should take doses directly rather than `bodyMg`, to avoid modeling the kinetics twice.

Rules:
- Time is in absolute instants (DST-safe, as now).
- An invalid half-life (≤ 0 or non-finite) returns `nil` at the call site, as `halfLifeProblem` does today.
- `Caffeine.activeMg` is kept as `legacyInstantMg` only for the React Native parity fixtures (`ParityTests.swift`).

### 6.2 Cutoff with an absorption phase

- **Problem:** with absorption, a drink taken just before bedtime has `A ≈ 0` at bedtime, while its caffeine peaks during sleep. Keeping "mg in body *at* bedtime" would make late drinks look harmless, and the latest-time problem would stop having a single answer.
- **Spec:** the scenario's bedtime value is `unclearedMg(at: bedtime)`, labelled "Modeled caffeine at bedtime, including any still being absorbed". Use the same value for existing records and for the hypothetical drink.

Since `N` strictly decreases:
1. Keep the existing early exits: `unreachable` (threshold 0 with caffeine), `thresholdReachedByRecords`, `needsAmount`.
2. `headroom = threshold − existingN`. If `amount ≤ headroom`, then τ = 0 and the result is bedtime itself.
3. Otherwise, bisect τ over `[0, 72 h]` for the smallest τ where `amount · unclearedFraction(τ) ≤ headroom`. Use 60 iterations, or stop at a 1-second tolerance, and take the upper end of the bracket.
4. Set `latest = floor_to_minute(bedtime − τ)`, so the condition still holds at the minute shown. Then apply `passed` / `feasible` as now.
5. `hypotheticalMg` and `combinedMg` also use `N`. The Today chart keeps `A` and adds a "rising" note while any dose is less than `tmax` old.

### 6.3 Preset values and labels

```
espresso  "Espresso"      serving "1 shot"         63 mg
drip      "Drip coffee"   serving "8 fl oz"        95 mg
matcha    "Matcha"        serving "2 g"            70 mg
energy    "Energy drink"  serving "16 fl oz can"  160 mg
(optional) blackTea "Black tea" "8 fl oz" 47 mg; cola "Cola" "12 fl oz" 34 mg
```

- Add a `serving: String` field to `CaffeinePreset`. Keep the `id` values so stored favorites survive.
- The stored `source` stays the label.
- The VoiceOver label is "Espresso, 1 shot, 63 milligrams".

### 6.4 Golden test cases

Case: 95 mg at 08:00 local, t½ 5 h (ke = 0.138629 h⁻¹), ka 4. Tolerance ±0.01 mg.

| Time | τ (h) | Current `0.5^(τ/5)` | New `A` (body) | New `N` (uncleared) |
|---|---|---|---|---|
| 08:00 | 0 | 95.00 | 0.00 | 95.00 |
| 08:15 | 0.25 | 91.76 | 58.86 | 93.80 |
| 08:30 | 0.5 | 88.64 | 78.50 | 91.36 |
| 08:52:14 (tmax 0.8707 h) | 0.8707 | 84.20 | **84.20 (peak)** | 87.12 |
| **09:00** | 1 | **82.70** | **83.87** | 85.61 |
| 10:00 | 2 | 72.00 | 74.55 | 74.58 |
| **13:00** | 5 | **47.50** | **49.21** | 49.21 |
| 16:00 | 8 | 31.34 | 32.46 | 32.46 |
| **23:00** | 15 | **11.88** | **12.30** | 12.30 |

Peak delay by half-life: t½ 2.5 h → 43.0 min; 4 h → 49.2; 5 h → 52.2; 6 h → 54.7; 8 h → 58.8; 10 h → 61.9.

Cutoff cases (bedtime 23:00, t½ 5 h, `now` early enough to be `feasible`):

| Existing | Threshold | Hypothetical | Current latest | New latest |
|---|---|---|---|---|
| 95 mg at 08:00 (current 11.875 / new 12.301 at 23:00) | 50 mg | 95 mg | 16:24 (τ 6.5860 h) | **16:04** (τ 6.9215 h) |
| none | 100 mg | 200 mg | 18:00 (τ 5.0000 h) | **17:44** (τ 5.2544 h) |
| none | 30 mg | 95 mg | 14:41 (τ 8.3148 h) | **14:25** (τ 8.5693 h) |
| none | 50 mg | 40 mg | 23:00 | 23:00 |
| 95 mg at 08:00 | 0 mg | — | unreachable | unreachable |

Property tests:
- `N` is non-increasing.
- `A ≤ N`.
- `A(τ) → 0` as τ → ∞.
- `∫ke·A dτ = D`, so the dose's mass is conserved.
- Doses superpose.
- A DST change between drink and bedtime counts real elapsed hours.

## 7. Migration and labelling

- **Records are unchanged.** Logged mg stays as entered; only new quick-adds use the new preset values.
- **Settings:** stored `halfLife` is kept. Values outside a new stepper range are shown as stored, never silently clamped. `dailyLimitMg` and `cutoffHour` become optional. Existing stored values are kept, because there's no way to tell a default from a value the person chose; see §8.
- **Snapshots:** cards captured under `cutoff-scenario-1` / `alertness-1` stay frozen with their version. Refresh re-evaluates under the new versions and shows "Model updated" once.
- **Labels:** keep "Modeled". Add "Includes a typical absorption time (peak about 50 min after a drink)" to the half-life note. While a recent dose is still rising, the chart point reads "rising".
- **One-time What's New note:** "Modeled caffeine now rises over about an hour after a drink instead of counting all at once. Your records and settings are unchanged."
- **Tests:** keep the React Native parity fixtures on `legacyInstantMg`; add §6.4 as new golden tests.

## 8. Open questions for the product owner

1. Accept `ka = 4 h⁻¹` as a single fixed constant, or use per-drink rates (for example a slower one for capsules and pre-workout)?
2. Is "not yet cleared" acceptable wording for the cutoff value? The alternative is "highest modeled amount from bedtime on", which is closer to the biology but harder to compute and explain.
3. Should the half-life range become 1.5–24 h? Stored values below 1.5 would stay but couldn't be re-entered.
4. Should the 400 mg and 16:00 defaults become "unset" for *new* users only, or should existing values equal to the default also be treated as unset? A one-time prompt could confirm them.
5. Build the "About the evidence" sheet (§3.4 B, §3.5 B), or show no evidence at all?
6. Add Black tea and Cola presets, or keep four?
7. Should brand-specific values (cold brew, energy drinks) be verified against current labels before shipping? Here they are Medium/Low confidence.

## 9. Sources

- Blanchard J, Sawers SJ. The absolute bioavailability of caffeine in man. Eur J Clin Pharmacol 1983;24:93–98. doi:10.1007/BF00613933
- Blanchard J, Sawers SJ. Comparative pharmacokinetics of caffeine in young and elderly men. J Pharmacokinet Biopharm 1983;11:109–126. doi:10.1007/BF01061844
- Liguori A, Hughes JR, Grass JA. Absorption and subjective effects of caffeine from coffee, cola and capsules. Pharmacol Biochem Behav 1997;58:721–726. doi:10.1016/S0091-3057(97)00003-8
- Ramakrishnan S, et al. Dose-dependent model of caffeine effects on human vigilance during total sleep deprivation. J Theor Biol 2014;358:11–24. doi:10.1016/j.jtbi.2014.05.017
- Ramakrishnan S, et al. A unified model of performance for predicting the effects of sleep and caffeine. Sleep 2016;39(10):1827–1841. doi:10.5665/sleep.6164
- Reifman J, et al. 2B-Alert Web. Sleep 2016;39(12):2157–2159. doi:10.5665/sleep.6318; and 2B-Alert Web 2.0. J Med Internet Res 2022;24(1):e29595. doi:10.2196/29595
- Vital-Lopez FG, et al. Caffeine dosing strategies to optimize alertness during sleep loss. J Sleep Res 2018;27(5):e12711. doi:10.1111/jsr.12711
- US Patent 11,241,194 B2 (caffeine parameter table). https://patents.google.com/patent/US11241194B2/en
- Grzegorzewski J, et al. Pharmacokinetics of caffeine: a systematic analysis of reported data. Front Pharmacol 2021;12:752826. doi:10.3389/fphar.2021.752826
- Nehlig A. Interindividual differences in caffeine metabolism and factors driving caffeine consumption. Pharmacol Rev 2018;70:384–411. doi:10.1124/pr.117.014407
- Temple JL, et al. The safety of ingested caffeine: a comprehensive review. Front Psychiatry 2017;8:80. doi:10.3389/fpsyt.2017.00080
- Culm-Merdek KE, et al. Fluvoxamine impairs single-dose caffeine clearance. Br J Clin Pharmacol 2005;60:486–493. doi:10.1111/j.1365-2125.2005.02467.x
- Jeppesen U, et al. A fluvoxamine–caffeine interaction study. Pharmacogenetics 1996;6:213–222.
- Desmond PV, et al. Impaired elimination of caffeine in cirrhosis. Dig Dis Sci 1980;25:193–197. doi:10.1007/BF01308138
- Drake C, et al. Caffeine effects on sleep taken 0, 3, or 6 hours before going to bed. J Clin Sleep Med 2013;9(11):1195–1200. doi:10.5664/jcsm.3170
- Gardiner C, et al. The effect of caffeine on subsequent sleep: a systematic review and meta-analysis. Sleep Med Rev 2023;69:101764. doi:10.1016/j.smrv.2023.101764
- Landolt HP, et al. Caffeine intake (200 mg) in the morning affects human sleep and EEG power spectra at night. Brain Res 1995;675:67–74. doi:10.1016/0006-8993(95)00040-W
- Weibel J, et al. The impact of daily caffeine intake on nighttime sleep in young adult men. Sci Rep 2021;11:4668. doi:10.1038/s41598-021-84088-x
- Clark I, Landolt HP. Coffee, caffeine, and sleep: a systematic review. Sleep Med Rev 2017;31:70–78. doi:10.1016/j.smrv.2016.01.006
- Reichert CF, Deboer T, Landolt HP. Adenosine, caffeine, and sleep–wake regulation. J Sleep Res 2022;31:e13597. doi:10.1111/jsr.13597
- EFSA NDA Panel. Scientific opinion on the safety of caffeine. EFSA J 2015;13(5):4102. doi:10.2903/j.efsa.2015.4102; summary https://www.efsa.europa.eu/en/topics/topic/caffeine
- FDA. Spilling the beans: how much caffeine is too much? https://www.fda.gov/consumers/consumer-updates/spilling-beans-how-much-caffeine-too-much
- Health Canada. Caffeine in foods. https://www.canada.ca/en/health-canada/services/food-nutrition/food-safety/food-additives/caffeine-foods/foods.html
- ACOG Committee Opinion No. 462: Moderate caffeine consumption during pregnancy. Obstet Gynecol 2010;116:467–468. PMID 20664420
- USDA FoodData Central, SR Legacy (espresso FDC 171891; brewed coffee). https://fdc.nal.usda.gov/
- McCusker RR, Goldberger BA, Cone EJ. Caffeine content of specialty coffees. J Anal Toxicol 2003;27:520–522. doi:10.1093/jat/27.7.520
- Ludwig IA, et al. Variations in caffeine and chlorogenic acid contents of coffees. Food Funct 2014;5:1718–1726. doi:10.1039/C4FO00290C
- Koláčková T, et al. Matcha tea: analysis of nutritional composition, phenolics and antioxidant activity. Plant Foods Hum Nutr 2020;75:48–53. doi:10.1007/s11130-019-00777-z
- AAP adolescent guidance (secondary): Boston Children's Hospital tip sheet. https://dme.childrenshospital.org/wp-content/uploads/2023/02/Caffeine-Use-in-Adolescents-PDF.pdf
