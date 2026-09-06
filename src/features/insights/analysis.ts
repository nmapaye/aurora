import { alertnessScore, mgActive } from '~/domain/algorithm';
import type { Dose, SleepSession, UserPrefs } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import type { CheckIn } from '~/features/planning/model';
import { isPersonal } from '~/features/planning/model';
import { buildSleepEpisodes } from '~/features/sleep/presentation';
import {
  addCalendarDays,
  isLocalDateKey,
  localDateKey,
  startOfLocalDay,
} from '~/utils/calendar';

export type InsightInput = {
  doses: Dose[];
  zeroDays: string[];
  sleeps: SleepSession[];
  checkIns: CheckIn[];
  tests: VigilanceSession[];
  prefs: UserPrefs & { dailyLimitMg?: number };
  now: number;
};
const HOUR = 3600000;
const validTime = (t: number) =>
  Number.isFinite(t) && Number.isFinite(new Date(t).getTime());
const mean = (values: number[]) =>
  values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
const median = (values: number[]) => {
  if (!values.length) return null;
  const s = [...values].sort((a, b) => a - b),
    m = Math.floor(s.length / 2);
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
};
function personalDoses(input: InsightInput) {
  return input.doses.filter(
    (d) =>
      isPersonal(d) &&
      validTime(d.timestamp) &&
      d.timestamp <= input.now &&
      Number.isFinite(d.mg) &&
      d.mg >= 0,
  );
}
function personalSleep(input: InsightInput) {
  return input.sleeps.filter(
    (s) =>
      isPersonal(s) &&
      validTime(s.start) &&
      validTime(s.end) &&
      s.start < s.end &&
      s.end <= input.now,
  );
}
export function completedTests(tests: VigilanceSession[], now: number) {
  return tests
    .filter(
      (t) =>
        isPersonal(t) &&
        validTime(t.startedAt) &&
        validTime(t.completedAt) &&
        t.completedAt > t.startedAt &&
        t.completedAt <= now &&
        Number.isFinite(t.durationMs) &&
        t.durationMs > 0,
    )
    .sort((a, b) => b.completedAt - a.completedAt || a.id.localeCompare(b.id));
}
function eligible(t: VigilanceSession) {
  return (
    t.validReactionCount > 0 &&
    t.medianReactionMs !== null &&
    Number.isFinite(t.medianReactionMs) &&
    t.medianReactionMs > 0
  );
}
function personalCheckIns(input: InsightInput) {
  return input.checkIns.filter(
    (c) =>
      isPersonal(c) &&
      validTime(c.timestamp) &&
      c.timestamp <= input.now &&
      Number.isInteger(c.rating) &&
      c.rating >= 1 &&
      c.rating <= 5,
  );
}
function dateStart(date: string) {
  const [y, m, d] = date.split('-').map(Number),
    value = new Date(0);
  value.setFullYear(y, m - 1, d);
  value.setHours(0, 0, 0, 0);
  return value.getTime();
}
function rangeStart(input: InsightInput, days: number) {
  return addCalendarDays(
    startOfLocalDay(input.now),
    1 - Math.max(1, Math.min(366, Math.trunc(days))),
  );
}
export type DayCompleteness = {
  date: string;
  caffeineMg: number | null;
  caffeineState: 'recorded' | 'zero' | 'missing';
  sleepHours: number | null;
  testCount: number;
  checkInCount: number;
};
export function completeness(
  input: InsightInput,
  days: number,
): DayCompleteness[] {
  const doses = personalDoses(input),
    episodes = buildSleepEpisodes(personalSleep(input), input.now),
    tests = completedTests(input.tests, input.now),
    checkIns = personalCheckIns(input);
  const result: DayCompleteness[] = [];
  for (
    let t = rangeStart(input, days);
    t <= input.now;
    t = addCalendarDays(t, 1)
  ) {
    const date = localDateKey(t),
      entries = doses.filter((d) => localDateKey(d.timestamp) === date),
      sleep = episodes.filter((e) => localDateKey(e.wakeTime) === date);
    const caffeineState = entries.length
      ? 'recorded'
      : input.zeroDays.includes(date)
        ? 'zero'
        : 'missing';
    result.push({
      date,
      caffeineState,
      caffeineMg:
        caffeineState === 'missing'
          ? null
          : entries.reduce((a, d) => a + d.mg, 0),
      sleepHours: sleep.length
        ? sleep.reduce((a, e) => a + e.durationMs, 0) / HOUR
        : null,
      testCount: tests.filter((s) => localDateKey(s.completedAt) === date)
        .length,
      checkInCount: checkIns.filter((c) => localDateKey(c.timestamp) === date)
        .length,
    });
  }
  return result;
}
export function weekdayPatterns(input: InsightInput, days: number) {
  const daily = completeness(input, days);
  return Array.from({ length: 7 }, (_, weekday) => {
    const group = daily.filter(
        (d) => new Date(dateStart(d.date)).getDay() === weekday,
      ),
      caffeine = group.flatMap((d) =>
        d.caffeineMg === null ? [] : [d.caffeineMg],
      ),
      sleep = group.flatMap((d) =>
        d.sleepHours === null ? [] : [d.sleepHours],
      );
    return {
      weekday,
      caffeineCount: caffeine.length,
      caffeineMean: mean(caffeine),
      sleepCount: sleep.length,
      sleepMean: mean(sleep),
    };
  });
}
export function vigilanceComparison(
  selected: VigilanceSession,
  tests: VigilanceSession[],
  now: number,
) {
  const prior = completedTests(tests, now).filter(
    (t) =>
      t.id !== selected.id &&
      t.completedAt < selected.completedAt &&
      eligible(t),
  );
  const medianMs =
    prior.length >= 3 &&
    completedTests([selected], now).length &&
    eligible(selected)
      ? median(prior.map((t) => t.medianReactionMs!))
      : null;
  return {
    count: prior.length,
    medianMs,
    changeMs: medianMs === null ? null : selected.medianReactionMs! - medianMs,
  };
}
export function checkInPairs(input: InsightInput, days: number) {
  const start = rangeStart(input, days),
    tests = completedTests(input.tests, input.now);
  const pairs = personalCheckIns(input)
    .filter((c) => c.timestamp >= start)
    .sort((a, b) => b.timestamp - a.timestamp || a.id.localeCompare(b.id))
    .flatMap((checkIn) => {
      const test = tests
        .filter((t) => Math.abs(t.completedAt - checkIn.timestamp) <= HOUR / 2)
        .sort(
          (a, b) =>
            Math.abs(a.completedAt - checkIn.timestamp) -
              Math.abs(b.completedAt - checkIn.timestamp) ||
            a.completedAt - b.completedAt ||
            a.id.localeCompare(b.id),
        )[0];
      return test ? [{ checkIn, test }] : [];
    });
  const usable = pairs.filter((p) => eligible(p.test));
  return {
    pairs,
    summary:
      usable.length >= 5
        ? {
            count: usable.length,
            meanRating: mean(usable.map((p) => p.checkIn.rating))!,
            medianReactionMs: median(
              usable.map((p) => p.test.medianReactionMs!),
            )!,
          }
        : null,
  };
}
export function bedtimePairs(input: InsightInput, days: number) {
  const doses = personalDoses(input),
    start = rangeStart(input, days);
  const points = buildSleepEpisodes(personalSleep(input), input.now)
    .filter((e) => e.type === 'sleep' && e.wakeTime >= start)
    .flatMap((e) => {
      // A logged preceding dose or explicit onset-day zero provides an observation.
      // Empty history alone cannot support a zero-caffeine point.
      const observed =
        doses.some(
          (d) =>
            d.timestamp <= e.sleepStart &&
            d.timestamp >= e.sleepStart - 24 * HOUR,
        ) || input.zeroDays.includes(localDateKey(e.sleepStart));
      return observed
        ? [
            {
              sleepStart: e.sleepStart,
              wakeTime: e.wakeTime,
              caffeineMg: mgActive(e.sleepStart, doses, input.prefs.halfLife),
              sleepHours: e.durationMs / HOUR,
            },
          ]
        : [];
    })
    .sort((a, b) => a.sleepStart - b.sleepStart);
  return {
    points,
    summary:
      points.length >= 5
        ? {
            count: points.length,
            meanCaffeineMg: mean(points.map((p) => p.caffeineMg))!,
            meanSleepHours: mean(points.map((p) => p.sleepHours))!,
          }
        : null,
  };
}
export type TimelineEvent = {
  id: string;
  kind: 'caffeine' | 'sleep' | 'nap' | 'check-in' | 'vigilance';
  timestamp: number;
  end?: number;
  label: string;
  detail: string;
};
export function dailyTimeline(
  input: InsightInput,
  date: string,
): TimelineEvent[] {
  if (!isLocalDateKey(date)) return [];
  const start = dateStart(date),
    end = addCalendarDays(start, 1),
    inside = (t: number) => t >= start && t < end;
  return [
    ...personalDoses(input)
      .filter((d) => inside(d.timestamp))
      .map((d) => ({
        id: d.id,
        kind: 'caffeine' as const,
        timestamp: d.timestamp,
        label: d.source || 'Caffeine',
        detail: `${d.mg} mg${d.note ? `. ${d.note}` : ''}`,
      })),
    ...buildSleepEpisodes(personalSleep(input), input.now)
      .filter((e) => e.sleepStart < end && e.wakeTime > start)
      .map((e) => ({
        id: `${e.type}:${e.sleepStart}:${e.wakeTime}`,
        kind: e.type,
        timestamp: e.sleepStart,
        end: e.wakeTime,
        label: e.type === 'nap' ? 'Nap' : 'Main sleep',
        detail: `${(e.durationMs / HOUR).toFixed(1)} h recorded; ${e.sessions.length} segment${e.sessions.length === 1 ? '' : 's'}, overlapping time counted once`,
      })),
    ...personalCheckIns(input)
      .filter((c) => inside(c.timestamp))
      .map((c) => ({
        id: c.id,
        kind: 'check-in' as const,
        timestamp: c.timestamp,
        label: 'Subjective alertness',
        detail: `${c.rating} of 5${c.note ? `. ${c.note}` : ''}`,
      })),
    ...completedTests(input.tests, input.now)
      .filter((t) => inside(t.completedAt))
      .map((t) => ({
        id: t.id,
        kind: 'vigilance' as const,
        timestamp: t.completedAt,
        label: 'Vigilance test',
        detail: `Median ${t.medianReactionMs === null ? 'unavailable' : `${t.medianReactionMs} ms`}; ${t.lapseCount} lapses; ${t.falseStartCount} false starts`,
      })),
  ].sort((a, b) => a.timestamp - b.timestamp || a.id.localeCompare(b.id));
}
export function inspectTime(input: InsightInput, timestamp: number) {
  const doses = personalDoses(input).filter((d) => d.timestamp <= timestamp),
    sleeps = personalSleep(input).filter((s) => s.end <= timestamp);
  return {
    timestamp,
    caffeineMg: mgActive(timestamp, doses, input.prefs.halfLife),
    alertness: alertnessScore(timestamp, doses, sleeps, input.prefs),
    doseCount: doses.length,
    sleepCount: sleeps.length,
    hasCaffeineRecord:
      doses.some(
        (d) => localDateKey(d.timestamp) === localDateKey(timestamp),
      ) || input.zeroDays.includes(localDateKey(timestamp)),
    hasSleepRecord: sleeps.some((s) => s.end > timestamp - 24 * HOUR),
  };
}
export function inspectionPoints(input: InsightInput, date: string) {
  if (!isLocalDateKey(date)) return [];
  const start = dateStart(date),
    end = addCalendarDays(start, 1),
    times = new Set<number>([start, end - 1]);
  for (let t = start; t < end; t += 15 * 60000) times.add(t);
  personalDoses(input)
    .filter((d) => d.timestamp >= start && d.timestamp < end)
    .forEach((d) => {
      times.add(d.timestamp);
      if (d.timestamp > start) times.add(d.timestamp - 1);
    });
  return [...times].sort((a, b) => a - b).map((t) => inspectTime(input, t));
}
export function weeklyReview(input: InsightInput) {
  const daily = completeness(input, 14),
    currentDays = daily.slice(-7),
    previousDays = daily.slice(0, -7),
    dailyCaffeineMg = input.prefs.dailyLimitMg ?? 400,
    sleepHours = input.prefs.targetSleep;
  function summarize(days: DayCompleteness[]) {
    const caffeine = days.flatMap((d) =>
        d.caffeineMg === null ? [] : [d.caffeineMg],
      ),
      sleep = days.flatMap((d) =>
        d.sleepHours === null ? [] : [d.sleepHours],
      );
    return {
      caffeineCount: caffeine.length,
      caffeineMeanMg: mean(caffeine),
      missingCaffeineDays: days.length - caffeine.length,
      caffeineWithinTarget: caffeine.filter((mg) => mg <= dailyCaffeineMg)
        .length,
      sleepCount: sleep.length,
      sleepMeanHours: mean(sleep),
      missingSleepDays: days.length - sleep.length,
      sleepAtTarget: sleep.filter((h) => h >= sleepHours).length,
      testCount: days.reduce((a, d) => a + d.testCount, 0),
      checkInCount: days.reduce((a, d) => a + d.checkInCount, 0),
    };
  }
  const current = summarize(currentDays),
    previous = summarize(previousDays);
  return {
    start: currentDays[0]?.date,
    end: currentDays[currentDays.length - 1]?.date,
    current,
    previous,
    targets: { dailyCaffeineMg, sleepHours },
    caffeineChangeMg:
      current.caffeineMeanMg === null || previous.caffeineMeanMg === null
        ? null
        : current.caffeineMeanMg - previous.caffeineMeanMg,
    sleepChangeHours:
      current.sleepMeanHours === null || previous.sleepMeanHours === null
        ? null
        : current.sleepMeanHours - previous.sleepMeanHours,
  };
}
