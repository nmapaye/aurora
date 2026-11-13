# KSSModel citations (research / unvalidated)

`KSSModel.swift` is the **original full Three-Process Model** (TPM) of
alertness regulation with its published KSS transfer. It is compiled into
Debug builds only (`AURORA_RESEARCH_KSS`, see `Package.swift`), is not
referenced by the app, and is never shown to people. It is a Swift port of
`website/research/tpm-kss.ts` (see `website/research/README.md`).

## Parameter trace

Every value below is printed in Ingre et al. 2014, section "The model
equations" (eqs 1.1–1.9), which states the parameters "were estimated
earlier [Åkerstedt & Folkard 1990] and have been published before
[Åkerstedt et al. 2007; Åkerstedt, Folkard & Portin 2004]". Transcription
was checked against the published PDF on 2026-11-10.

| Symbol | Swift name | Value | Equation | Source |
|---|---|---|---|---|
| ha | `upperAsymptote` | 14.3 | 1.1–1.4 | Ingre 2014 [1] |
| la | `lowerAsymptote` | 2.4 | 1.1 | Ingre 2014 [1] |
| d | `wakeDecayRate` | −0.0353 h⁻¹ | 1.1 S = la + (sw − la)·e^(d·taw) | Ingre 2014 [1] |
| g | `sleepRecoveryRate` | ln((14.3 − 14.0)/(14.3 − 7.96))/8 ≈ −0.3813 h⁻¹ | 1.2 S′ = ha − (ha − ss)·e^(g·tas) | Ingre 2014 [1]; original recovery Åkerstedt & Folkard 1990 [2] |
| bl | `brakeLevel` | 12.2 | 1.3 S′₁ = ss + tas·g·(bl − ha); 1.4 S′₂ = ha − (ha − bl)·e^(g·(tas − bt)); 1.5 bt = (bl − ss)/(g·(bl − ha)) | Ingre 2014 [1]; brake introduced in Åkerstedt et al. 2008 [5] |
| Wc | `inertiaAmplitude` | −5.72 | 1.6 W = Wc·e^(Wd·taw) | Ingre 2014 [1] |
| Wd | `inertiaRecoveryRate` | −1.51 h⁻¹ | 1.6 | Ingre 2014 [1] |
| Cm, Ca | `circadianMesor`, `circadianAmplitude` | 0, 2.5 | 1.7 C = Cm + Ca·cos(2π/24·(tod − p)) | Ingre 2014 [1] |
| Um, Ua | `ultradianMesor`, `ultradianAmplitude` | −0.5, 0.5 | 1.8 U = Um + Ua·cos(2π/12·(tod − p − 3)) | Ingre 2014 [1] |
| p | `defaultPhaseHours` | 16.8 h | 1.7–1.8 | Ingre 2014 [1] |
| a, b | `kssIntercept`, `kssSlope` | 10.6, −0.6 | 1.9 KSS = a + b·(S + C + U + W) | Ingre 2014 [1] |
| — | `sleepEntryThreshold` | S + C + U = 8.38 | sleep generator | Ingre 2014 [1]; used only to initialise S at the first recorded sleep |

Implementation choices that are **not** from the papers (inherited from
`tpm-kss.ts`, documented as assumptions):

- S is initialised at the first recorded sleep onset from the sleep-entry
  threshold (no individual prior sleep debt).
- Queries more than 16 h after the last sleep end are refused (the
  reviewed study's selection window in `tpm-kss.ts`, not a model limit).
- At least two recorded sleep episodes are required; unknown or
  unconfirmed intervals are refused, never imputed as wake.
- No jet-lag acclimatisation (Ingre 2014 eq 1.10) and no chronotype phase
  adjustment (Ingre 2014 models 6c/6d) are applied.
- **Caffeine is excluded.** No published, validated caffeine term for the
  TPM's KSS output was found. Any positive dose, or an unknown caffeine
  history, is refused with `caffeine-effect-not-validated` /
  `unknown-caffeine-history`. No coefficient was invented.

## References

1. Ingre M, Van Leeuwen W, Klemets T, Ullvetter C, Hough S, Kecklund G,
   Karlsson D, Åkerstedt T (2014). Validating and Extending the Three
   Process Model of Alertness in Airline Operations. *PLoS ONE* 9(10):
   e108679. DOI [10.1371/journal.pone.0108679](https://doi.org/10.1371/journal.pone.0108679). CC BY 4.0.
2. Åkerstedt T, Folkard S (1990). A model of human sleepiness. In: Horne J
   (ed.), *Sleep '90*. Bochum: Pontenagel Press, pp. 310–313. No DOI.
3. Åkerstedt T, Folkard S (1995). Validation of the S and C components of
   the three-process model of alertness regulation. *Sleep* 18(1):1–6.
   DOI [10.1093/sleep/18.1.1](https://doi.org/10.1093/sleep/18.1.1).
4. Åkerstedt T, Folkard S (1997). The three-process model of alertness and
   its extension to performance, sleep latency, and sleep length.
   *Chronobiol Int* 14(2):115–123. DOI [10.3109/07420529709001149](https://doi.org/10.3109/07420529709001149).
5. Åkerstedt T, Ingre M, Kecklund G, Folkard S, Axelsson J (2008).
   Accounting for partial sleep deprivation and cumulative sleepiness in
   the Three-Process Model of alertness regulation. *Chronobiol Int*
   25(2):309–319. DOI [10.1080/07420520802110613](https://doi.org/10.1080/07420520802110613).
6. Åkerstedt T, Folkard S, Portin C (2004). Predictions from the
   three-process model of alertness. *Aviat Space Environ Med* 75(3
   Suppl):A75–A83. No DOI; PMID 15018268.
7. Åkerstedt T, Axelsson J, Kecklund G (2007). Individual validation of
   model predictions of sleepiness and sleep hours. *Somnologie* 11:169–174.
   DOI [10.1007/s11818-007-0315-7](https://doi.org/10.1007/s11818-007-0315-7).
8. Åkerstedt T, Gillberg M (1990). Subjective and objective sleepiness in
   the active individual. *Int J Neurosci* 52(1–2):29–37 (the KSS).
   DOI [10.3109/00207459008994241](https://doi.org/10.3109/00207459008994241).

DOIs were resolved against Crossref on 2026-11-10.

## Verification

- `KSSModelTests.matchesTypeScriptReferenceForEveryCase`: 41 identical
  inputs (28 predictions, 13 refusals) through `tpm-kss.ts`
  (sha256 `24bc58e3…6bfb25`) and Swift; agreement ≤ 1e-9.
  Regenerate: `node AuroraCore/Tools/kss-tpm-reference/generate.mjs`.
- `matchesIndependentRK4Integration`: the 16 Python RK4 cases from
  `website/research/make-reference-fixtures.py`; agreement ≤ 3e-7.
- These are synthetic mathematical cases, not human KSS observations.
  Agreement shows the equations are reproduced, not that predictions are
  valid for any individual.
