# Correspondence brief: Three-Process Model KSS in Aurora

For Nathan to adapt and send to Prof. Torbjörn Åkerstedt. Draft only; not sent.

## What Aurora is

Aurora is an iPhone/iPad app that logs caffeine and sleep (manually or from
Apple Health) and runs everything on the device. It makes no medical claims.
The app's daily check-in is moving from an in-house 1–5 energy rating to the
**self-rated KSS (1–9, every step labelled)**. Old 1–5 ratings stay as they
are and are never converted.

## What is implemented (research only)

A Swift implementation of the **original full Three-Process Model** with its
KSS transfer, `KSS = 10.6 − 0.6·(S + C + U + W)`, as written in Ingre et al.
(2014, eqs 1.1–1.9). It is compiled into developer builds only, is not used by
any screen, and is labelled research/unvalidated. Its job right now is to
support this conversation, not to show anything to users.

- Inputs: timestamped, contiguous sleep and confirmed-wake segments, a time
  zone, and a circadian phase (default 16.8 h). Unknown periods are refused,
  not filled in. At least two sleep episodes; queries up to 16 h after waking.
- Process S: wake decay (eq 1.1) and sleep recovery with the brake at 12.2
  (eqs 1.3–1.5). S is started from the sleep-entry threshold S+C+U = 8.38 at
  the first recorded sleep onset.
- Processes C and U (eqs 1.7–1.8), sleep inertia W (eq 1.6).
- Fragmented sleep is run fragment by fragment, so each awakening applies
  the wake equation and restarts the inertia clock.
- Caffeine is **not** in the formula. Any recorded dose returns "not
  supported" instead of a number.
- Verified against our earlier TypeScript version (41 identical inputs, match
  to 1e-9) and an independent numerical integration of the differential
  equations (16 cases, match to 3e-7). These are synthetic checks of the
  maths, not validation against people.

## Parameter sources

| Parameter | Value | Source |
|---|---|---|
| Upper/lower asymptote of S | 14.3 / 2.4 | Ingre et al. 2014, DOI 10.1371/journal.pone.0108679 |
| Wake decay d | −0.0353 h⁻¹ | same |
| Sleep recovery g | ln((14.3 − 14.0)/(14.3 − 7.96))/8 ≈ −0.3813 h⁻¹ | same; Åkerstedt & Folkard 1990 |
| Brake level | 12.2 | same; Åkerstedt et al. 2008, DOI 10.1080/07420520802110613 |
| Sleep inertia Wc, Wd | −5.72, −1.51 h⁻¹ | Ingre et al. 2014 |
| C amplitude/mesor, phase | 2.5 / 0, 16.8 h | same |
| U amplitude/mesor, offset | 0.5 / −0.5, p + 3 h | same |
| KSS transfer a, b | 10.6, −0.6 | same |
| Sleep-entry threshold | 8.38 | same (sleep generator) |

Full trace with all DOIs: `AuroraCore/Sources/AuroraCore/Research/CITATIONS.md`.

## How it relates to the self-reported KSS plan

- The person's own KSS rating is the measurement. The model value would only
  ever be a separate, clearly labelled estimate. The two are never merged,
  and the model never overrides or "corrects" a rating.
- Any comparison would be within the same person only (their ratings against
  the model over time). No population cut-offs, no "you are sleepier than
  you feel", nothing about driving or safety.
- Before anything is shown, we would want to check the model against each
  tester's own KSS ratings during a private beta, if you think that is a
  sensible test.

## Questions for Prof. Åkerstedt

1. **Version and parameters.** Is the original full model (S+C+U+W with the
   brake) still the version you would recommend for everyday KSS
   prediction? Ingre et al. 2014 found that S+C alone, with the phase set by
   chronotype, fitted better in aircrew. Would you recommend that variant, or
   later parameters, for a general consumer population?
2. **Initialisation.** We start S from the 8.38 sleep-entry threshold at the
   first recorded sleep. Is there a better way to start it from a few days of
   sleep records, and how many prior days do you suggest?
3. **Fragmented sleep and naps.** Is it right to apply the wake equation to
   each awakening and the sleep equations to each fragment (and to naps), and
   should sleep inertia restart after short awakenings?
4. **Caffeine.** We have found no validated way to include caffeine in the
   TPM's KSS output (the 2004 paper mentioned it was being implemented). Is
   there unpublished or later work, or a dataset, you would point us to? Until
   then we leave caffeine out and show no estimate when caffeine was logged.
   Is that the approach you would recommend?
5. **Circadian phase.** Should phase come from a single chronotype question
   (as in Ingre 2014) or from usual sleep timing? Is there a recommended way
   to handle time-zone travel and daylight-saving changes?
6. **Using the KSS in the app.** May we show the KSS (version B, every step
   labelled) in a paid app? If so, what wording, attribution and citation do
   you require, and is there a licence or fee?
7. **Using the model in the app.** If we later show a model estimate, may we
   describe it as based on the Three-Process Model with your attribution? Any
   conditions or wording you want us to avoid?

## What we will not do without your input

Invent a caffeine coefficient, convert old 1–5 ratings into KSS, or show
model output to users.
