import type { Dose } from '~/domain/models';
import type { CaffeinePreset } from './presets';

export type CustomDoseDraft = {
  editingId?: string;
  mg: string;
  source: string;
  timestamp: number;
  note: string;
};

export type DraftValidation =
  | { valid: true; message?: undefined }
  | { valid: false; message: string };

function startOfLocalDay(timestamp: number) {
  const date = new Date(timestamp);
  date.setHours(0, 0, 0, 0);
  return date.getTime();
}

export function getTodayCaffeineTotal(doses: readonly Dose[], now: number) {
  const start = startOfLocalDay(now);
  const end = new Date(start);
  end.setDate(end.getDate() + 1);
  return doses.reduce(
    (total, dose) =>
      dose.timestamp >= start && dose.timestamp < end.getTime()
        ? total + dose.mg
        : total,
    0,
  );
}

export function getRemainingDailyCaffeineLimit(
  doses: readonly Dose[],
  now: number,
  dailyLimitMg: number,
) {
  return Math.max(0, dailyLimitMg - getTodayCaffeineTotal(doses, now));
}

export function createCustomDoseDraft(now: number): CustomDoseDraft {
  return { mg: '80', source: 'Drip', timestamp: now, note: '' };
}

export function validateCustomDoseDraft(
  draft: CustomDoseDraft,
  now: number,
): DraftValidation {
  const mg = Number(draft.mg);
  if (!Number.isInteger(mg) || mg < 1 || mg > 1999) {
    return { valid: false, message: 'Amount must be between 1 and 1999 mg.' };
  }
  if (
    !Number.isFinite(draft.timestamp) ||
    !Number.isFinite(new Date(draft.timestamp).getTime()) ||
    draft.timestamp > now
  ) {
    return { valid: false, message: 'Time cannot be in the future.' };
  }
  return { valid: true };
}

export function buildQuickAddDose(
  preset: CaffeinePreset,
  now: number,
  createId: () => string,
): Dose {
  return {
    id: createId(),
    timestamp: now,
    mg: preset.mg,
    source: preset.label,
  };
}

export function buildCustomDose(
  draft: CustomDoseDraft,
  createId: () => string,
): Dose {
  return {
    id: createId(),
    timestamp: draft.timestamp,
    mg: Number(draft.mg),
    source: draft.source.trim() || undefined,
    note: draft.note.trim() || undefined,
  };
}
