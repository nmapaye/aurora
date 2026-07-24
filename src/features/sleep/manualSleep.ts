import type { SleepSession } from '~/domain/models';

const HOUR_MS = 60 * 60 * 1000;
const MANUAL_SLEEP_PREFIX = 'manual:sleep:';

export type ManualSleepDraft = Pick<SleepSession, 'start' | 'end'> & { note: string };

export function createManualSleepDraft(now = Date.now()): ManualSleepDraft {
  return { start: now - 8 * HOUR_MS, end: now, note: '' };
}

export function createManualSleepId(now = Date.now(), entropy = Math.random().toString(36).slice(2)) {
  return `${MANUAL_SLEEP_PREFIX}${now}:${entropy}`;
}

export function isManualSleep(id: string) {
  return id.startsWith(MANUAL_SLEEP_PREFIX);
}

export function validateManualSleep(
  draft: Pick<ManualSleepDraft, 'start' | 'end'> & Partial<Pick<ManualSleepDraft, 'note'>>,
  now = Date.now(),
): { valid: true } | { valid: false; message: string } {
  if (!Number.isFinite(draft.start) || !Number.isFinite(draft.end) || draft.start >= draft.end) {
    return { valid: false, message: 'Start time must be before end time.' };
  }
  if (draft.end - draft.start > 24 * HOUR_MS) {
    return { valid: false, message: 'Sleep duration cannot exceed 24 hours.' };
  }
  if (draft.end > now) {
    return { valid: false, message: 'End time cannot be in the future.' };
  }
  return { valid: true };
}
