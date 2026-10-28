/**
 * Research-only reproduction of the ORIGINAL full TPM in Ingre et al. (2014),
 * equations 1.1–1.9, https://doi.org/10.1371/journal.pone.0108679 (CC BY).
 * Not imported by the website. No caffeine term or predictive validation is
 * claimed. The study's improved fitted models are not reproduced here.
 */
export const TPM = Object.freeze({
  upper: 14.3,
  lower: 2.4,
  wakeRate: -0.0353,
  brakeLevel: 12.2,
  sleepRate: Math.log((14.3 - 14) / (14.3 - 7.96)) / 8,
  inertiaAmplitude: -5.72,
  inertiaRate: -1.51,
  phaseHours: 16.8,
  sleepEntryThreshold: 8.38,
});

export type HistorySegment = {
  state: "sleep" | "awake" | "unknown";
  start: number;
  end: number;
};
export type TimedCaffeine = { at: number; mg: number };
export type ResearchInput = {
  at: number;
  timeZone: string;
  phaseHours: number;
  history: readonly HistorySegment[];
  caffeine: { complete: boolean; doses: readonly TimedCaffeine[] } | null;
};

function domain(level: number, hours: number) {
  if (
    !Number.isFinite(level) ||
    level < TPM.lower ||
    level > TPM.upper ||
    !Number.isFinite(hours) ||
    hours < 0
  ) {
    throw new RangeError(
      "Finite TPM state within its asymptotes and nonnegative hours required.",
    );
  }
}

export function wakeState(level: number, hours: number): number {
  domain(level, hours);
  return TPM.lower + (level - TPM.lower) * Math.exp(TPM.wakeRate * hours);
}

export function originalSleepState(level: number, hours: number): number {
  domain(level, hours);
  return TPM.upper - (TPM.upper - level) * Math.exp(TPM.sleepRate * hours);
}

export function sleepState(level: number, hours: number): number {
  domain(level, hours);
  if (level >= TPM.brakeLevel) return originalSleepState(level, hours);
  const rate = TPM.sleepRate * (TPM.brakeLevel - TPM.upper);
  const brakeAt = (TPM.brakeLevel - level) / rate;
  return hours <= brakeAt
    ? level + rate * hours
    : originalSleepState(TPM.brakeLevel, hours - brakeAt);
}

export function clockTerms(localHour: number, phaseHours: number) {
  if (!Number.isFinite(localHour) || !Number.isFinite(phaseHours)) {
    throw new RangeError("Finite local hour and circadian phase required.");
  }
  return {
    circadian: 2.5 * Math.cos(((2 * Math.PI) / 24) * (localHour - phaseHours)),
    ultradian:
      -0.5 +
      0.5 * Math.cos(((2 * Math.PI) / 12) * (localHour - phaseHours - 3)),
  };
}

function localHour(at: number, timeZone: string) {
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone,
    hourCycle: "h23",
    hour: "numeric",
    minute: "numeric",
    second: "numeric",
  }).formatToParts(new Date(at));
  const value = (type: string) =>
    Number(parts.find((p) => p.type === type)?.value);
  return value("hour") + value("minute") / 60 + value("second") / 3600;
}

export function evaluateResearchBaseline(input: ResearchInput) {
  const refuse = (reason: string) => ({
    status: "not-supported" as const,
    reason,
  });
  if (
    !Number.isFinite(input.at) ||
    !Number.isFinite(input.phaseHours) ||
    input.phaseHours < 0 ||
    input.phaseHours >= 24
  )
    return refuse("invalid-query");
  if (typeof input.timeZone !== "string" || input.timeZone.length === 0)
    return refuse("invalid-time-zone");
  try {
    localHour(input.at, input.timeZone);
  } catch {
    return refuse("invalid-time-zone");
  }
  const history = [...input.history].sort((a, b) => a.start - b.start);
  if (!history.length) return refuse("missing-sleep-history");
  for (let i = 0; i < history.length; i++) {
    const s = history[i];
    if (
      !Number.isFinite(s.start) ||
      !Number.isFinite(s.end) ||
      s.end <= s.start ||
      s.end > input.at ||
      !["sleep", "awake", "unknown"].includes(s.state)
    )
      return refuse("invalid-history");
    if (s.state === "unknown") return refuse("unknown-sleep-wake-state");
    if (i > 0 && history[i - 1].end !== s.start)
      return refuse("gap-or-overlap");
    if (i > 0 && history[i - 1].state === s.state)
      return refuse("split-episode");
  }
  if (
    history[0].state !== "sleep" ||
    history[history.length - 1]?.end !== input.at
  )
    return refuse("incomplete-history");
  const sleeps = history.filter((s) => s.state === "sleep");
  if (sleeps.length < 2) return refuse("needs-two-sleep-episodes");
  const hoursAwake = (input.at - sleeps[sleeps.length - 1].end) / 3_600_000;
  if (hoursAwake > 16) return refuse("outside-study-wake-window");
  if (input.caffeine?.complete !== true)
    return refuse("unknown-caffeine-history");
  for (const dose of input.caffeine.doses) {
    if (
      !Number.isFinite(dose.at) ||
      !Number.isFinite(dose.mg) ||
      dose.mg < 0 ||
      dose.at < history[0].start ||
      dose.at > input.at
    )
      return refuse("invalid-caffeine-history");
  }
  // Deliberately no invented washout threshold or KSS-per-mg coefficient.
  if (input.caffeine.doses.some((d) => d.mg > 0))
    return refuse("caffeine-effect-not-validated");

  const initialClock = clockTerms(
    localHour(history[0].start, input.timeZone),
    input.phaseHours,
  );
  let homeostatic =
    TPM.sleepEntryThreshold - initialClock.circadian - initialClock.ultradian;
  for (const s of history) {
    const hours = (s.end - s.start) / 3_600_000;
    homeostatic =
      s.state === "sleep"
        ? sleepState(homeostatic, hours)
        : wakeState(homeostatic, hours);
  }
  const clock = clockTerms(
    localHour(input.at, input.timeZone),
    input.phaseHours,
  );
  const inertia = TPM.inertiaAmplitude * Math.exp(TPM.inertiaRate * hoursAwake);
  const rawKss =
    10.6 - 0.6 * (homeostatic + clock.circadian + clock.ultradian + inertia);
  return {
    status: "research-baseline-only" as const,
    rawKss,
    boundedKss: Math.max(1, Math.min(9, rawKss)),
    components: { homeostatic, ...clock, inertia },
    hoursAwake,
    initialization:
      "Published assumed sleep-entry threshold; no individual calibration.",
    validation:
      "Equation reproduction only; no independent clinical or caffeine validation.",
  };
}
