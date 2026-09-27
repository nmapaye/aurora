import {
  BRIEF_AWAKENING_MS,
  mergeSleepIntervals,
} from '~/domain/algorithm/sleepIntervals';
import AppleHealth, {
  makeHealthSleepSessionId,
} from '~/services/platform/health/appleHealth';
import { useStore } from '~/state/store';

const DAY_MS = 24 * 60 * 60 * 1000;

export const NO_HEALTH_SLEEP_MESSAGE =
  'No recent sleep found in Health. Check that Aurora can read Sleep in the Health app, or add sleep manually.';

export type HealthSleepImportResult =
  | { ok: true; nights: number }
  | { ok: false; error: string };

/** Counts nights rather than raw samples: one Watch night can be dozens of stage segments. */
export function countSleepNights(samples: readonly { start: number; end: number }[]) {
  return mergeSleepIntervals(samples, BRIEF_AWAKENING_MS).length;
}

export function describeImportedNights(nights: number) {
  return nights > 0
    ? `Imported ${nights} ${nights === 1 ? 'night' : 'nights'} of sleep from Health.`
    : NO_HEALTH_SLEEP_MESSAGE;
}

/**
 * Reads the last `days` of sleep from Health and replaces Aurora's copy of that
 * window, so edits and deletions made in Health carry over.
 */
export async function importHealthSleep({
  days,
  now = Date.now(),
  failurePrefix = 'Health refresh failed.',
}: {
  days: number;
  now?: number;
  failurePrefix?: string;
}): Promise<HealthSleepImportResult> {
  const { setHealthSync, replaceHealthSleepWindow } = useStore.getState();
  setHealthSync({
    importStatus: 'importing',
    lastMessage: 'Importing recent sleep from Health.',
  });
  const windowStart = now - days * DAY_MS;
  try {
    const samples = await AppleHealth.getSleepSamples(windowStart, now);
    if (!Array.isArray(samples)) {
      throw new Error('Health sleep query returned an invalid payload.');
    }
    replaceHealthSleepWindow(
      samples.map((sample) => ({
        id: makeHealthSleepSessionId(sample),
        start: sample.start,
        end: sample.end,
        type: 'sleep' as const,
      })),
      windowStart,
      now,
    );
    const nights = countSleepNights(samples);
    setHealthSync({
      importedCount: nights,
      importStatus: 'succeeded',
      lastSyncedAt: Date.now(),
      lastMessage: describeImportedNights(nights),
    });
    return { ok: true, nights };
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Unable to read sleep data.';
    setHealthSync({
      importStatus: 'failed',
      lastSyncedAt: Date.now(),
      lastMessage: `${failurePrefix} ${message}`,
    });
    return { ok: false, error: message };
  }
}
