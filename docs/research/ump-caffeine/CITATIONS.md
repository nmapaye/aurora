# UMP + caffeine research model: citations

Code: `AuroraCore/Sources/AuroraCore/Research/UMPCaffeineModel.swift`, compiled only in Debug builds (`AURORA_RESEARCH_CAFFEINE`, defined for Debug in `AuroraCore/Package.swift`). Research only: never in Release/TestFlight; the only UI is the Debug-only Research screen.

Implemented from the published papers below and nothing else. No code from the authors' tools was seen or used. All sources were retrieved on 2026-11-10 from the authors' institute page (bhsai.org/pubs); page numbers are the journal's.

## Sources

| Key | Reference | URL |
|---|---|---|
| 2016b | Ramakrishnan S, Wesensten NJ, Kamimori GH, Moon JE, Balkin TJ, Reifman J. A unified model of performance for predicting the effects of sleep and caffeine. Sleep 2016;39(10):1827–1841. doi:10.5665/sleep.6164 | https://bhsai.org/pubs/Ramakrishnan_2016_A_Unified_Model_Of_Performance2.pdf |
| 2016a | Ramakrishnan S, Wesensten NJ, Balkin TJ, Reifman J. A unified model of performance: validation of its predictions across different sleep/wake schedules. Sleep 2016;39(1):249–262. doi:10.5665/sleep.5358 | https://bhsai.org/pubs/Ramakrishnan_2016_A_Unified_Model_of_Performance.pdf |
| 2014 | Ramakrishnan S, Laxminarayan S, Wesensten NJ, Kamimori GH, Balkin TJ, Reifman J. Dose-dependent model of caffeine effects on human vigilance during total sleep deprivation. J Theor Biol 2014;358:11–24. doi:10.1016/j.jtbi.2014.05.017 | https://bhsai.org/pubs/Ramakrishnan_2014_Dose_Dependent_Model_of_Caffeine.pdf |
| 2013 | Rajdev P, Thorsley D, Rajaraman S, Rupp TL, Wesensten NJ, Balkin TJ, Reifman J. A unified mathematical model to quantify performance impairment for both chronic sleep restriction and total sleep deprivation. J Theor Biol 2013;331:66–77. doi:10.1016/j.jtbi.2013.04.013 | https://bhsai.org/pubs/Rajdev_2013_A_Unified_Mathematical_Model.pdf |
| 2023 | Priezjev NV, Vital-Lopez FG, Reifman J. Assessment of the unified model of performance: accuracy of group-average and individualised alertness predictions. J Sleep Res 2023;32:e13626. doi:10.1111/jsr.13626 | https://bhsai.org/pubs/Priezjev_2023_Assessment_of_the_unified_model.pdf |

Also consulted, no constants taken: Reifman et al. 2022 (J Med Internet Res 24:e29595, https://www.jmir.org/2022/1/e29595; read, no equations) and Vital-Lopez et al. 2018 (J Sleep Res 27:e12711; read, its equations are in Supporting Information, which was not available). Reifman et al. 2016 (Sleep 39:2157–2159) was downloaded but not used.

## Equations

| Code | Equation | Source |
|---|---|---|
| `simulate` → `impairment` | P = P0 × gPD for t ≥ t0 | 2016b Eq 1, p. 1829 |
| `caffeineFree` | P0 = S + κC | 2016b Table 2 Eq 2, p. 1830; 2016a Table 2 Eq 1, p. 252 |
| `circadian` | C(t) = Σ₁⁵ aᵢ sin(i·2π(t + φ)/τ) | 2016b Table 2 Eq 3; 2016a Table 2 Eq 2; 2013 Eq 2, p. 68 |
| `advance` (wake) | S = U − (U − S0)e^(−t/τw) | 2016b Table 2 Eq 4 |
| `advance` (sleep) | S = −2U + (2U + S0)e^(−t/τs) + (2U + L0)[τLA/(τLA − τs)](e^(−t/τLA) − e^(−t/τs)) while L is above the floor | 2016b Table 2 Eq 4; 2013 Eq 6b, p. 69 |
| `advance` (sleep, at floor) | dS/dt = (L − S)/τs with L held at the floor | 2016a Table 2 Eq 3, p. 252; 2023 Table 2 Eq 4, p. 4. See FLAGGED F4 |
| `advance` (L) | L = max[U − (U − L0)e^(−t/τLA), −0.11U] awake; max[−2U + (2U + L0)e^(−t/τLA), −0.11U] asleep | 2016b Table 2 Eq 5; 2023 Table 2 Eq 5 |
| L and Debt | L = U × Debt; dDebt/dt = (Loss − Debt)/τLA; Loss = +1 awake, −2 asleep | 2016a Table 2 Eqs 4–5b; 2013 Eqs 5a–5b, p. 68 |
| `caffeineFactor` | gPD = [1 + Mc·ka/(ka − kc)·(e^(−kc(t−t0)) − e^(−ka(t−t0)))]⁻¹, t ≥ t0 | 2016b Table 2 Eq 6a |
| `caffeineFactor` | Mc = M0·c, kc = k0·e^(−z·c), c in grams | 2016b Table 2 Eq 6b; 2014 Eqs 4–5, p. 13 |
| `caffeineFactor` before the dose | gPD = 1 for t < t1 | 2014 Eq 6, p. 13 |
| range | 0 ≤ gPD ≤ 1 | 2016b p. 1829 |

## Constants

All from 2016b Table 3 (p. 1832) unless stated. Standard errors in brackets as printed.

| Constant | Lapse set | Mean RT set | Source |
|---|---|---|---|
| U | 18.4 (0.7) lapses | 497 (31) ms | Table 3 |
| τw | 40.0 (3.2) h | 23.0 (3.2) h | Table 3 |
| τs | 2.1 (0.1) h | 4.0 (1.0) h | Table 3 |
| S0 | 0.5 (0.7) lapses | 176 (15) ms | Table 3 |
| κ | 3.3 (0.3) lapses | 75 (7) ms | Table 3 |
| φ | 2.3 (0.3) h | 2.5 (0.2) h | Table 3. Clock origin of t: FLAGGED F1 |
| τLA | 7.0 (1.7) d → 168 h | 7.0 (2.6) d → 168 h | Table 3 (d × 24 is a unit conversion) |
| L0 | 0.0 (0.0) lapses | 140 (14) ms | Table 3 |
| M0 | 9.86 (1.80) g⁻¹ | 3.59 (0.66) g⁻¹ | Table 3 |
| k0 | 0.49 (0.17) h⁻¹ | 0.49 (0.17) h⁻¹ | Table 3 |
| z | 1.63 (1.61) g⁻¹ | 1.63 (1.61) g⁻¹ | Table 3 |
| ka capsule | 2.06 (0.36) h⁻¹ | same | Table 3 (from Kamimori et al. 2002, its ref 21); fixed per p. 1831 |
| ka gum | 3.21 (0.78) h⁻¹ | same | Table 3; fixed per p. 1831 |
| a1…a5 | 0.97, 0.22, 0.07, 0.03, 0.001 | same | 2016b Table 2; 2016a Table 2; 2013 p. 68 |
| τ (circadian period) | 24 h | same | 2016b Table 2 says "~24 h"; 2014 p. 13 fixes τ = 24 h |
| Debt floor | −0.11 (L ≥ −0.11U) | same | 2016a p. 251 (8.9 h sleep/day limit); 2016b Table 2 Eq 5 |
| Loss | +1 awake, −2 asleep | same | 2016a Table 2 Eq 5b; 2013 Eq 5a |

Rajdev 2013 Table 1 τLA = 4.06 d is used only in a test that checks the 2013 text's 63.2 % / 95 % statements.

## Not part of this model

- δ, the per-study offset added to fit each study's first day (2016a p. 252; 2016b p. 1831). It is a fitting device, not a model constant.
- μ = 2.99, b = 2.89 lapses (5-min to 10-min PVT affine map, 2016b p. 1831). Study normalisation only.
- The 2023 individualisation (Bayesian updates, τw = 18.2 h and τs = 4.2 h fixed there, Table S1 not read).
- Prediction intervals (2016b Eq 7): σp and σm are not published as numbers in the sources read.
