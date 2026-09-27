import { alertnessScore } from '~/domain/algorithm/alertness';
import { totalSleepHoursLast24 } from '~/domain/algorithm/sleepDebt';
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
  | { status: 'estimated'; score: number; sleepHours: number }
  | { status: 'needs-sleep' };

export function estimateAlertness(
  t: number,
  doses: CaffeineDoseInput[],
  sleeps: SleepSessionInput[],
  prefs: Pick<UserPrefs, 'halfLife' | 'targetSleep' | 'tz'>,
): AlertnessEstimate {
  const sleepHours = totalSleepHoursLast24(t, sleeps);
  if (!(sleepHours > 0)) return { status: 'needs-sleep' };
  return {
    status: 'estimated',
    score: Math.round(alertnessScore(t, doses, sleeps, prefs)),
    sleepHours,
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
  )} of sleep in the last 24 hours, active caffeine, and time of day. This is an estimate, not a measurement.`;
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
