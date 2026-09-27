import { alertnessScore } from '~/domain/algorithm/alertness';
import { totalSleepHoursLast24 } from '~/domain/algorithm/sleepDebt';
import { isSampleId } from '~/features/signals/model';
import type {
  CaffeineDoseInput,
  SleepSessionInput,
  UserPrefs,
} from '~/domain/models';

// Estimated Alertness is the existing alertness model, nothing more. The model
// reads sleep from the 24 hours before `t`; without any, its sleep-debt term
// saturates and the number would describe missing data rather than the person.
// In that case we return no score at all.
export type AlertnessEstimate =
  | {
      status: 'estimated';
      score: number;
      sleepHours: number;
      // True when sample sleep or doses feed this estimate.
      includesSample: boolean;
    }
  | { status: 'needs-sleep' };

const DAY_MS = 24 * 60 * 60 * 1000;

function hasSampleId(item: object) {
  const id = (item as { id?: unknown }).id;
  return typeof id === 'string' && isSampleId(id);
}

export function estimateAlertness(
  t: number,
  doses: CaffeineDoseInput[],
  sleeps: SleepSessionInput[],
  prefs: Pick<UserPrefs, 'halfLife' | 'targetSleep' | 'tz'>,
): AlertnessEstimate {
  const sleepHours = totalSleepHoursLast24(t, sleeps);
  if (!(sleepHours > 0)) return { status: 'needs-sleep' };
  const windowStart = t - DAY_MS;
  const includesSample =
    sleeps.some((sleep) => sleep.end > windowStart && sleep.start <= t && hasSampleId(sleep)) ||
    doses.some((dose) => dose.timestamp > windowStart && dose.timestamp <= t && hasSampleId(dose));
  return {
    status: 'estimated',
    score: Math.round(alertnessScore(t, doses, sleeps, prefs)),
    sleepHours,
    includesSample,
  };
}

export function formatClockTime(ts: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toLocaleTimeString();
  }
}

export function formatSleepHours(hours: number) {
  const totalMinutes = Math.round(hours * 60);
  const h = Math.floor(totalMinutes / 60);
  const m = totalMinutes % 60;
  return `${h}h ${m}m`;
}

export function describeAlertnessEstimate(estimate: AlertnessEstimate) {
  if (estimate.status === 'needs-sleep') {
    return 'Estimated alertness unavailable. No sleep is recorded in the last 24 hours.';
  }
  return `Estimated alertness ${estimate.score} out of 100. Modeled from ${formatSleepHours(
    estimate.sleepHours,
  )} of sleep in the last 24 hours, active caffeine, and time of day.${
    estimate.includesSample ? ' Includes Sample Data.' : ''
  } This is an estimate, not a measurement.`;
}

export type CutoffAnnotation = {
  // Today's cutoff, which is where the curve marks it.
  at: number;
  isPast: boolean;
  // The next cutoff to come: today's, or tomorrow's once today's has passed.
  nextAt: number;
  text: string;
};

// The user's own cutoff as context on today's curve, not a recommendation.
// Before the cutoff it is always worth marking. After it, it only matters if
// caffeine was logged today; otherwise there is nothing for it to annotate.
// Tomorrow's cutoff is built from the calendar day so DST shifts keep the
// same local hour.
export function getCutoffAnnotation({
  now,
  cutoffHour,
  doses,
  formatTime = formatClockTime,
}: {
  now: number;
  cutoffHour: number;
  doses: readonly CaffeineDoseInput[];
  formatTime?: (ts: number) => string;
}): CutoffAnnotation | null {
  if (!Number.isFinite(cutoffHour)) return null;
  const hour = Math.max(0, Math.min(23, Math.round(cutoffHour)));
  const today = new Date(now);
  today.setHours(hour, 0, 0, 0);
  const at = today.getTime();
  const isPast = now >= at;
  if (isPast) {
    const dayStart = new Date(now);
    dayStart.setHours(0, 0, 0, 0);
    const loggedToday = doses.some(
      (dose) => dose.timestamp >= dayStart.getTime() && dose.timestamp <= now,
    );
    if (!loggedToday) return null;
  }
  const next = new Date(now);
  if (isPast) next.setDate(next.getDate() + 1);
  next.setHours(hour, 0, 0, 0);
  const time = formatTime(at);
  return {
    at,
    isPast,
    nextAt: next.getTime(),
    text: isPast
      ? `Your cutoff was ${time}. Next: tomorrow, ${formatTime(next.getTime())}.`
      : `Your cutoff: ${time} today.`,
  };
}

// Index of the point whose x is closest to `x`. `xs` must be ascending.
export function nearestIndex(xs: readonly number[], x: number) {
  if (xs.length === 0) return -1;
  let lo = 0;
  let hi = xs.length - 1;
  while (hi - lo > 1) {
    const mid = (lo + hi) >> 1;
    if (xs[mid] <= x) lo = mid;
    else hi = mid;
  }
  return Math.abs(xs[hi] - x) < Math.abs(xs[lo] - x) ? hi : lo;
}

// Latest point at or before `now`, which is the default inspected point.
export function nowIndex(series: readonly { t: number }[], now: number) {
  let index = 0;
  series.forEach((point, i) => {
    if (point.t <= now) index = i;
  });
  return index;
}

export type CaffeineInspection = {
  t: number;
  isNow: boolean;
  isFuture: boolean;
  // Model: active caffeine from the half-life model.
  activeMg: number;
  // Measured: only doses the person actually logged today, up to `t`.
  loggedMg: number;
  loggedCount: number;
  alertness: AlertnessEstimate;
};

export function inspectCaffeinePoint({
  point,
  doses,
  sleeps,
  prefs,
  dayStart,
  now,
}: {
  point: { t: number; mg: number };
  doses: CaffeineDoseInput[];
  sleeps: SleepSessionInput[];
  prefs: Pick<UserPrefs, 'halfLife' | 'targetSleep' | 'tz'>;
  dayStart: number;
  now: number;
}): CaffeineInspection {
  const logged = doses.filter(
    (dose) =>
      dose.timestamp >= dayStart &&
      dose.timestamp <= point.t &&
      dose.timestamp <= now,
  );
  return {
    t: point.t,
    isNow: point.t === now,
    isFuture: point.t > now,
    activeMg: point.mg,
    loggedMg: logged.reduce((sum, dose) => sum + dose.mg, 0),
    loggedCount: logged.length,
    alertness: estimateAlertness(point.t, doses, sleeps, prefs),
  };
}

export function describeInspection(
  inspection: CaffeineInspection,
  formatTime: (ts: number) => string = formatClockTime,
) {
  const time = inspection.isNow
    ? `Now, ${formatTime(inspection.t)}`
    : formatTime(inspection.t);
  const active = `${inspection.isFuture ? 'projected' : 'modeled'} active caffeine ${Math.round(
    inspection.activeMg,
  )} milligrams`;
  const logged =
    inspection.loggedCount === 0
      ? 'no doses logged today by then'
      : `${Math.round(inspection.loggedMg)} milligrams logged today by then in ${
          inspection.loggedCount
        } ${inspection.loggedCount === 1 ? 'dose' : 'doses'}`;
  const alertness =
    inspection.alertness.status === 'estimated'
      ? `${inspection.isFuture ? 'projected' : 'estimated'} alertness ${inspection.alertness.score}`
      : 'alertness needs recent sleep';
  return `${time}: ${active}, ${logged}, ${alertness}.`;
}

// Whether today's curve has anything to show: a dose logged today, or modeled
// carryover that rounds to at least 1 mg somewhere in the day. Without either
// the chart would be a flat 0 mg line, so the hero shows a short note instead.
export function hasCaffeineSignal({
  series,
  doses,
  dayStart,
  dayEnd,
}: {
  series: readonly { mg: number }[];
  doses: readonly CaffeineDoseInput[];
  dayStart: number;
  dayEnd: number;
}) {
  return (
    doses.some((dose) => dose.timestamp >= dayStart && dose.timestamp < dayEnd) ||
    series.some((point) => Math.round(point.mg) >= 1)
  );
}

export const NO_CAFFEINE_NOTE = {
  title: 'No caffeine logged today',
  body: 'Today’s active-caffeine curve appears once you log a dose.',
};

export function describeNoCaffeineNote(cutoffText?: string) {
  const base = `Caffeine today. ${NO_CAFFEINE_NOTE.title}, and none is carried over from earlier. ${NO_CAFFEINE_NOTE.body}`;
  return cutoffText ? `${base} ${cutoffText}` : base;
}

export function describeCaffeineDay({
  series,
  doses,
  dayStart,
  dayEnd,
  formatTime = formatClockTime,
}: {
  series: readonly { t: number; mg: number }[];
  doses: CaffeineDoseInput[];
  dayStart: number;
  dayEnd: number;
  formatTime?: (ts: number) => string;
}) {
  const today = doses.filter(
    (dose) => dose.timestamp >= dayStart && dose.timestamp < dayEnd,
  );
  const logged =
    today.length === 0
      ? 'No caffeine logged today.'
      : `${today.length} ${today.length === 1 ? 'dose' : 'doses'} logged today, ${Math.round(
          today.reduce((sum, dose) => sum + dose.mg, 0),
        )} milligrams total.`;
  const peak = series.reduce<{ t: number; mg: number } | null>(
    (best, point) => (!best || point.mg > best.mg ? point : best),
    null,
  );
  const shape =
    !peak || Math.round(peak.mg) === 0
      ? 'Modeled active caffeine stays at 0 milligrams.'
      : `Modeled active caffeine peaks at ${Math.round(peak.mg)} milligrams at ${formatTime(
          peak.t,
        )}.`;
  return `Active caffeine today chart. ${logged} ${shape}`;
}
