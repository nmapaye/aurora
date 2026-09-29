import type { Dose, SleepSession } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import {
  formatSignalDay,
  isSampleId,
  type SignalCardModel,
} from '~/features/signals/model';
import {
  formatSleepDuration,
  getSleepPresentation,
  sleepSourceLabel,
} from '~/features/sleep/presentation';
import { formatClockTime } from '~/features/summary/presentation';

// Summary pins three recorded signals: caffeine logged today, the latest
// night of sleep, and the latest Reaction Test. Active caffeine and the
// cutoff live on the caffeine curve instead of repeating here.

function startOfDay(now: number) {
  const day = new Date(now);
  day.setHours(0, 0, 0, 0);
  return day.getTime();
}

// The Caffeine Logged signal is Summary's one route into Log, empty or not.
// Log itself holds recent entries and history, so only the wording changes:
// an empty day offers logging, a logged day opens Log.
export function caffeineLoggedSignal(
  doses: readonly Dose[],
  now: number,
  formatTime: (ts: number) => string = formatClockTime,
): SignalCardModel {
  const dayStart = startOfDay(now);
  const today = doses.filter(
    (dose) => dose.timestamp >= dayStart && dose.timestamp <= now,
  );
  const base = {
    id: 'caffeine',
    label: 'Caffeine Logged',
    period: 'Today',
    destination: 'Open Log',
  };
  if (today.length === 0) {
    return {
      ...base,
      status: 'empty',
      destination: 'Log Caffeine',
      context: 'Nothing logged yet today.',
    };
  }
  const total = Math.round(today.reduce((sum, dose) => sum + dose.mg, 0));
  const last = today.reduce((latest, dose) =>
    dose.timestamp > latest.timestamp ? dose : latest,
  );
  const sampleCount = today.filter((dose) => isSampleId(dose.id)).length;
  const allSample = sampleCount === today.length;
  return {
    ...base,
    status: allSample ? 'sample' : 'observed',
    source: allSample
      ? 'Sample Data'
      : sampleCount > 0
        ? 'Manual and Sample Data'
        : 'Manual',
    value: `${total} mg`,
    context: `${today.length} ${today.length === 1 ? 'entry' : 'entries'} · last at ${formatTime(last.timestamp)}`,
  };
}

export function sleepSignal(
  sleeps: readonly SleepSession[],
  targetSleepHours: number,
  now: number,
  formatTime: (ts: number) => string = formatClockTime,
): SignalCardModel {
  // Reuse Sleep's own episode logic so fragmented Health samples read as one
  // night, and so sleep older than a week is not shown as if it were current.
  const { lastNight } = getSleepPresentation(
    sleeps,
    targetSleepHours,
    'week',
    now,
  );
  const base = {
    id: 'sleep',
    label: 'Sleep',
    destination: 'Open Sleep',
  };
  if (!lastNight) {
    return {
      ...base,
      status: 'empty',
      period: 'Last 7 days',
      destination: 'Add Sleep',
      context: 'None recorded in the last 7 days.',
    };
  }
  const source = sleepSourceLabel(lastNight.session.id);
  const period = formatSignalDay(lastNight.wakeTime, now);
  const span = `${formatTime(lastNight.sleepStart)} – ${formatTime(lastNight.wakeTime)}`;
  return {
    ...base,
    status: source === 'Sample Data' ? 'sample' : 'observed',
    period,
    source,
    value: formatSleepDuration(lastNight.durationMs),
    context:
      period === 'Today' || period === 'Yesterday'
        ? span
        : `Latest night recorded · ${span}`,
  };
}

export function reactionTestSignal(
  sessions: readonly VigilanceSession[],
  now: number,
): SignalCardModel {
  const latest = sessions.reduce<VigilanceSession | undefined>(
    (best, session) =>
      session.completedAt <= now &&
      (!best || session.completedAt > best.completedAt)
        ? session
        : best,
    undefined,
  );
  const base = {
    id: 'reaction-test',
    label: 'Reaction Test',
    destination: 'Take Reaction Test',
  };
  if (!latest) {
    return {
      ...base,
      status: 'empty',
      period: 'No test yet',
      context: 'A 60-second test of reaction speed.',
    };
  }
  const sample = isSampleId(latest.id);
  return {
    ...base,
    status: sample ? 'sample' : 'observed',
    period: formatSignalDay(latest.completedAt, now),
    source: sample ? 'Sample Data' : undefined,
    value: `${latest.score}`,
    context:
      latest.medianReactionMs !== null
        ? `${latest.rating} · ${Math.round(latest.medianReactionMs)} ms median`
        : latest.rating,
  };
}
