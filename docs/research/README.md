# Aurora research

Aurora's model numbers, defaults and health wording should trace back to published evidence. Each report below cites its sources. Each has a constant trace table (current value, recommended value, source, confidence), an implementation spec with test cases, and open questions. None of this is legal or medical advice; the claims report lists what needs a lawyer.

| Report | Covers | Main recommendation |
|---|---|---|
| [energy-model.md](energy-model.md) | Alertness score, daily (circadian) curve, sleep debt, sleep inertia, how caffeine changes alertness | Replace the hand-weighted formula with the Unified Model of Performance (Ramakrishnan et al. 2016, used by 2B-Alert). Show it on 0–100, rested day to no sleep. |
| [caffeine.md](caffeine.md) | Absorption, half-life, drink contents, cutoff calculation, sleep evidence, safety figures | Use a one-compartment model with first-order absorption, and keep the 5 h default half-life editable. Presets state their serving. Evidence goes in a static sheet, never next to the person's own numbers. |
| [sleep-and-check-in.md](sleep-and-check-in.md) | Sleep target, sleep episodes, recent-sleep summary, usual timing, energy check-in scale | No pre-filled 8 h target. One 90-minute episode rule. Recent sleep summarized over 24 h, 48 h and 7 wake days, without filling gaps. Check-in uses the Karolinska Sleepiness Scale, or Samn-Perelli as the fallback. |
| [claims-and-reminders.md](claims-and-reminders.md) | FDA/MHRA/Health Canada/TGA positioning, App Store and HealthKit rules, a copy audit, notification load, drink follow-ups | Fits FDA General Wellness. Rewrite the cutoff notification and other risky lines. Allow one notification a day that Aurora starts itself. Follow-ups are silent and come about 60 minutes after yesterday's drink. |

The reaction test changes (30 s, finger-down timing, versioned sessions) are tracked separately. The sleep and claims reports both say it must never be called a "PVT".

## Where the reports meet

- **Sleep into the model:** the energy model takes its sleep input from the sleep report: episodes, the 24 h / 48 h / 7-day summary, and no imputation of missing nights.
- **Caffeine into the model:** the caffeine report supplies `bodyMg` for the active-caffeine display. The energy model's caffeine effect has its own fitted time course, so feeding it `bodyMg` would count absorption twice. As a result, the half-life setting no longer changes the score.
- **Pre-filled values:** these defaults conflict with the rule that inputs never start with a value the person didn't give, and are flagged by more than one report:
  - the 8 h sleep target;
  - the 400 mg personal reference;
  - the 16:00 cutoff;
  - the 80 mg Drip custom entry.
- **Self-rating and performance:** the sleep report keeps the check-in (KSS), the reaction test and the modeled score separate, each compared only with the person's own history. The energy model shows its output on 0–100, not on the KSS scale.
- **Versioning:** model changes bump a version label. Earlier snapshots stay visible, labelled "Earlier model" or "Earlier 60-second test".
