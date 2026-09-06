import { alertnessScore, mgActive } from '~/domain/algorithm';
import type {
  CaffeineDoseInput,
  Dose,
  SleepSession,
  UserPrefs,
} from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import {
  addCalendarDays,
  isLocalDateKey,
  localDateKey,
} from '~/utils/calendar';
import { buildSleepEpisodes } from '~/features/sleep/presentation';
export type PlannedDose = {
  id: string;
  offsetMinutes: number;
  mg: number;
  label: string;
};
export type Scenario = { id: string; name: string; doses: PlannedDose[] };
export type ReductionPlan = {
  startDate: string;
  startMg: number;
  endMg: number;
  days: number;
};
export type Budget = {
  targetMg: number;
  allocations: { id: string; label: string; mg: number }[];
};
export type FocusWindow = { startMinutes: number; endMinutes: number };
export type CheckIn = {
  id: string;
  timestamp: number;
  rating: number;
  note: string;
};
export type DateWindow = { start: string; end: string };
export type Experiment = {
  id: string;
  question: string;
  baseline: DateWindow;
  comparison: DateWindow;
};
export type PlanningState = {
  scenarios: Scenario[];
  thresholdMg: number;
  sensitivityHours: [number, number, number];
  reduction: ReductionPlan | null;
  budget: Budget;
  focus: FocusWindow;
  checkIns: CheckIn[];
  experiments: Experiment[];
};
export const defaultPlanningState = (): PlanningState => ({
  scenarios: [],
  thresholdMg: 25,
  sensitivityHours: [3, 5, 7],
  reduction: null,
  budget: { targetMg: 200, allocations: [] },
  focus: { startMinutes: 60, endMinutes: 180 },
  checkIns: [],
  experiments: [],
});
const record = (v: unknown): Record<string, unknown> =>
  v && typeof v === 'object' && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
const numeric = (v: unknown, min: number, max: number): v is number =>
  typeof v === 'number' && Number.isFinite(v) && v >= min && v <= max;
const named = (v: unknown): v is string =>
  typeof v === 'string' && v.trim().length > 0 && v.length <= 200;
const note = (v: unknown): v is string =>
  typeof v === 'string' && v.length <= 2000;
const stamp = (v: unknown): v is number => numeric(v, 0, 8640000000000000);
const unique = <T extends { id: string }>(items: T[]) =>
  items.filter((x, i) => items.findIndex((y) => x.id === y.id) === i);
export function validScenario(v: unknown): v is Scenario {
  const s = record(v);
  return (
    named(s.id) &&
    named(s.name) &&
    Array.isArray(s.doses) &&
    s.doses.length <= 100 &&
    s.doses.every((d) => {
      const x = record(d);
      return (
        named(x.id) &&
        named(x.label) &&
        numeric(x.mg, 0, 2000) &&
        numeric(x.offsetMinutes, 0, 10080)
      );
    }) &&
    new Set(s.doses.map((d) => d.id)).size === s.doses.length
  );
}
export function validReduction(v: unknown): v is ReductionPlan {
  const r = record(v);
  return (
    typeof r.startDate === 'string' &&
    isLocalDateKey(r.startDate) &&
    numeric(r.startMg, 0, 2000) &&
    numeric(r.endMg, 0, 2000) &&
    r.endMg <= r.startMg &&
    numeric(r.days, 2, 365) &&
    Number.isInteger(r.days)
  );
}
export function validDateWindow(v: unknown): v is DateWindow {
  const w = record(v);
  return (
    typeof w.start === 'string' &&
    typeof w.end === 'string' &&
    isLocalDateKey(w.start) &&
    isLocalDateKey(w.end) &&
    w.start <= w.end &&
    dateValue(w.end) - dateValue(w.start) <= 366 * 86400000
  );
}
export function validExperiment(v: unknown): v is Experiment {
  const e = record(v);
  return (
    named(e.id) &&
    named(e.question) &&
    validDateWindow(e.baseline) &&
    validDateWindow(e.comparison) &&
    e.baseline.end < e.comparison.start
  );
}
export function normalizePlanning(v: unknown): PlanningState {
  const p = record(v),
    d = defaultPlanningState(),
    b = record(p.budget),
    f = record(p.focus);
  const array = <T>(a: unknown, valid: (v: unknown) => v is T): T[] =>
    Array.isArray(a) ? a.filter(valid) : [];
  return {
    scenarios: unique(array(p.scenarios, validScenario)),
    thresholdMg: numeric(p.thresholdMg, 0.1, 2000)
      ? p.thresholdMg
      : d.thresholdMg,
    sensitivityHours:
      Array.isArray(p.sensitivityHours) &&
      p.sensitivityHours.length === 3 &&
      p.sensitivityHours.every((h) => numeric(h, 0.5, 24))
        ? (p.sensitivityHours as [number, number, number])
        : d.sensitivityHours,
    reduction: validReduction(p.reduction) ? p.reduction : null,
    budget: {
      targetMg: numeric(b.targetMg, 0, 2000) ? b.targetMg : d.budget.targetMg,
      allocations: unique(
        array(b.allocations, (v): v is Budget['allocations'][number] => {
          const a = record(v);
          return named(a.id) && named(a.label) && numeric(a.mg, 0, 2000);
        }),
      ).slice(0, 100),
    },
    focus:
      numeric(f.startMinutes, 0, 10080) &&
      numeric(f.endMinutes, 0, 10080) &&
      f.endMinutes > f.startMinutes
        ? (f as FocusWindow)
        : d.focus,
    checkIns: unique(
      array(p.checkIns, (v): v is CheckIn => {
        const c = record(v);
        return (
          named(c.id) &&
          stamp(c.timestamp) &&
          numeric(c.rating, 1, 5) &&
          Number.isInteger(c.rating) &&
          note(c.note)
        );
      }),
    ),
    experiments: unique(array(p.experiments, validExperiment)),
  };
}
export const isPersonal = (v: { id: string }) => !v.id.startsWith('demo:');
export function thresholdCrossing(
  doses: CaffeineDoseInput[],
  halfLife: number,
  threshold: number,
  now: number,
): number | null {
  if (
    !numeric(halfLife, 0.5, 24) ||
    !numeric(threshold, 0.1, 2000) ||
    !stamp(now)
  )
    return null;
  const valid = doses.filter(
    (d) => stamp(d.timestamp) && numeric(d.mg, 0, 2000),
  );
  const finalTime = Math.max(now, ...valid.map((d) => d.timestamp));
  const active = mgActive(finalTime, valid, halfLife);
  const result =
    active <= threshold
      ? finalTime
      : finalTime + halfLife * 3600000 * Math.log2(active / threshold);
  return Number.isFinite(new Date(result).getTime()) ? result : null;
}
export function scenarioInputs(
  scenario: Scenario,
  baseline: Dose[],
  now: number,
): CaffeineDoseInput[] {
  return [
    ...baseline.filter(
      (d) =>
        isPersonal(d) &&
        d.timestamp <= now &&
        stamp(d.timestamp) &&
        numeric(d.mg, 0, 2000),
    ),
    ...scenario.doses.map((d) => ({
      timestamp: now + d.offsetMinutes * 60000,
      mg: d.mg,
    })),
  ];
}
export function projectScenario(
  scenario: Scenario,
  baseline: Dose[],
  sleeps: SleepSession[],
  prefs: UserPrefs,
  now: number,
  bedtime: number,
  focus: FocusWindow,
) {
  const doses = scenarioInputs(scenario, baseline, now),
    personalSleep = sleeps.filter((s) => isPersonal(s) && s.end <= now);
  const end = Math.max(
    now + 24 * 3600000,
    bedtime,
    now + Math.max(0, ...scenario.doses.map((d) => d.offsetMinutes)) * 60000,
  );
  const events = doses.filter((d) => d.timestamp >= now);
  const times = new Set<number>([
    now,
    bedtime,
    ...events.flatMap((d) => [d.timestamp - 1, d.timestamp]),
  ]);
  // Hourly points plus exact dose events let readers inspect abrupt modeled rises.
  for (let t = now; t <= end; t += 3600000) times.add(t);
  const curve = [...times]
    .filter((t) => t >= now)
    .sort((a, b) => a - b)
    .map((timestamp) => ({
      timestamp,
      mg: mgActive(timestamp, doses, prefs.halfLife),
      alertness: alertnessScore(timestamp, doses, personalSleep, prefs),
      event: events.some((d) => d.timestamp - 1 === timestamp)
        ? 'before-dose'
        : events.some((d) => d.timestamp === timestamp)
          ? 'dose'
          : null,
    }));
  const focusScores: number[] = [];
  for (
    let minutes = focus.startMinutes;
    minutes < focus.endMinutes;
    minutes += 15
  )
    focusScores.push(
      alertnessScore(now + minutes * 60000, doses, personalSleep, prefs),
    );
  focusScores.push(
    alertnessScore(now + focus.endMinutes * 60000, doses, personalSleep, prefs),
  );
  return {
    plannedMg: scenario.doses.reduce((sum, d) => sum + d.mg, 0),
    baselineTodayMg: baseline
      .filter(
        (d) =>
          isPersonal(d) &&
          d.timestamp <= now &&
          localDateKey(d.timestamp) === localDateKey(now),
      )
      .reduce((sum, d) => sum + d.mg, 0),
    bedtimeMg: mgActive(bedtime, doses, prefs.halfLife),
    curve,
    focusMean: focusScores.reduce((a, b) => a + b, 0) / focusScores.length,
    focusSamples: focusScores.length,
  };
}
function dateValue(key: string) {
  const [y, m, d] = key.split('-').map(Number);
  const date = new Date(0);
  date.setFullYear(y, m - 1, d);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}
export function reductionTargets(
  plan: ReductionPlan,
): { date: string; mg: number }[] {
  if (!validReduction(plan)) return [];
  return Array.from({ length: plan.days }, (_, i) => ({
    date: localDateKey(addCalendarDays(dateValue(plan.startDate), i)),
    mg:
      Math.round(
        (plan.startMg + ((plan.endMg - plan.startMg) * i) / (plan.days - 1)) *
          10,
      ) / 10,
  }));
}
export function budgetBalance(budget: Budget) {
  const allocatedMg = budget.allocations.reduce((s, a) => s + a.mg, 0);
  return { allocatedMg, remainingMg: budget.targetMg - allocatedMg };
}
function mean(values: number[]) {
  return values.length
    ? values.reduce((a, b) => a + b, 0) / values.length
    : null;
}
export function experimentWindow(
  window: DateWindow,
  doses: Dose[],
  zeroDays: string[],
  sleeps: SleepSession[],
  checkIns: CheckIn[],
  tests: VigilanceSession[],
  now: number,
) {
  const start = dateValue(window.start),
    end = Math.min(addCalendarDays(dateValue(window.end), 1), now + 1);
  const days: string[] = [];
  for (let t = start; t < end; t = addCalendarDays(t, 1))
    days.push(localDateKey(t));
  const caffeineValues: number[] = [];
  days.forEach((day) => {
    const entries = doses.filter(
      (d) =>
        isPersonal(d) &&
        d.timestamp <= now &&
        localDateKey(d.timestamp) === day,
    );
    if (entries.length || zeroDays.includes(day))
      caffeineValues.push(entries.reduce((a, d) => a + d.mg, 0));
  });
  const episodes = buildSleepEpisodes(
    sleeps.filter((s) => isPersonal(s) && s.end <= now),
    now,
  );
  const sleepHours = days.flatMap((day) => {
    const entries = episodes.filter((e) => localDateKey(e.wakeTime) === day);
    return entries.length
      ? [entries.reduce((sum, e) => sum + e.durationMs, 0) / 3600000]
      : [];
  });
  const ratings = checkIns
    .filter((c) => isPersonal(c) && c.timestamp >= start && c.timestamp < end)
    .map((c) => c.rating);
  const vigilance = tests
    .filter(
      (t) =>
        isPersonal(t) &&
        t.completedAt >= start &&
        t.completedAt < end &&
        t.validReactionCount > 0 &&
        t.medianReactionMs !== null,
    )
    .map((t) => t.medianReactionMs!);
  return {
    days: days.length,
    caffeine: {
      count: caffeineValues.length,
      mean: mean(caffeineValues),
      missingDays: days.length - caffeineValues.length,
    },
    sleep: {
      count: sleepHours.length,
      mean: mean(sleepHours),
      missingDays: days.length - sleepHours.length,
    },
    checkIns: { count: ratings.length, mean: mean(ratings) },
    vigilance: { count: vigilance.length, mean: mean(vigilance) },
  };
}
