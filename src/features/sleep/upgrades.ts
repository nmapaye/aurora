import type { SleepSession } from '~/domain/models';
import {
  addCalendarDays,
  isLocalDateKey,
  localDateKey,
} from '~/utils/calendar';
import {
  buildSleepEpisodes,
  getLocalCalendarDayStarts,
  getSleepPresentation,
  sleepSourceLabel,
} from './presentation';
export type SleepTimes = { bedtime: number; wake: number };
export type SleepAnnotation = { quality: number; note: string };
export type SleepRoutines = {
  weekly: SleepTimes[];
  weeklyConfigured: boolean;
  exceptions: Record<string, SleepTimes>;
  annotations: Record<string, SleepAnnotation>;
  timer: { start: number; end?: number } | null;
  windDown: { enabled: boolean; leadMinutes: number };
};
export function defaultSleepRoutines(targetHours: number): SleepRoutines {
  const duration =
    Number.isFinite(targetHours) && targetHours > 0 ? targetHours : 8;
  return {
    weeklyConfigured: false,
    weekly: Array.from({ length: 7 }, () => ({
      bedtime: 1350,
      wake: (1350 + Math.round(duration * 60)) % 1440,
    })),
    exceptions: {},
    annotations: {},
    timer: null,
    windDown: { enabled: false, leadMinutes: 30 },
  };
}
const record = (x: unknown): Record<string, unknown> =>
  typeof x === 'object' && x !== null && !Array.isArray(x)
    ? (x as Record<string, unknown>)
    : {};
const minute = (x: unknown): x is number =>
  typeof x === 'number' && Number.isInteger(x) && x >= 0 && x < 1440;
export function validSleepTimes(x: unknown): x is SleepTimes {
  const v = record(x);
  return minute(v.bedtime) && minute(v.wake) && v.bedtime !== v.wake;
}
export function normalizeSleepRoutines(
  raw: unknown,
  targetHours: number,
): SleepRoutines {
  const defaults = defaultSleepRoutines(targetHours),
    v = record(raw);
  const weekly = defaults.weekly.map((fallback, i) =>
    Array.isArray(v.weekly) && validSleepTimes(v.weekly[i])
      ? { ...v.weekly[i] }
      : fallback,
  );
  const exceptions = Object.fromEntries(
    Object.entries(record(v.exceptions)).filter(
      ([date, times]) => isLocalDateKey(date) && validSleepTimes(times),
    ),
  ) as Record<string, SleepTimes>;
  const annotations: SleepRoutines['annotations'] = {};
  for (const [id, value] of Object.entries(record(v.annotations))) {
    const a = record(value);
    if (
      Number.isInteger(a.quality) &&
      Number(a.quality) >= 1 &&
      Number(a.quality) <= 5 &&
      typeof a.note === 'string'
    )
      annotations[id] = {
        quality: Number(a.quality),
        note: a.note.slice(0, 2000),
      };
  }
  const t = record(v.timer),
    w = record(v.windDown);
  const validStart =
    typeof t.start === 'number' &&
    Number.isFinite(new Date(t.start).getTime()) &&
    t.start > 0;
  const validEnd =
    typeof t.end === 'number' &&
    Number.isFinite(new Date(t.end).getTime()) &&
    Number(t.end) > Number(t.start);
  return {
    weekly,
    weeklyConfigured: v.weeklyConfigured === true,
    exceptions,
    annotations,
    timer: validStart
      ? { start: Number(t.start), ...(validEnd ? { end: Number(t.end) } : {}) }
      : null,
    windDown: {
      enabled: w.enabled === true,
      leadMinutes:
        typeof w.leadMinutes === 'number' &&
        Number.isInteger(w.leadMinutes) &&
        w.leadMinutes >= 0 &&
        w.leadMinutes <= 180
          ? w.leadMinutes
          : 30,
    },
  };
}
export function scheduledSleep(
  state: SleepRoutines,
  date: string,
): { bedtime: number; wake: number; daylightSavingAdjusted?: boolean } {
  const day = new Date(`${date}T12:00:00`);
  const times = state.exceptions[date] ?? state.weekly[day.getDay()];
  const bed = new Date(day);
  bed.setHours(Math.floor(times.bedtime / 60), times.bedtime % 60, 0, 0);
  const wake = new Date(
    times.wake <= times.bedtime
      ? addCalendarDays(day.getTime(), 1)
      : day.getTime(),
  );
  wake.setHours(Math.floor(times.wake / 60), times.wake % 60, 0, 0);
  if (wake.getTime() <= bed.getTime()) {
    const durationMinutes = (times.wake - times.bedtime + 1440) % 1440;
    return {
      bedtime: bed.getTime(),
      wake: bed.getTime() + durationMinutes * 60000,
      daylightSavingAdjusted: true,
    };
  }
  return { bedtime: bed.getTime(), wake: wake.getTime() };
}
export function nextScheduledSleep(state: SleepRoutines, now: number) {
  const today = scheduledSleep(state, localDateKey(now));
  return today.bedtime > now
    ? today
    : scheduledSleep(state, localDateKey(addCalendarDays(now, 1)));
}
export function overlapPairs(sessions: readonly SleepSession[]) {
  const sorted = sessions
    .filter((s) => !s.id.startsWith('demo:') && s.end > s.start)
    .slice()
    .sort((a, b) => a.start - b.start);
  return sorted.flatMap((a, i) =>
    sorted
      .slice(i + 1)
      .filter((b) => b.start < a.end && b.end > a.start)
      .map((b) => [a, b] as const),
  );
}
export function sleepEpisodeIds(
  id: string,
  sessions: readonly SleepSession[],
  now: number,
) {
  const episode = buildSleepEpisodes(
    sessions.filter((s) => !s.id.startsWith('demo:')),
    now,
  ).find((e) => e.sessions.some((s) => s.id === id));
  return (
    episode?.sessions
      .slice()
      .sort((a, b) => a.start - b.start || a.id.localeCompare(b.id))
      .map((s) => s.id) ?? [id]
  );
}
export function sleepJournalKey(
  id: string,
  sessions: readonly SleepSession[],
  now: number,
  annotations: SleepRoutines['annotations'] = {},
) {
  const ids = sleepEpisodeIds(id, sessions, now);
  return ids.find((key) => annotations[key]) ?? ids[0];
}
export type SleepFilters = {
  query: string;
  source: string;
  type: string;
  from?: string;
  to?: string;
};
export function sleepHistory(
  sessions: readonly SleepSession[],
  filters: SleepFilters,
  annotations: SleepRoutines['annotations'],
  now: number,
) {
  return sessions
    .filter((s) => {
      const date = localDateKey(s.start);
      return (
        (!filters.query.trim() ||
          `${s.note ?? ''} ${annotations[sleepJournalKey(s.id, sessions, now, annotations)]?.note ?? annotations[s.id]?.note ?? ''}`
            .toLowerCase()
            .includes(filters.query.trim().toLowerCase())) &&
        (filters.source === 'all' ||
          sleepSourceLabel(s.id) === filters.source) &&
        (filters.type === 'all' || s.type === filters.type) &&
        (!filters.from || date >= filters.from) &&
        (!filters.to || date <= filters.to)
      );
    })
    .slice()
    .sort((a, b) => b.end - a.end);
}
export function sleepTrends(
  sessions: readonly SleepSession[],
  state: SleepRoutines,
  targetHours: number,
  now: number,
  days: number,
) {
  const personal = sessions.filter((s) => !s.id.startsWith('demo:'));
  const presentation = getSleepPresentation(
    personal,
    targetHours,
    days === 7 ? 'week' : 'month',
    now,
  );
  const episodes = buildSleepEpisodes(personal, now).filter(
    (e) => e.type === 'sleep',
  );
  return getLocalCalendarDayStarts(now, days).map((date) => {
    const key = localDateKey(date),
      point = presentation.points.find((p) => localDateKey(p.date) === key);
    const episode = episodes
      .filter((e) => localDateKey(e.wakeTime) === key)
      .sort((a, b) => b.durationMs - a.durationMs)[0];
    const candidates = episode
      ? [-1, 0, 1].map((offset) =>
          scheduledSleep(
            state,
            localDateKey(addCalendarDays(episode.sleepStart, offset)),
          ),
        )
      : [];
    const planned = candidates.sort(
      (a, b) =>
        Math.abs(a.bedtime - episode.sleepStart) -
        Math.abs(b.bedtime - episode.sleepStart),
    )[0];
    const durationMs = point?.durationMs ?? null;
    return {
      date,
      durationMs,
      deficitMs:
        durationMs === null
          ? null
          : Math.max(0, targetHours * 3600000 - durationMs),
      bedtimeVariationMin: planned
        ? Math.round((episode.sleepStart - planned.bedtime) / 60000)
        : null,
      wakeVariationMin: planned
        ? Math.round((episode.wakeTime - planned.wake) / 60000)
        : null,
    };
  });
}
