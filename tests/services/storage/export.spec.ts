import type { VigilanceSession } from '~/domain/vigilance';
import {
  makeDailyTotalsCSV,
  makeSummaryText,
  makeVigilanceSessionsCSV,
} from '~/services/storage/export';

describe('storage export helpers', () => {
  it('exports daily totals as escaped CSV rows', () => {
    const csv = makeDailyTotalsCSV([
      { date: '2026-04-25', mg: 95 },
      { date: '2026-04-26, late "boost"', mg: 12.5 },
    ]);

    expect(csv).toBe(
      [
        'date,mg',
        '"2026-04-25","95"',
        '"2026-04-26, late ""boost""","12.5"',
      ].join('\n')
    );
  });

  it('omits optional summary sections when they are not provided', () => {
    const summary = makeSummaryText({
      range: 'Apr 20-26, 2026',
      totalMg: 420,
      avgMg: 60,
    });

    expect(summary).toBe(
      [
        'AURORA Summary Apr 20-26, 2026',
        'Total: 420 mg',
        'Average: 60 mg/day',
      ].join('\n')
    );
  });

  it('includes optional summary sections when present', () => {
    const summary = makeSummaryText({
      range: 'Apr 20-26, 2026',
      totalMg: 420,
      avgMg: 60,
      adherencePct: 86,
      streakDays: 4,
      dayparts: [
        { label: 'Morning', mg: 300.4 },
        { label: 'Afternoon', mg: 119.5 },
      ],
      sources: [
        { label: 'Coffee', mg: 360, pct: 86 },
        { label: 'Tea', mg: 60, pct: 14 },
      ],
    });

    expect(summary).toBe(
      [
        'AURORA Summary Apr 20-26, 2026',
        'Total: 420 mg',
        'Average: 60 mg/day',
        'Adherence: 86% (streak 4d)',
        'Dayparts: Morning:300 mg, Afternoon:120 mg',
        'Sources: Coffee 360mg (86%), Tea 60mg (14%)',
      ].join('\n')
    );
  });

  it('exports vigilance sessions with escaped cells and blank null metrics', () => {
    const rows: VigilanceSession[] = [
      {
        id: 'session "alpha", one',
        startedAt: Date.UTC(2026, 3, 25, 15, 0, 0),
        completedAt: Date.UTC(2026, 3, 25, 15, 1, 0),
        durationMs: 60_000,
        trialCount: 12,
        validReactionCount: 0,
        falseStartCount: 2,
        lapseCount: 12,
        medianReactionMs: null,
        meanReactionMs: null,
        fastestReactionMs: null,
        reactionStdDevMs: null,
        score: 18,
        rating: 'Fatigued',
      },
    ];

    expect(makeVigilanceSessionsCSV(rows)).toBe(
      [
        [
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
        ].join(','),
        [
          '"session ""alpha"", one"',
          '"2026-04-25T15:00:00.000Z"',
          '"2026-04-25T15:01:00.000Z"',
          '"60000"',
          '"12"',
          '"0"',
          '"2"',
          '"12"',
          '""',
          '""',
          '""',
          '""',
          '"18"',
          '"Fatigued"',
        ].join(','),
      ].join('\n')
    );
  });
});
