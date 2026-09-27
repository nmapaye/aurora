import type { Dose } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import {
  formatSignalDay,
  isSampleId,
  type SignalCardModel,
} from '~/features/signals/model';

// Insights describes what was recorded over a range. A day with no entries is
// "no record", never 0 mg; averages count recorded days only; a comparison
// with the previous period appears only when both periods have enough
// recorded days. Nothing here judges intake against a limit or suggests a
// dose, bedtime, or wake time.

export type InsightsRange = '7' | '14' | '30';

export const DEFAULT_INSIGHTS_RANGE: InsightsRange = '14';

// A personal Reaction Test baseline needs this many tests in the last 30 days.
export const REACTION_BASELINE_TESTS = 3;
export const REACTION_BASELINE_WINDOW_DAYS = 30;
// Periods whose averages differ by less than this read as "about the same".
export const TREND_STEADY_PCT = 10;

export type RecordSource = 'Manual' | 'Sample Data' | 'Manual and Sample Data';

export type InsightsChartPoint = {
  date: number;
  // null means nothing was recorded that day, not zero intake.
  mg: number | null;
  entries: number;
  source?: RecordSource;
};

type DrinkMixItem = { label: string; mg: number; pct: number };
type DaypartItem = { label: 'Morning' | 'Midday' | 'Evening' | 'Late'; mg: number; entries: number };

function localDayStart(timestamp: number) {
  const date = new Date(timestamp);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

function localDayEnd(timestamp: number) {
  const date = new Date(timestamp);
  date.setHours(23, 59, 59, 999);
  return date.getTime();
}

function localDayKey(timestamp: number) {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

function plural(count: number, one: string, many = `${one}s`) {
  return `${count} ${count === 1 ? one : many}`;
}

function formatShortDate(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toDateString();
  }
}

function formatChartDay(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, { weekday: 'short', month: 'short', day: 'numeric' }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toDateString();
  }
}

export function getInsightsRangeDays(range: InsightsRange = DEFAULT_INSIGHTS_RANGE) {
  return Number(range);
}

// The minimum recorded days each period needs before Insights compares them:
// half the range, and never fewer than four.
export function getTrendMinimumDays(days: number) {
  return Math.max(4, Math.ceil(days / 2));
}

export function getInsightsDayStarts(now: number, days: number) {
  const end = new Date(now);
  end.setHours(0, 0, 0, 0);
  return Array.from({ length: days }, (_, index) => {
    const day = new Date(end);
    day.setDate(end.getDate() - (days - 1 - index));
    return day.getTime();
  });
}

export function recordSourceLabel(ids: readonly string[]): RecordSource | undefined {
  if (ids.length === 0) return undefined;
  const sample = ids.filter(isSampleId).length;
  if (sample === 0) return 'Manual';
  return sample === ids.length ? 'Sample Data' : 'Manual and Sample Data';
}

function normalizeDrink(source?: string) {
  if (!source) return 'Other';
  const value = source.toLowerCase();
  if (value.includes('espresso') || value.includes('drip') || value.includes('brew') || value.includes('coffee')) return 'Coffee';
  if (value.includes('tea') || value.includes('matcha')) return 'Tea';
  if (value.includes('energy')) return 'Energy';
  if (value.includes('pill')) return 'Pills';
  return 'Other';
}

function formatDateRange(days: number, now: number) {
  const starts = getInsightsDayStarts(now, days);
  return `${days} days · ${formatShortDate(starts[0] ?? now)}–${formatShortDate(now)}`;
}

function isValidDose(dose: Dose) {
  return Number.isFinite(dose.timestamp) && Number.isFinite(dose.mg);
}

function selectDoses(doses: readonly Dose[], starts: readonly number[], now: number) {
  const allowedDays = new Set(starts.map(localDayKey));
  return doses.filter(
    (dose) => isValidDose(dose) && dose.timestamp <= now && allowedDays.has(localDayKey(dose.timestamp)),
  );
}

function getDayparts(doses: readonly Dose[]): DaypartItem[] {
  const items: DaypartItem[] = [
    { label: 'Morning', mg: 0, entries: 0 },
    { label: 'Midday', mg: 0, entries: 0 },
    { label: 'Evening', mg: 0, entries: 0 },
    { label: 'Late', mg: 0, entries: 0 },
  ];
  for (const dose of doses) {
    const hour = new Date(dose.timestamp).getHours();
    const index = hour >= 5 && hour < 11 ? 0 : hour >= 11 && hour < 17 ? 1 : hour >= 17 && hour < 21 ? 2 : 3;
    items[index].mg += dose.mg;
    items[index].entries += 1;
  }
  return items;
}

function getDrinkMix(doses: readonly Dose[]): DrinkMixItem[] {
  const totals = new Map<string, number>();
  for (const dose of doses) {
    const label = normalizeDrink(dose.source);
    totals.set(label, (totals.get(label) ?? 0) + dose.mg);
  }
  const entries = [...totals.entries()].sort((left, right) => right[1] - left[1]);
  const totalMg = entries.reduce((sum, [, mg]) => sum + mg, 0);
  return entries.map(([label, mg]) => ({ label, mg, pct: totalMg ? Math.round((mg / totalMg) * 100) : 0 }));
}

function makeWindow(doses: readonly Dose[], starts: readonly number[], now: number) {
  const selected = selectDoses(doses, starts, now);
  const byDay = new Map<number, Dose[]>();
  for (const dose of selected) {
    const start = localDayStart(dose.timestamp);
    byDay.set(start, [...(byDay.get(start) ?? []), dose]);
  }
  const points: InsightsChartPoint[] = starts.map((date) => {
    const dayDoses = byDay.get(date);
    if (!dayDoses) return { date, mg: null, entries: 0 };
    return {
      date,
      mg: Math.round(dayDoses.reduce((sum, dose) => sum + dose.mg, 0)),
      entries: dayDoses.length,
      source: recordSourceLabel(dayDoses.map((dose) => dose.id)),
    };
  });
  const recordedDays = points.filter((point) => point.mg !== null).length;
  const totalMg = Math.round(selected.reduce((sum, dose) => sum + dose.mg, 0));
  return {
    starts,
    selected,
    points,
    totalMg,
    recordedDays,
    // Per recorded day: days with no record are unknown, not zero.
    averageMg: recordedDays ? Math.round(totalMg / recordedDays) : null,
    source: recordSourceLabel(selected.map((dose) => dose.id)),
  };
}

export type InsightsTrend =
  | {
      status: 'insufficient';
      requiredDays: number;
      currentDays: number;
      previousDays: number;
      text: string;
    }
  | {
      status: 'compared';
      direction: 'higher' | 'lower' | 'similar';
      requiredDays: number;
      currentDays: number;
      previousDays: number;
      text: string;
      detail: string;
    };

function getTrend(
  current: ReturnType<typeof makeWindow>,
  previous: ReturnType<typeof makeWindow>,
  days: number,
): InsightsTrend {
  const requiredDays = getTrendMinimumDays(days);
  const counts = { requiredDays, currentDays: current.recordedDays, previousDays: previous.recordedDays };
  if (
    current.recordedDays < requiredDays ||
    previous.recordedDays < requiredDays ||
    current.averageMg === null ||
    previous.averageMg === null ||
    previous.averageMg <= 0
  ) {
    return {
      status: 'insufficient',
      ...counts,
      text: `A comparison with the previous ${days} days appears once each period has ${requiredDays} recorded days. This period has ${current.recordedDays}; the previous has ${previous.recordedDays}.`,
    };
  }
  const pct = Math.round((current.averageMg / previous.averageMg - 1) * 100);
  const direction = Math.abs(pct) < TREND_STEADY_PCT ? 'similar' : pct > 0 ? 'higher' : 'lower';
  const text =
    direction === 'similar'
      ? `About the same as the previous ${days} days`
      : `About ${Math.abs(pct)}% ${direction} than the previous ${days} days`;
  return {
    status: 'compared',
    direction,
    ...counts,
    text,
    detail: `${current.averageMg} mg vs ${previous.averageMg} mg per recorded day · ${current.recordedDays} and ${previous.recordedDays} recorded days`,
  };
}

// One Reaction Test signal. The latest test is an observation with its date
// and source; a baseline (the median of recent tests) appears only once there
// are enough tests, so one or two results never read as an established norm.
export function reactionInsightSignal(
  sessions: readonly VigilanceSession[],
  now: number,
): SignalCardModel & { baseline: 'none' | 'building' | 'established'; recentTests: number } {
  const valid = sessions
    .filter((session) => Number.isFinite(session.completedAt) && session.completedAt <= now)
    .sort((left, right) => left.completedAt - right.completedAt);
  const latest = valid[valid.length - 1];
  const base = { id: 'insights-reaction-test', label: 'Reaction Test', destination: 'Take Reaction Test' };
  if (!latest) {
    return {
      ...base,
      status: 'empty',
      period: 'No test yet',
      context: `A 60-second test of reaction speed. A personal baseline appears after ${REACTION_BASELINE_TESTS} tests.`,
      baseline: 'none',
      recentTests: 0,
    };
  }
  const windowStart = new Date(now);
  windowStart.setHours(0, 0, 0, 0);
  windowStart.setDate(windowStart.getDate() - (REACTION_BASELINE_WINDOW_DAYS - 1));
  const recent = valid.filter((session) => session.completedAt >= windowStart.getTime());
  const source = recordSourceLabel([latest.id]) === 'Sample Data' ? 'Sample Data' : 'Recorded';
  const detail =
    latest.medianReactionMs !== null
      ? `${latest.rating} · ${Math.round(latest.medianReactionMs)} ms median`
      : latest.rating;
  if (recent.length < REACTION_BASELINE_TESTS) {
    return {
      ...base,
      status: source === 'Sample Data' ? 'sample' : 'observed',
      period: formatSignalDay(latest.completedAt, now),
      source,
      value: `${latest.score}`,
      context: `${detail} · ${recent.length} of ${REACTION_BASELINE_TESTS} tests toward a baseline (last ${REACTION_BASELINE_WINDOW_DAYS} days)`,
      baseline: 'building',
      recentTests: recent.length,
    };
  }
  const scores = recent.map((session) => session.score).sort((a, b) => a - b);
  const middle = Math.floor(scores.length / 2);
  const median = scores.length % 2 ? scores[middle] : Math.round((scores[middle - 1] + scores[middle]) / 2);
  const recentSource = recordSourceLabel(recent.map((session) => session.id));
  return {
    ...base,
    status: source === 'Sample Data' ? 'sample' : 'observed',
    period: formatSignalDay(latest.completedAt, now),
    source,
    value: `${latest.score}`,
    context: `${detail} · Baseline ${median}, median of ${recent.length} tests in the last ${REACTION_BASELINE_WINDOW_DAYS} days${recentSource === 'Manual and Sample Data' ? ' (includes Sample Data)' : ''}`,
    baseline: 'established',
    recentTests: recent.length,
  };
}

export function describeInsightsChartDay(point: InsightsChartPoint) {
  const title = formatChartDay(point.date);
  const value =
    point.mg === null
      ? 'No record'
      : [`${point.mg} mg`, plural(point.entries, 'entry', 'entries'), point.source].filter(Boolean).join(' · ');
  return { title, value, text: `${title}, ${value}` };
}

export function getInsightsPresentation(
  doses: readonly Dose[],
  vigilanceSessions: readonly VigilanceSession[],
  range: InsightsRange = DEFAULT_INSIGHTS_RANGE,
  now = Date.now(),
) {
  const days = getInsightsRangeDays(range);
  const currentStarts = getInsightsDayStarts(now, days);
  const previousEnd = new Date(currentStarts[0] ?? now);
  previousEnd.setDate(previousEnd.getDate() - 1);
  const previousStarts = getInsightsDayStarts(previousEnd.getTime(), days);
  const current = makeWindow(doses, currentStarts, now);
  const previous = makeWindow(
    doses,
    previousStarts,
    localDayEnd(previousStarts[previousStarts.length - 1] ?? previousEnd.getTime()),
  );
  const isEmpty = current.recordedDays === 0;
  const dateRange = formatDateRange(days, now);
  const missingDays = days - current.recordedDays;
  const headline = current.averageMg === null ? undefined : `${current.averageMg} mg`;
  const period = isEmpty
    ? dateRange
    : `Average of ${plural(current.recordedDays, 'recorded day')} · ${dateRange}`;
  const accessibilitySummary = isEmpty
    ? `Caffeine intake, ${dateRange}. No caffeine recorded in this range.`
    : `Caffeine intake, ${dateRange}. ${headline} average per recorded day across ${plural(current.recordedDays, 'recorded day')}${current.source ? `, ${current.source}` : ''}. ${plural(missingDays, 'day')} with no record.`;
  const latestRecordedIndex = current.points.reduce(
    (latest, point, index) => (point.mg !== null ? index : latest),
    current.points.length - 1,
  );

  return {
    range,
    days,
    dateRange,
    current,
    previous,
    points: current.points,
    recordedDays: current.recordedDays,
    missingDays,
    headline,
    period,
    source: current.source,
    trend: getTrend(current, previous, days),
    dayparts: getDayparts(current.selected),
    drinkMix: getDrinkMix(current.selected),
    reaction: reactionInsightSignal(vigilanceSessions, now),
    latestRecordedIndex,
    isEmpty,
    accessibilitySummary,
  };
}
