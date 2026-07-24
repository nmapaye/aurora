import type { Dose, SleepSession } from '~/domain/models';

const HOUR_MS = 60 * 60 * 1000;

export type SleepRange = 'week' | 'month';
export type SleepChartPoint = { date: number; durationMs: number | null };

function localDayKey(timestamp: number) {
  const date = new Date(timestamp);
  return `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
}

export function getLocalCalendarDayStarts(now: number, days: number) {
  const end = new Date(now);
  end.setHours(0, 0, 0, 0);
  return Array.from({ length: days }, (_, index) => {
    const day = new Date(end);
    day.setDate(end.getDate() - (days - 1 - index));
    return day.getTime();
  });
}

function rangeDays(range: SleepRange) {
  return range === 'week' ? 7 : 30;
}

function selectRangeSessions(sessions: readonly SleepSession[], range: SleepRange, now: number) {
  const starts = getLocalCalendarDayStarts(now, rangeDays(range));
  const dayKeys = new Set(starts.map(localDayKey));
  return sessions.filter((session) =>
    Number.isFinite(session.start) &&
    Number.isFinite(session.end) &&
    session.end > session.start &&
    session.end <= now &&
    dayKeys.has(localDayKey(session.end)),
  );
}

function selectLatestSessionByNight(sessions: readonly SleepSession[]) {
  const selected = new Map<string, SleepSession>();
  for (const session of sessions) {
    const key = localDayKey(session.end);
    const current = selected.get(key);
    if (!current || session.end > current.end) selected.set(key, session);
  }
  return selected;
}

function median(values: readonly number[]) {
  const sorted = [...values].sort((left, right) => left - right);
  return sorted.length ? sorted[Math.floor(sorted.length / 2)] : 0;
}

function percentile(values: readonly number[], q: number) {
  const sorted = [...values].sort((left, right) => left - right);
  if (!sorted.length) return 0;
  return sorted[Math.max(0, Math.min(sorted.length - 1, Math.round(q * (sorted.length - 1))))] ?? 0;
}

export function formatSleepDuration(durationMs: number) {
  const totalMinutes = Math.round(durationMs / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return `${hours}h ${minutes}m`;
}

export function sleepSourceLabel(id: string) {
  return id.startsWith('healthkit:sleep:') ? 'Health' : 'Manual';
}

export function getCaffeineImpact(
  sessions: readonly SleepSession[],
  doses: readonly Dose[],
  range: SleepRange,
  now: number,
) {
  const nights = selectLatestSessionByNight(selectRangeSessions(sessions, range, now));
  const pairs = [...nights.values()].flatMap((session) => {
    const lastDose = doses
      .filter((dose) => dose.timestamp <= session.start && dose.timestamp >= session.start - 12 * HOUR_MS)
      .sort((left, right) => right.timestamp - left.timestamp)[0];
    if (!lastDose) return [];
    return [{
      deltaMin: Math.round((session.start - lastDose.timestamp) / 60_000),
      sleepMin: Math.round((session.end - session.start) / 60_000),
    }];
  });
  const deltas = pairs.map((pair) => pair.deltaMin);
  const durations = pairs.map((pair) => pair.sleepMin);
  return {
    qualifyingNights: pairs.length,
    medianDeltaMin: median(deltas),
    p10: percentile(deltas, 0.1),
    p90: percentile(deltas, 0.9),
    medianSleepMin: median(durations),
    showCorrelation: pairs.length >= 14,
  };
}

export function getSleepPresentation(
  sessions: readonly SleepSession[],
  targetSleepHours: number,
  range: SleepRange,
  now: number,
) {
  const days = rangeDays(range);
  const points: SleepChartPoint[] = getLocalCalendarDayStarts(now, days).map((date) => ({ date, durationMs: null }));
  const sessionsByDay = selectLatestSessionByNight(selectRangeSessions(sessions, range, now));
  points.forEach((point) => {
    const session = sessionsByDay.get(localDayKey(point.date));
    if (session) point.durationMs = session.end - session.start;
  });

  const recorded = points.filter((point) => point.durationMs !== null);
  const latest = [...sessionsByDay.values()].sort((left, right) => right.end - left.end)[0];
  const durationMs = latest ? latest.end - latest.start : 0;
  const targetDifferenceMs = latest ? durationMs - targetSleepHours * HOUR_MS : null;
  const dateRange = `${days} days ending ${new Intl.DateTimeFormat(undefined, { month: 'short', day: 'numeric' }).format(new Date(now))}`;
  const noun = recorded.length === 1 ? 'night' : 'nights';
  const accessibilitySummary = recorded.length
    ? `Time Asleep, ${dateRange}, ${recorded.length} ${noun} recorded. Latest duration ${formatSleepDuration(recorded[recorded.length - 1].durationMs ?? 0)}.`
    : `Time Asleep, ${dateRange}. No sleep data is available.`;

  return {
    days,
    dateRange,
    points,
    headline: latest ? formatSleepDuration(durationMs) : 'No Data',
    accessibilitySummary,
    lastNight: latest
      ? { session: latest, durationMs, wakeTime: latest.end, targetDifferenceMs }
      : null,
  };
}
