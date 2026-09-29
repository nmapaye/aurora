import type { Dose } from '~/domain/models';
import { isSampleId } from '~/features/signals/model';
import { caffeineLoggedSignal } from '~/features/summary/signals';
import { formatClockTime } from '~/features/summary/presentation';

// Log states what was recorded and where it came from. It never frames the
// day's total against a limit, allowance, or "remaining" amount, and it never
// suggests how much caffeine to have.

export const RECENT_DOSE_LIMIT = 5;
// A second quick-add tap this soon after the last one is treated as an
// accidental double tap rather than a second drink.
export const QUICK_ADD_REPEAT_GUARD_MS = 1000;

export type DoseSourceLabel = 'Manual' | 'Sample Data';

export function doseSourceLabel(dose: Pick<Dose, 'id'>): DoseSourceLabel {
  return isSampleId(dose.id) ? 'Sample Data' : 'Manual';
}

// Sample Data is labeled and read-only, as on Sleep. Only entries the user
// recorded can be corrected or deleted from Log.
export function isEditableDose(dose: Pick<Dose, 'id'>) {
  return !isSampleId(dose.id);
}

// Bundled sample entries all carry the stored note "Sample data", which only
// repeats their source label. Display skips that note; the record keeps it.
// Any other note, including on a sample entry, is shown as written.
const SAMPLE_NOTE = 'sample data';

export function displayDoseNote(dose: Pick<Dose, 'id' | 'note'>): string | undefined {
  const note = dose.note?.trim();
  if (!note) return undefined;
  if (isSampleId(dose.id) && note.toLowerCase() === SAMPLE_NOTE) return undefined;
  return dose.note;
}

/** Full local date and time, e.g. "Sun, Sep 27, 2026, 9:41 AM". */
export function formatDoseDateTime(timestamp: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      weekday: 'short',
      month: 'short',
      day: 'numeric',
      year: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(timestamp));
  } catch {
    return new Date(timestamp).toLocaleString();
  }
}

export function formatDoseTitle(dose: Pick<Dose, 'mg' | 'source'>) {
  return dose.source ? `${dose.mg} mg · ${dose.source}` : `${dose.mg} mg`;
}

export function describeDose(
  dose: Dose,
  formatDateTime: (ts: number) => string = formatDoseDateTime,
) {
  const note = displayDoseNote(dose);
  return [
    `${dose.mg} mg`,
    dose.source,
    formatDateTime(dose.timestamp),
    isEditableDose(dose) ? 'Manual' : 'Sample Data, read-only',
    note ? `Note: ${note}` : undefined,
  ]
    .filter(Boolean)
    .join(', ');
}

export function getRecentDoses(
  doses: readonly Dose[],
  limit = RECENT_DOSE_LIMIT,
) {
  return [...doses].sort((a, b) => b.timestamp - a.timestamp).slice(0, limit);
}

export type LoggedTodaySummary = {
  label: string;
  value: string;
  // Omitted when nothing is logged today.
  source?: string;
  sample: boolean;
  detail: string;
  accessibilityLabel: string;
};

// The same total and source wording as Summary's Caffeine Logged signal, so
// the two screens never disagree about today.
export function getLoggedTodaySummary(
  doses: readonly Dose[],
  now: number,
  formatTime: (ts: number) => string = formatClockTime,
): LoggedTodaySummary {
  const signal = caffeineLoggedSignal(doses, now, formatTime);
  const label = 'Logged Today';
  if (signal.status === 'empty') {
    const detail = 'Nothing logged yet today.';
    return {
      label,
      value: '0 mg',
      sample: false,
      detail,
      accessibilityLabel: `${label}, 0 mg, ${detail}`,
    };
  }
  const value = signal.value ?? '0 mg';
  return {
    label,
    value,
    source: signal.source,
    sample: signal.source !== 'Manual',
    detail: signal.context,
    accessibilityLabel: [label, value, signal.source, signal.context].join(', '),
  };
}

export function acceptsQuickAdd(lastAcceptedAt: number | undefined, at: number) {
  return (
    lastAcceptedAt === undefined ||
    at < lastAcceptedAt ||
    at - lastAcceptedAt >= QUICK_ADD_REPEAT_GUARD_MS
  );
}

export function quickAddConfirmation(
  dose: Pick<Dose, 'mg' | 'source' | 'timestamp'>,
  formatTime: (ts: number) => string = formatClockTime,
) {
  const what = dose.source ? `${dose.source}, ${dose.mg} mg` : `${dose.mg} mg`;
  return `Logged ${what} at ${formatTime(dose.timestamp)}.`;
}
