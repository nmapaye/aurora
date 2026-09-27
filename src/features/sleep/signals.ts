import type { Dose, SleepSession } from '~/domain/models';
import type { SignalCardModel } from '~/features/signals/model';
import {
  formatSleepDuration,
  getCaffeineImpact,
  getSleepPresentation,
  PAIRED_NIGHTS_REQUIRED,
  sleepSourceLabel,
} from '~/features/sleep/presentation';
import { formatClockTime } from '~/features/summary/presentation';

const HOUR_MS = 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

// Sleep describes recorded nights and, once enough nights exist, when caffeine
// was last logged before sleep. It never suggests a dose, a cutoff, or a
// bedtime, and it never claims caffeine changed a night's sleep.

// "40m", "2h", "7h 15m": compact gaps for context lines.
export function formatGap(durationMs: number) {
  const totalMinutes = Math.round(Math.abs(durationMs) / MINUTE_MS);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  if (hours === 0) return `${minutes}m`;
  return minutes === 0 ? `${hours}h` : `${hours}h ${minutes}m`;
}

export function describeTargetComparison(
  durationMs: number,
  targetSleepHours: number,
) {
  const target = formatGap(targetSleepHours * HOUR_MS);
  const differenceMs = durationMs - targetSleepHours * HOUR_MS;
  // Within a minute reads as on target rather than "0m under".
  if (Math.abs(differenceMs) < MINUTE_MS) return `On your ${target} target`;
  return `${formatGap(differenceMs)} ${differenceMs > 0 ? 'over' : 'under'} your ${target} target`;
}

// "Sun, Sep 21": the wake day, always absolute so an older night is never
// mistaken for last night.
export function formatSleepDate(ts: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toDateString();
  }
}

// "Today", "Yesterday", "6 days ago", counted in calendar days so DST
// transitions never shift the count.
export function describeSleepAge(ts: number, now: number) {
  const day = new Date(ts);
  day.setHours(0, 0, 0, 0);
  const today = new Date(now);
  today.setHours(0, 0, 0, 0);
  const days = Math.round((today.getTime() - day.getTime()) / (24 * HOUR_MS));
  if (days <= 0) return 'Today';
  if (days === 1) return 'Yesterday';
  return `${days} days ago`;
}

// The most recent night in the last seven days, using the same episode merge
// as the chart so fragmented Health samples read as one night. The context
// leads with the absolute wake date and the footer says how long ago it was,
// so a week-old sample night never reads as last night.
export function recentNightSignal(
  sleeps: readonly SleepSession[],
  targetSleepHours: number,
  now: number,
  formatTime: (ts: number) => string = formatClockTime,
  formatDate: (ts: number) => string = formatSleepDate,
): SignalCardModel {
  const { lastNight } = getSleepPresentation(
    sleeps,
    targetSleepHours,
    'week',
    now,
  );
  const base = { id: 'sleep-recent-night', label: 'Most Recent Sleep' };
  if (!lastNight) {
    return {
      ...base,
      status: 'empty',
      period: 'Last 7 days',
      context: 'No sleep recorded in the last 7 days.',
      destination: 'Add Sleep',
    };
  }
  const source = sleepSourceLabel(lastNight.session.id);
  const span = `${formatTime(lastNight.sleepStart)} – ${formatTime(lastNight.wakeTime)}`;
  return {
    ...base,
    status: source === 'Sample Data' ? 'sample' : 'observed',
    period: describeSleepAge(lastNight.wakeTime, now),
    source,
    value: formatSleepDuration(lastNight.durationMs),
    context: `${formatDate(lastNight.wakeTime)} · ${span} · ${describeTargetComparison(lastNight.durationMs, targetSleepHours)}`,
    destination: 'Show All Data',
  };
}

export type CaffeineTimingSignal =
  | {
      status: 'gathering';
      label: string;
      pairedNights: number;
      required: number;
      text: string;
    }
  | {
      status: 'observed';
      label: string;
      pairedNights: number;
      period: string;
      value: string;
      context: string;
      detailRows: readonly { title: string; value: string }[];
      accessibilityLabel: string;
    };

export const CAFFEINE_TIMING_LABEL = 'Caffeine timing before sleep';

// Always the last 30 days, independent of the W/M chart range: a 7-day window
// can never reach the 14-night gate.
export function caffeineTimingSignal(
  sleeps: readonly SleepSession[],
  doses: readonly Dose[],
  now: number,
): CaffeineTimingSignal {
  const timing = getCaffeineImpact(sleeps, doses, 'month', now);
  const pairedNights = timing.qualifyingNights;
  if (!timing.meetsPairedNightGate) {
    const text =
      pairedNights === 0
        ? `No nights yet with both sleep and caffeine logged in the 12 hours before it. A typical timing appears after ${PAIRED_NIGHTS_REQUIRED} such nights.`
        : `${pairedNights} of ${PAIRED_NIGHTS_REQUIRED} nights so far with both sleep and caffeine logged in the 12 hours before it. A typical timing appears at ${PAIRED_NIGHTS_REQUIRED}.`;
    return {
      status: 'gathering',
      label: CAFFEINE_TIMING_LABEL,
      pairedNights,
      required: PAIRED_NIGHTS_REQUIRED,
      text,
    };
  }
  const value = formatGap(timing.medianDeltaMin * MINUTE_MS);
  const context = `Median time from last logged caffeine to sleep · ${pairedNights} nights`;
  const range = `${formatGap(timing.p10 * MINUTE_MS)} – ${formatGap(timing.p90 * MINUTE_MS)}`;
  return {
    status: 'observed',
    label: CAFFEINE_TIMING_LABEL,
    pairedNights,
    period: 'Last 30 days',
    value,
    context,
    detailRows: [
      { title: 'Middle 80% of nights', value: range },
      { title: 'Nights with both logged', value: `${pairedNights}` },
    ],
    accessibilityLabel: `${CAFFEINE_TIMING_LABEL}, ${value}, Last 30 days, ${context}`,
  };
}
