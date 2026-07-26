import type { Dose } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';

export type InsightsRange = '7' | '14' | '30';

export const DEFAULT_INSIGHTS_RANGE: InsightsRange = '14';

export type InsightsChartPoint = { date: number; mg: number | null };

type SourceMixItem = { label: string; mg: number; pct: number };
type DaypartItem = { label: 'Morning' | 'Midday' | 'Evening' | 'Late'; mg: number };

const DAY_MS = 24 * 60 * 60 * 1000;

function localDayStart(timestamp: number) {
  const date = new Date(timestamp);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

function localDayKey(timestamp: number) {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

export function getInsightsRangeDays(range: InsightsRange = DEFAULT_INSIGHTS_RANGE) {
  return Number(range);
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

function normalizeSource(source?: string) {
  if (!source) return 'Other';
  const value = source.toLowerCase();
  if (value.includes('espresso') || value.includes('drip') || value.includes('brew')) return 'Coffee';
  if (value.includes('tea') || value.includes('matcha')) return 'Tea';
  if (value.includes('energy')) return 'Energy';
  if (value.includes('pill')) return 'Pills';
  return 'Other';
}

function formatDateRange(days: number, now: number) {
  const starts = getInsightsDayStarts(now, days);
  const formatter = new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' });
  return `${days} days · ${formatter.format(new Date(starts[0] ?? now))}–${formatter.format(new Date(now))}`;
}

function directionFor(points: readonly InsightsChartPoint[]) {
  const recorded = points.filter((point): point is { date: number; mg: number } => point.mg !== null);
  if (recorded.length < 2) return 'not enough recorded days to describe a direction';
  const first = recorded[0]?.mg ?? 0;
  const last = recorded[recorded.length - 1]?.mg ?? 0;
  if (last > first) return 'intake is increasing across recorded days';
  if (last < first) return 'intake is decreasing across recorded days';
  return 'intake is steady across recorded days';
}

function selectDoses(doses: readonly Dose[], starts: readonly number[], now: number) {
  const allowedDays = new Set(starts.map(localDayKey));
  return doses.filter(
    (dose) =>
      Number.isFinite(dose.timestamp) &&
      Number.isFinite(dose.mg) &&
      dose.timestamp <= now &&
      allowedDays.has(localDayKey(dose.timestamp)),
  );
}

function selectVigilanceSessions(
  sessions: readonly VigilanceSession[],
  starts: readonly number[],
  now: number,
) {
  const allowedDays = new Set(starts.map(localDayKey));
  return sessions
    .filter(
      (session) =>
        Number.isFinite(session.completedAt) &&
        session.completedAt <= now &&
        allowedDays.has(localDayKey(session.completedAt)),
    )
    .sort((left, right) => left.completedAt - right.completedAt);
}

function getDayparts(doses: readonly Dose[]): DaypartItem[] {
  const values = [0, 0, 0, 0];
  for (const dose of doses) {
    const hour = new Date(dose.timestamp).getHours();
    const index = hour >= 5 && hour < 11 ? 0 : hour >= 11 && hour < 17 ? 1 : hour >= 17 && hour < 21 ? 2 : 3;
    values[index] += dose.mg;
  }
  return [
    { label: 'Morning', mg: values[0] ?? 0 },
    { label: 'Midday', mg: values[1] ?? 0 },
    { label: 'Evening', mg: values[2] ?? 0 },
    { label: 'Late', mg: values[3] ?? 0 },
  ];
}

function getSourceMix(doses: readonly Dose[]): SourceMixItem[] {
  const totals = new Map<string, number>();
  for (const dose of doses) {
    const label = normalizeSource(dose.source);
    totals.set(label, (totals.get(label) ?? 0) + dose.mg);
  }
  const entries = [...totals.entries()].sort((left, right) => right[1] - left[1]);
  const totalMg = entries.reduce((sum, [, mg]) => sum + mg, 0);
  return entries.map(([label, mg]) => ({ label, mg, pct: totalMg ? Math.round((mg / totalMg) * 100) : 0 }));
}

function getAdherence(points: readonly InsightsChartPoint[], dailyLimit: number) {
  const totals = points.map((point) => point.mg ?? 0);
  const daysWithData = totals.filter((total) => total > 0);
  const withinLimit = daysWithData.filter((total) => total <= dailyLimit);
  let streak = 0;
  for (let index = totals.length - 1; index >= 0; index -= 1) {
    const total = totals[index] ?? 0;
    if (total > 0 && total <= dailyLimit) streak += 1;
    else if (total > 0) {
      streak = 0;
      break;
    }
  }
  return { pct: daysWithData.length ? Math.round((withinLimit.length / daysWithData.length) * 100) : 0, streak };
}

function getVigilanceSummary(sessions: readonly VigilanceSession[]) {
  const latest = sessions[sessions.length - 1];
  const averageScore = sessions.length
    ? Math.round(sessions.reduce((sum, session) => sum + session.score, 0) / sessions.length)
    : undefined;
  return {
    latest,
    averageScore,
    trendSessions: sessions.slice(-7),
    hasBaseline: sessions.length >= 3,
  };
}

function makeWindow(doses: readonly Dose[], starts: readonly number[], now: number) {
  const selected = selectDoses(doses, starts, now);
  const totalsByDay = new Map<number, number>();
  for (const dose of selected) {
    const start = localDayStart(dose.timestamp);
    totalsByDay.set(start, (totalsByDay.get(start) ?? 0) + dose.mg);
  }
  const points = starts.map((date) => ({ date, mg: totalsByDay.get(date) ?? null }));
  const totalMg = selected.reduce((sum, dose) => sum + dose.mg, 0);
  return { starts, selected, points, totalMg, averageMg: Math.round(totalMg / Math.max(1, starts.length)) };
}

export function getInsightsPresentation(
  doses: readonly Dose[],
  vigilanceSessions: readonly VigilanceSession[],
  dailyLimit: number,
  range: InsightsRange = DEFAULT_INSIGHTS_RANGE,
  now = Date.now(),
) {
  const days = getInsightsRangeDays(range);
  const currentStarts = getInsightsDayStarts(now, days);
  const previousEnd = new Date(currentStarts[0] ?? now);
  previousEnd.setDate(previousEnd.getDate() - 1);
  const previousStarts = getInsightsDayStarts(previousEnd.getTime(), days);
  const current = makeWindow(doses, currentStarts, now);
  const previous = makeWindow(doses, previousStarts, previousEnd.getTime() + DAY_MS - 1);
  const selectedSessions = selectVigilanceSessions(vigilanceSessions, currentStarts, now);
  const isEmpty = current.selected.length === 0;
  const deltaPct = previous.averageMg > 0
    ? Math.round((current.averageMg / previous.averageMg - 1) * 100)
    : undefined;
  const dateRange = formatDateRange(days, now);
  const recordedDays = current.points.filter((point) => point.mg !== null).length;
  const accessibilitySummary = isEmpty
    ? `Caffeine intake, ${dateRange}. No caffeine data is available.`
    : `Caffeine intake, ${dateRange}, ${recordedDays} recorded ${recordedDays === 1 ? 'day' : 'days'}. ${directionFor(current.points)}.`;

  return {
    range,
    days,
    dateRange,
    current,
    previous,
    points: current.points,
    headline: isEmpty ? 'No Data' : `${current.averageMg} mg/day`,
    deltaPct,
    deltaLabel: typeof deltaPct === 'number' ? `${deltaPct >= 0 ? 'Up' : 'Down'} ${Math.abs(deltaPct)}% vs prior window` : 'Building baseline',
    adherence: getAdherence(current.points, dailyLimit),
    dayparts: getDayparts(current.selected),
    sourceMix: getSourceMix(current.selected),
    vigilance: getVigilanceSummary(selectedSessions),
    isEmpty,
    accessibilitySummary,
  };
}
