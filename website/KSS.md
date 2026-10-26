# Website KSS and copy cleanup

## Decision: self-reported KSS, not a calculated estimate

The current native model (`AuroraCore/Sources/AuroraCore/Algorithms.swift`,
`Alertness.score`) is `clamp(30 + 50C + 40E − 40S − 100I, 0, 100)`.
`EnergyEstimate.currentModelVersion` remains `alertness-1`. The coefficients have
no KSS calibration, and the previous website values (68 and 74) were hard-coded.
The preview provides a sleep duration and a caffeine amount, not a complete,
timed sleep/wake history. None of these supports a defensible automatic KSS.

The repository's `docs/research/energy-model.md` is explicitly a proposal, not
implemented validation. Its proposed UMP predicts vigilance-task performance,
not KSS. The TPM and other KSS-specific models have their own equations,
parameters, history requirements and validation; their existence does not
validate an affine conversion of Aurora's unrelated score. No conversion,
calculated KSS, or accuracy claim is implemented here.

The requested fallback is implemented: **Self-reported KSS**, version B,
integer 1–9, with one interpretation for every point. The person chooses how
sleepy they felt over the preceding five minutes. Higher means sleepier. No
rating is selected by default; missing or invalid input stays “Not rated”.

## Behavior and implementation

- `src/kss.ts` is the single anchor table and input boundary. `kssRating` accepts
  only integer numeric values 1–9; it never rounds, clamps, or coerces scores.
  `parseKssSelection` accepts only the native select's exact strings 1–9.
- `src/App.tsx` owns one optional rating. Both EnergyCards use that value and
  the same interpretation. Only the interactive card announces changes.
- Sleep and caffeine switches never calculate or alter the rating. Missing sleep
  does not prevent a self-report. Clear preview resets the rating and both switches.
- The illustration's sample sleep/caffeine remain distinct from the actual
  optional self-report. Component state only: no persistence, telemetry, Health
  connection or model invocation. Reload clears the rating.
- Removed repeated source sentences, the arbitrary /100 metric, and the unused
  `demoData.ts` for the retired simulator. Consolidated sample/privacy disclosure
  beneath the illustration; details retain scientific limits and the lack of a
  Health connection. Release availability and the full privacy policy remain.
- This is website-only. It does not change native check-ins, algorithms, exports,
  Health permissions, other worktrees, or CI. No deployment is authorized.

## Scientific scope

A self-rating is not an objective measurement of alertness or performance, a
clinical diagnosis, or a safety/fitness determination. The underlying research
supports use of the scale; this implementation has no independent clinical
validation. No estimate is inferred for a person who has not entered a rating.
All nine labels use the wording in the 2016 paper, with sentence capitalization.
No native paid-app instrument-licensing decision is made by this website change.

## Sources

- Åkerstedt Miley A, Kecklund G, Åkerstedt T (2016),
  [Comparing two versions of the Karolinska Sleepiness Scale](https://doi.org/10.1007/s41105-016-0048-8).
  Version B labels and the preceding-five-minute frame. The article is published
  under [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); credit is also
  available in the website's expandable KSS explanation. Capitalization adapted.
- Ramakrishnan S et al. (2016),
  [A Unified Model of Performance for Predicting the Effects of Sleep and Caffeine](https://pubmed.ncbi.nlm.nih.gov/27397562/).
  Its outcomes are group-average PVT performance, not a KSS conversion.
- Repository evidence: `Algorithms.swift`, `EnergyEstimate.swift`,
  `docs/research/energy-model.md` (especially current model, model comparison,
  and Q2), and `docs/research/sleep-and-check-in.md` (R5).

## Validation

Run `npm --prefix website test`, `npm run site:type-check`, and
`npm run site:build`. Tests use Node's built-in runner and Vite's React transform,
with server-rendered assertions against the actual components; no new test
library or runtime dependency was added.

The automated suite covers every anchor, invalid/missing/non-finite/out-of-range
inputs, malformed select values, all 40 record/rating combinations, no default
rating, shared display wording, semantic controls, single live announcement,
existing navigation, and removal of obsolete alertness/source labels.
Browser interaction and responsive evidence are recorded in `review/kss/`.

## Follow-up request: a sleep/caffeine-responsive prediction

The requested automatic behavior is not implemented by modifying a person's
KSS answer. It requires a separately defined prediction outcome. The user selected research and validation of a KSS-specific predictor with richer
timing inputs. The resulting [research checkpoint](research/README.md) reproduces
a published sleep-only baseline but does not validate a caffeine effect. This
branch retains the tested self-report implementation; automatic KSS is not enabled.

A follow-up literature check found Puckeridge et al. (2011),
[Incorporation of caffeine into a quantitative model of fatigue and sleep](https://pubmed.ncbi.nlm.nih.gov/21176782/).
The authors' review, Robinson et al. (2011),
[Quantitative modelling of sleep dynamics](https://doi.org/10.1098/rsta.2011.0120),
section 2(e), identifies the comparison outcome as the Stanford Sleepiness Scale,
with a 600 mg dose after prolonged total sleep deprivation. This does not provide
a validated KSS conversion for this preview's 95 mg coffee and one sleep duration.
A KSS-specific implementation needs appropriate equations, timed sleep/wake and
dose history, parameters, independent numerical fixtures, and scope/limitations
matched to the original validation data. No effect coefficients have been invented.

Research verification: 38 software tests now pass, including 16 independent
numerical cases. See research/validation-results.json. This is equation
verification, not empirical prediction validation or clinical validation.
