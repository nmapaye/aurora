import type { SleepSession } from '~/domain/models';

const DAY_MS = 24 * 60 * 60 * 1000;

export type SleepRange = 'week' | 'month';
export type SleepChartPoint = { date: number; durationMs: number | null };

function startOfDay(timestamp: number) {
  const date = new Date(timestamp);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
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

export function getSleepPresentation(
  sessions: readonly SleepSession[],
  targetSleepHours: number,
  range: SleepRange,
  now: number,
) {
  const days = range === 'week' ? 7 : 30;
  const endDay = startOfDay(now);
  const startDay = endDay - (days - 1) * DAY_MS;
  const points: SleepChartPoint[] = Array.from({ length: days }, (_, index) => ({
    date: startDay + index * DAY_MS,
    durationMs: null,
  }));

  const sessionsByDay = new Map<number, SleepSession>();
  for (const session of sessions) {
    if (!Number.isFinite(session.start) || !Number.isFinite(session.end) || session.end <= session.start) continue;
    const day = startOfDay(session.end);
    if (day < startDay || day > endDay) continue;
    const existing = sessionsByDay.get(day);
    if (!existing || session.end > existing.end) sessionsByDay.set(day, session);
  }
  points.forEach((point) => {
    const session = sessionsByDay.get(point.date);
    if (session) point.durationMs = session.end - session.start;
  });

  const recorded = points.filter((point) => point.durationMs !== null);
  const latest = [...sessions]
    .filter((session) => session.end <= now && session.end > session.start)
    .sort((left, right) => right.end - left.end)[0];
  const durationMs = latest ? latest.end - latest.start : 0;
  const targetDifferenceMs = latest ? durationMs - targetSleepHours * 60 * 60 * 1000 : null;
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
      ? {
          session: latest,
          durationMs,
          wakeTime: latest.end,
          targetDifferenceMs,
        }
      : null,
  };
}
