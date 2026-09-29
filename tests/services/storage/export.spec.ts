import type { VigilanceSession } from '~/domain/vigilance';
import {
  formatLocalDate,
  getDailyTotalRows,
  makeDailyTotalsCSV,
  makeDoseEntriesCSV,
  makeVigilanceSessionsCSV,
} from '~/services/storage/export';

describe('storage export helpers', () => {
  it('formats a timestamp from local calendar components', () => {
    const localMidnight = new Date(2026, 6, 24, 0, 0, 0, 0).getTime();

    expect(formatLocalDate(localMidnight)).toBe('2026-07-24');
  });

  it('keeps local dates stable across DST transition days', () => {
    expect(formatLocalDate(new Date(2026, 2, 8, 0, 0, 0, 0).getTime())).toBe(
      '2026-03-08',
    );
    expect(formatLocalDate(new Date(2026, 10, 1, 0, 0, 0, 0).getTime())).toBe(
      '2026-11-01',
    );
  });

  it('exports daily totals as escaped CSV rows, with a blank mg for days without a record', () => {
    const csv = makeDailyTotalsCSV([
      { date: '2026-04-25', mg: 95, entries: 1, source: 'Manual' },
      { date: '2026-04-26', mg: null, entries: 0 },
      { date: '2026-04-27, late "boost"', mg: 12.5, entries: 2, source: 'Sample Data' },
    ]);

    expect(csv).toBe(
      [
        'date,mg,entries,status,data_source',
        '"2026-04-25","95","1","recorded","Manual"',
        '"2026-04-26","","0","no record",""',
        '"2026-04-27, late ""boost""","12.5","2","recorded","Sample Data"',
      ].join('\n')
    );
  });

  it('builds one daily row per local day from the first record to today, never writing 0 mg for a gap', () => {
    const now = new Date(2026, 6, 24, 12, 0, 0, 0).getTime();
    const rows = getDailyTotalRows(
      [
        { id: 'a', timestamp: new Date(2026, 6, 21, 8).getTime(), mg: 95 },
        { id: 'demo:dose:1', timestamp: new Date(2026, 6, 21, 15).getTime(), mg: 60 },
        { id: 'b', timestamp: new Date(2026, 6, 23, 9).getTime(), mg: 70 },
        // Future entries are not recorded intake yet.
        { id: 'future', timestamp: new Date(2026, 6, 25, 9).getTime(), mg: 500 },
      ],
      now,
    );

    expect(rows).toEqual([
      { date: '2026-07-21', mg: 155, entries: 2, source: 'Manual and Sample Data' },
      { date: '2026-07-22', mg: null, entries: 0 },
      { date: '2026-07-23', mg: 70, entries: 1, source: 'Manual' },
      { date: '2026-07-24', mg: null, entries: 0 },
    ]);
    const csv = makeDailyTotalsCSV(rows);
    expect(csv).not.toMatch(/"2026-07-22","0"/);
    expect(csv).toContain('"2026-07-22","","0","no record",""');
  });

  it('exports no daily rows when nothing was recorded', () => {
    expect(getDailyTotalRows([], Date.now())).toEqual([]);
    expect(makeDailyTotalsCSV([])).toBe('date,mg,entries,status,data_source');
  });

  it('steps daily rows by calendar day across a DST change', () => {
    const originalZone = process.env.TZ;
    process.env.TZ = 'America/New_York';
    try {
      const rows = getDailyTotalRows(
        [{ id: 'a', timestamp: new Date(2026, 2, 7, 9).getTime(), mg: 95 }],
        new Date(2026, 2, 9, 12).getTime(),
      );
      expect(rows.map((row) => row.date)).toEqual(['2026-03-07', '2026-03-08', '2026-03-09']);
    } finally {
      process.env.TZ = originalZone;
    }
  });

  it('exports every recorded entry in time order with its data source', () => {
    const csv = makeDoseEntriesCSV([
      { id: 'demo:dose:2', timestamp: Date.UTC(2026, 6, 24, 16), mg: 60, source: 'Tea', note: 'Sample data' },
      { id: 'dose "1"', timestamp: Date.UTC(2026, 6, 24, 15), mg: 95, source: 'Drip, large' },
    ]);
    const lines = csv.split('\n');

    expect(lines[0]).toBe('id,local_date,timestamp,datetime,mg,drink,note,data_source');
    expect(lines).toHaveLength(3);
    expect(lines[1]).toContain('"dose ""1"""');
    expect(lines[1]).toContain('"2026-07-24T15:00:00.000Z","95","Drip, large","","Manual"');
    expect(lines[2]).toContain('"60","Tea","Sample data","Sample Data"');
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
        rating: 'Sluggish',
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
          'data_source',
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
          '"Sluggish"',
          '"Recorded"',
        ].join(','),
      ].join('\n')
    );
  });
});
