export type DailyTotal = { date: string; mg: number };

export function makeDailyTotalsCSV(rows: DailyTotal[]): string {
  const header = 'date,mg';
  const lines = rows.map((r) => `${r.date},${r.mg}`);
  return [header, ...lines].join('\n');
}

export function makeSummaryText(params: {
  range: string;
  totalMg: number;
  avgMg: number;
  adherencePct?: number;
  streakDays?: number;
  dayparts?: { label: string; mg: number }[];
  sources?: { label: string; mg: number; pct: number }[];
}): string {
  const parts: string[] = [];
  parts.push(`AURORA Summary ${params.range}`);
  parts.push(`Total: ${params.totalMg} mg`);
  parts.push(`Average: ${params.avgMg} mg/day`);
  if (typeof params.adherencePct === 'number') {
    parts.push(`Adherence: ${params.adherencePct}%${params.streakDays ? ` (streak ${params.streakDays}d)` : ''}`);
  }
  if (params.dayparts && params.dayparts.length) {
    parts.push(
      `Dayparts: ${params.dayparts.map((d) => `${d.label}:${Math.round(d.mg)} mg`).join(', ')}`
    );
  }
  if (params.sources && params.sources.length) {
    parts.push(
      `Sources: ${params.sources.map((s) => `${s.label} ${s.mg}mg (${s.pct}%)`).join(', ')}`
    );
  }
  return parts.join('\n');
}

export default { makeDailyTotalsCSV, makeSummaryText };
