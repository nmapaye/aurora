import type { Dose, SleepSession } from '~/domain/models';

const HOUR_MS = 60 * 60 * 1000;
const SLEEP_EPISODE_GAP_MS = 2 * HOUR_MS;

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

type SleepEpisode = {
  sessions: SleepSession[];
  type: SleepSession['type'];
  sleepStart: number;
  wakeTime: number;
  durationMs: number;
};

function unionDuration(sessions: readonly SleepSession[]) {
  const ordered = [...sessions].sort(
    (left, right) => left.start - right.start || left.end - right.end,
  );
  let intervalStart = ordered[0]?.start ?? 0;
  let intervalEnd = ordered[0]?.end ?? 0;
  let durationMs = 0;
  for (const session of ordered.slice(1)) {
    if (session.start <= intervalEnd) {
      intervalEnd = Math.max(intervalEnd, session.end);
    } else {
      durationMs += intervalEnd - intervalStart;
      intervalStart = session.start;
      intervalEnd = session.end;
    }
  }
  return durationMs + intervalEnd - intervalStart;
}

function buildSleepEpisodes(sessions: readonly SleepSession[], now: number) {
  const ordered = sessions
    .filter((session) =>
      Number.isFinite(session.start) &&
      Number.isFinite(session.end) &&
      session.end > session.start &&
      session.end <= now,
    )
    .sort((left, right) => left.start - right.start || left.end - right.end);
  const grouped: SleepSession[][] = [];
  for (const session of ordered) {
    const current = grouped[grouped.length - 1];
    const currentEnd = current
      ? Math.max(...current.map((item) => item.end))
      : undefined;
    if (
      current &&
      current[0]?.type === session.type &&
      currentEnd !== undefined &&
      session.start - currentEnd <= SLEEP_EPISODE_GAP_MS
    ) {
      current.push(session);
    } else {
      grouped.push([session]);
    }
  }
  return grouped.flatMap<SleepEpisode>((episodeSessions) => {
    const first = episodeSessions[0];
    if (!first) return [];
    return [{
      sessions: episodeSessions,
      type: first.type,
      sleepStart: Math.min(...episodeSessions.map((session) => session.start)),
      wakeTime: Math.max(...episodeSessions.map((session) => session.end)),
      durationMs: unionDuration(episodeSessions),
    }];
  });
}

function selectRangeEpisodes(sessions: readonly SleepSession[], range: SleepRange, now: number) {
  const starts = getLocalCalendarDayStarts(now, rangeDays(range));
  const dayKeys = new Set(starts.map(localDayKey));
  return buildSleepEpisodes(sessions, now).filter((episode) =>
    dayKeys.has(localDayKey(episode.wakeTime)),
  );
}

function bucketEpisodesByWakeDay(episodes: readonly SleepEpisode[]) {
  const buckets = new Map<string, SleepEpisode[]>();
  episodes.forEach((episode) => {
    const key = localDayKey(episode.wakeTime);
    buckets.set(key, [...(buckets.get(key) ?? []), episode]);
  });
  return buckets;
}

function primarySleepEpisode(episodes: readonly SleepEpisode[]) {
  const sleepEpisodes = episodes.filter((episode) => episode.type === 'sleep');
  return [...sleepEpisodes].sort(
    (left, right) =>
      right.durationMs - left.durationMs || right.wakeTime - left.wakeTime,
  )[0];
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
  if (id.startsWith('demo:sleep:')) return 'Sample Data';
  return id.startsWith('healthkit:sleep:') ? 'Health' : 'Manual';
}

export function getCaffeineImpact(
  sessions: readonly SleepSession[],
  doses: readonly Dose[],
  range: SleepRange,
  now: number,
) {
  const wakeDays = bucketEpisodesByWakeDay(selectRangeEpisodes(sessions, range, now));
  const pairs = [...wakeDays.values()].flatMap((episodes) => {
    const night = primarySleepEpisode(episodes);
    if (!night) return [];
    const lastDose = doses
      .filter((dose) => dose.timestamp <= night.sleepStart && dose.timestamp >= night.sleepStart - 12 * HOUR_MS)
      .sort((left, right) => right.timestamp - left.timestamp)[0];
    if (!lastDose) return [];
    return [{
      deltaMin: Math.round((night.sleepStart - lastDose.timestamp) / 60_000),
      sleepMin: Math.round(night.durationMs / 60_000),
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
  const sessionsByDay = bucketEpisodesByWakeDay(selectRangeEpisodes(sessions, range, now));
  points.forEach((point) => {
    const episodes = sessionsByDay.get(localDayKey(point.date));
    if (episodes) {
      point.durationMs = episodes.reduce(
        (total, episode) => total + episode.durationMs,
        0,
      );
    }
  });

  const recorded = points.filter((point) => point.durationMs !== null);
  const latest = [...sessionsByDay.values()]
    .flatMap((episodes) => primarySleepEpisode(episodes) ?? [])
    .sort((left, right) => right.wakeTime - left.wakeTime)[0];
  const durationMs = latest?.durationMs ?? 0;
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
      ? {
          session: [...latest.sessions].sort(
            (left, right) => right.end - left.end,
          )[0],
          durationMs,
          sleepStart: latest.sleepStart,
          wakeTime: latest.wakeTime,
          targetDifferenceMs,
        }
      : null,
  };
}
