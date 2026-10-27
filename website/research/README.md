# KSS prediction research checkpoint

**Outcome:** a combined sleep-and-caffeine KSS predictor is **not validated**.
Automatic KSS is not enabled on the marketing website. The copy cleanup and
self-rating remain in commit `9e4f84e4` on `nmapaye-bot/aurora-website-kss`.
This directory is a research artifact; it is not a production feature.

## Model review

| Candidate | Evidence checked | Decision for this task |
| --- | --- | --- |
| Original full TPM, Ingre et al. 2014 | Explicit homeostatic, circadian, ultradian and inertia equations and a KSS transformation; field study assesses model variants | Equations reproduced for verification. No timed caffeine effect; not sufficient for the requested combined predictor. |
| Postnova et al. 2018 arousal dynamics | KSS calibration to dim-light constant-routine/forced-desynchrony protocols | KSS-specific, but reviewed work does not validate a caffeine-to-KSS adjustment; environmental and protocol constraints also matter. |
| Puckeridge et al. 2011 caffeine extension | Authors' 2011 review identifies the comparison outcome as Stanford Sleepiness Scale following a 600 mg challenge during prolonged deprivation | Does not establish a KSS effect for the preview's 95 mg coffee. Combining it with another KSS model would require new validation. |
| Aurora `alertness-1` / proposed UMP | Existing Swift formula and the research proposal, compared with UMP's published outcome | Existing formula has no KSS calibration; UMP's caffeine validation concerns PVT performance. Neither supplies a KSS conversion. |

This is a bounded review of the named candidates, not a claim that no suitable
model or dataset exists anywhere. No participant-level dataset jointly covering
timed sleep, timed caffeine and KSS was acquired or fitted in this work.

## Implemented research prototype

`tpm-kss.ts` reproduces the **original full model**, not the article's improved
fitted model variants. Parameter and equation transcription was checked against
pages 6–7 of the published PDF. Wake decay, piecewise sleep recovery with the
brake, circadian/ultradian phases (including the three-hour offset), sleep inertia,
and the published transfer equation are represented directly.

The original transfer is `10.6 − 0.6 × (S + C + U + W)`. It is applied to the
published TPM's own internal states; it never converts Aurora's 0–100 score.
The returned raw and bounded values are research outputs, not ratings made by
people. They must not be presented as validated individual predictions.

Required rich inputs:

- Query instant as epoch milliseconds and an explicit valid time zone.
- An explicit circadian phase, in hours; the paper's original default is 16.8.
- Contiguous, non-overlapping, timestamped sleep **and confirmed wake** segments.
  Unknown intervals are rejected. Absence of a sleep log does not become wake.
- At least two complete sleep episodes; query at wake or within 16 elapsed hours
  of the latest sleep end, matching the reviewed study's selection window.
- Explicit caffeine-history completeness and timestamped dose amounts. Unknown
  caffeine history is rejected. Any positive recorded dose returns
  `caffeine-effect-not-validated` with **no predicted KSS**.

The initialization uses the paper's assumed sleep-entry threshold. This does not
recover an individual's prior sleep debt. Time-zone conversion uses the query
instant, while elapsed durations use timestamps; DST tests verify that repeated
wall-clock times retain distinct elapsed wake durations. Biological adjustment
to travel/DST and individualized phase estimation are not validated here.
No sleep generator, dose suggestion, schedule recommendation or inferred missing
record is implemented.

## What passed

- 38 software tests, including 16 independently generated numerical references.
- Closed-form TypeScript propagation agrees with an independent Python RK4
  implementation of the differential dynamics within `3e-7` model units.
- The published recovery calibration, asymptotes, brake continuity and clock
  phases; missing/invalid history, gaps/overlaps, future records and DST cases.
- A 95 mg coffee returns an unsupported result rather than an invented effect.
- Tests keep this research implementation out of marketing entry points.
- Website type check and production build pass. Existing copy/KSS UI browser
  checks and desktop/mobile screenshots are under `../review/kss/`.

Exact differences and scope flags are in `validation-results.json`.
The reference fixtures are **synthetic mathematical cases**, not experimental
observations. Numerical agreement, unit tests and published study results do not
constitute new clinical or predictive validation of this implementation.

Reproduce:

```sh
python3 website/research/make-reference-fixtures.py
npm --prefix website test
npm run site:type-check
npm run site:build
```

## Gate for the requested automatic metric

Before enabling sleep-and-coffee-adjusted **Estimated KSS**, obtain a reproducible
KSS-specific caffeine model with its parameters and applicability, or a suitable
paired dataset and a justified model specification. For a new fit, split by
participant/study before calibration; use independently held-out observations;
compare with no-caffeine, sleep-only and simple baseline predictors; report
coverage, bias, MAE/RMSE and uncertainty within dose/timing/sleep strata. Define
missing-input and extrapolation behavior before fitting. Avoid reusing the same
observations as both calibration and validation.

If those gates pass, add a richer historical-input editor, display the model's
version and applicability, and retain the self-rating separately. Until then,
the requested responsive KSS feature remains incomplete. No hybrid coefficient,
hand-picked caffeine subtraction or SSS-to-KSS remapping is shipped.

## Primary sources

- Ingre M et al. (2014), [Validating and Extending the Three Process Model of
  Alertness in Airline Operations](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0108679),
  especially equations 1.1–1.9 and Table 2. [PDF](https://journals.plos.org/plosone/article/file?id=10.1371/journal.pone.0108679&type=printable).
  Open access, Creative Commons Attribution; equations independently implemented.
- Postnova S, Lockley SW, Robinson PA (2018), [Prediction of Cognitive Performance
  and Subjective Sleepiness Using a Model of Arousal Dynamics](https://journals.sagepub.com/doi/pdf/10.1177/0748730418758454).
- Puckeridge M et al. (2011), [Incorporation of caffeine into a quantitative model
  of fatigue and sleep](https://pubmed.ncbi.nlm.nih.gov/21176782/), and the authors'
  [Quantitative modelling of sleep dynamics](https://doi.org/10.1098/rsta.2011.0120),
  section 2(e). The reviewed author-uploaded text identifies the SSS outcome.
- Ramakrishnan S et al. (2016), [A Unified Model of Performance for Predicting the
  Effects of Sleep and Caffeine](https://pubmed.ncbi.nlm.nih.gov/27397562/).
