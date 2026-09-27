import type { Dose } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';
import { isSampleId } from '~/features/signals/model';

// Exports carry only what was recorded. A day with no entries is written with
// a blank mg and a "no record" status, never as 0 mg, and every row names its
// data source so Sample Data is never mistaken for the user's own entries.

export type DailyTotal = {
  date: string;
  // null: nothing was recorded that day.
  mg: number | null;
  entries: number;
  source?: string;
};

export function formatLocalDate(timestamp: number): string {
  const date = new Date(timestamp);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

function csvCell(value: string | number): string {
  return `"${String(value).replace(/"/g, '""')}"`;
}

function dataSource(ids: readonly string[]) {
  const sample = ids.filter(isSampleId).length;
  if (sample === 0) return 'Manual';
  return sample === ids.length ? 'Sample Data' : 'Manual and Sample Data';
}

export function makeDailyTotalsCSV(rows: readonly DailyTotal[]): string {
  const header = 'date,mg,entries,status,data_source';
  const lines = rows.map((row) =>
    (row.mg === null
      ? [row.date, '', 0, 'no record', '']
      : [row.date, row.mg, row.entries, 'recorded', row.source ?? '']
    )
      .map(csvCell)
      .join(','),
  );
  return [header, ...lines].join('\n');
}

// One row per local calendar day from the first recorded day through today.
export function getDailyTotalRows(doses: readonly Dose[], now: number): DailyTotal[] {
  const recorded = doses.filter(
    (dose) => Number.isFinite(dose.timestamp) && Number.isFinite(dose.mg) && dose.timestamp <= now,
  );
  if (recorded.length === 0) return [];
  const byDay = new Map<string, Dose[]>();
  for (const dose of recorded) {
    const key = formatLocalDate(dose.timestamp);
    byDay.set(key, [...(byDay.get(key) ?? []), dose]);
  }
  const first = new Date(Math.min(...recorded.map((dose) => dose.timestamp)));
  first.setHours(0, 0, 0, 0);
  const last = new Date(now);
  last.setHours(0, 0, 0, 0);
  const rows: DailyTotal[] = [];
  // Step by calendar date, not 24 hours, so DST days are neither skipped nor doubled.
  for (const day = first; day.getTime() <= last.getTime(); day.setDate(day.getDate() + 1)) {
    const date = formatLocalDate(day.getTime());
    const dayDoses = byDay.get(date);
    rows.push(
      dayDoses
        ? {
            date,
            mg: Math.round(dayDoses.reduce((sum, dose) => sum + dose.mg, 0)),
            entries: dayDoses.length,
            source: dataSource(dayDoses.map((dose) => dose.id)),
          }
        : { date, mg: null, entries: 0 },
    );
  }
  return rows;
}

export function makeDoseEntriesCSV(doses: readonly Dose[]): string {
  const header = 'id,local_date,timestamp,datetime,mg,drink,note,data_source';
  const lines = [...doses]
    .filter((dose) => Number.isFinite(dose.timestamp) && Number.isFinite(dose.mg))
    .sort((a, b) => a.timestamp - b.timestamp)
    .map((dose) =>
      [
        dose.id,
        formatLocalDate(dose.timestamp),
        dose.timestamp,
        new Date(dose.timestamp).toISOString(),
        dose.mg,
        dose.source ?? '',
        dose.note ?? '',
        dataSource([dose.id]),
      ]
        .map(csvCell)
        .join(','),
    );
  return [header, ...lines].join('\n');
}

export function makeVigilanceSessionsCSV(rows: readonly VigilanceSession[]): string {
  const header = [
    'id',
    'started_at',
    'completed_at',
    'duration_ms',
    'trial_count',
    'valid_reaction_count',
    'false_start_count',
    'lapse_count',
    'median_reaction_ms',
    'mean_reaction_ms',
    'fastest_reaction_ms',
    'reaction_std_dev_ms',
    'score',
    'rating',
    'data_source',
  ].join(',');
  const lines = rows.map((row) =>
    [
      row.id,
      new Date(row.startedAt).toISOString(),
      new Date(row.completedAt).toISOString(),
      row.durationMs,
      row.trialCount,
      row.validReactionCount,
      row.falseStartCount,
      row.lapseCount,
      row.medianReactionMs ?? '',
      row.meanReactionMs ?? '',
      row.fastestReactionMs ?? '',
      row.reactionStdDevMs ?? '',
      row.score,
      row.rating,
      isSampleId(row.id) ? 'Sample Data' : 'Recorded',
    ]
      .map(csvCell)
      .join(',')
  );
  return [header, ...lines].join('\n');
}

export default {
  formatLocalDate,
  getDailyTotalRows,
  makeDailyTotalsCSV,
  makeDoseEntriesCSV,
  makeVigilanceSessionsCSV,
};
