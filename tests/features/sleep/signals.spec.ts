import type { Dose, SleepSession } from '~/domain/models';
import {
  describeSleepChartDay,
  getSleepPresentation,
} from '~/features/sleep/presentation';
import {
  caffeineTimingSignal,
  describeSleepAge,
  describeTargetComparison,
  formatGap,
  recentNightSignal,
} from '~/features/sleep/signals';

const now = new Date(2026, 6, 24, 12, 0).getTime();
const hour = 60 * 60 * 1000;
const day = 24 * hour;
const clock = (ts: number) => {
  const date = new Date(ts);
  return `${date.getHours()}:${String(date.getMinutes()).padStart(2, '0')}`;
};
const date = (ts: number) => {
  const value = new Date(ts);
  return `${value.getMonth() + 1}/${value.getDate()}`;
};

function night(id: string, daysAgo: number, hours = 8): SleepSession {
  const end = new Date(2026, 6, 24 - daysAgo, 6, 0).getTime();
  return { id, start: end - hours * hour, end, type: 'sleep' };
}

function pairedNights(count: number, gapHours = 3) {
  const sleeps = Array.from({ length: count }, (_, index) =>
    night(`manual:sleep:${index}`, index + 1),
  );
  const doses: Dose[] = sleeps.map((sleep, index) => ({
    id: `dose:${index}`,
    timestamp: sleep.start - gapHours * hour - index * 10 * 60 * 1000,
    mg: 80,
  }));
  return { sleeps, doses };
}

describe('formatGap and target comparison', () => {
  it('formats compact durations', () => {
    expect(formatGap(40 * 60 * 1000)).toBe('40m');
    expect(formatGap(2 * hour)).toBe('2h');
    expect(formatGap(7.25 * hour)).toBe('7h 15m');
  });

  it('describes the target as context, not a prescription', () => {
    expect(describeTargetComparison(7.5 * hour, 8)).toBe('30m under your 8h target');
    expect(describeTargetComparison(8.25 * hour, 8)).toBe('15m over your 8h target');
    expect(describeTargetComparison(8 * hour, 8)).toBe('On your 8h target');
    expect(describeTargetComparison(7 * hour, 7.5)).toBe('30m under your 7h 30m target');
  });
});

describe('recentNightSignal', () => {
  it('names every source when a manual night merges with a sample night', () => {
    const wake = now - 2 * hour;
    const signal = recentNightSignal(
      [
        { id: 'demo:sleep:night', start: wake - 16 * hour, end: wake - 8 * hour, type: 'sleep' },
        { id: 'manual:sleep:1:a', start: wake - 8 * hour, end: wake, type: 'sleep' },
      ],
      8,
      now,
      clock,
    );

    expect(signal).toMatchObject({ status: 'observed', source: 'Manual and Sample Data' });
  });

  it('is a quiet empty signal with no value when no night is recent', () => {
    const signal = recentNightSignal([night('manual:sleep:old', 9)], 8, now, clock);
    expect(signal).toEqual({
      id: 'sleep-recent-night',
      label: 'Most Recent Sleep',
      status: 'empty',
      period: 'Last 7 days',
      context: 'No sleep recorded in the last 7 days.',
      destination: 'Add Sleep',
    });
    expect(signal.value).toBeUndefined();
  });

  it.each([
    ['manual:sleep:1', 'Manual', 'observed'],
    ['healthkit:sleep:1', 'Health', 'observed'],
    ['demo:sleep:1', 'Sample Data', 'sample'],
  ] as const)('labels %s as %s', (id, source, status) => {
    const signal = recentNightSignal([night(id, 0, 7.5)], 8, now, clock, date);
    expect(signal).toMatchObject({
      label: 'Most Recent Sleep',
      status,
      source,
      period: 'Today',
      value: '7h 30m',
      context: '7/24 · 22:30 – 6:00 · 30m under your 8h target',
      destination: 'Show All Data',
    });
  });

  it('merges fragmented samples into one night, like the chart', () => {
    const first = { id: 'healthkit:sleep:a', start: new Date(2026, 6, 23, 23, 0).getTime(), end: new Date(2026, 6, 24, 2, 0).getTime(), type: 'sleep' as const };
    const second = { id: 'healthkit:sleep:b', start: new Date(2026, 6, 24, 2, 30).getTime(), end: new Date(2026, 6, 24, 7, 0).getTime(), type: 'sleep' as const };
    expect(recentNightSignal([first, second], 8, now, clock, date)).toMatchObject({
      value: '7h 30m',
      context: '7/24 · 23:00 – 7:00 · 30m under your 8h target',
    });
  });

  it('leads an older sample night with its date and says how long ago it was', () => {
    // QA case: a Sep 21 sample night viewed on Sep 27 must not read as last night.
    const signal = recentNightSignal([night('demo:sleep:1', 6)], 8, now, clock, date);
    expect(signal).toMatchObject({
      label: 'Most Recent Sleep',
      status: 'sample',
      source: 'Sample Data',
      period: '6 days ago',
      value: '8h 0m',
      context: '7/18 · 22:00 – 6:00 · On your 8h target',
    });
    expect(JSON.stringify(signal)).not.toMatch(/Latest Night|Last Night/i);
  });

  it('counts sleep age in calendar days', () => {
    expect(describeSleepAge(new Date(2026, 6, 24, 6, 0).getTime(), now)).toBe('Today');
    expect(describeSleepAge(new Date(2026, 6, 23, 23, 59).getTime(), now)).toBe('Yesterday');
    expect(describeSleepAge(new Date(2026, 6, 21, 7, 0).getTime(), now)).toBe('3 days ago');
    // Across the November DST change: still three calendar days.
    expect(
      describeSleepAge(new Date(2026, 10, 1, 7, 0).getTime(), new Date(2026, 10, 4, 7, 0).getTime()),
    ).toBe('3 days ago');
  });
});

describe('caffeineTimingSignal', () => {
  it('shows only progress, with no timing number, at 1 of 14 paired nights', () => {
    const { sleeps, doses } = pairedNights(1, 8.25);
    const signal = caffeineTimingSignal(sleeps, doses, now);
    expect(signal).toEqual({
      status: 'gathering',
      label: 'Caffeine timing before sleep',
      pairedNights: 1,
      required: 14,
      text: '1 of 14 nights so far with both sleep and caffeine logged in the 12 hours before it. A typical timing appears at 14.',
    });
    // 8h 15m = 495 minutes must not leak as a headline or a 495–495 range.
    expect(JSON.stringify(signal)).not.toMatch(/495|8h 15m/);
  });

  it('explains the gate when no night is paired yet', () => {
    const signal = caffeineTimingSignal([night('manual:sleep:1', 1)], [], now);
    expect(signal).toMatchObject({ status: 'gathering', pairedNights: 0 });
    expect(signal.status === 'gathering' && signal.text).toMatch(/^No nights yet/);
  });

  it('stays gathering at 13 paired nights', () => {
    const { sleeps, doses } = pairedNights(13);
    expect(caffeineTimingSignal(sleeps, doses, now)).toMatchObject({
      status: 'gathering',
      pairedNights: 13,
    });
  });

  it('shows one observed median with its night count at 14, over 30 days regardless of chart range', () => {
    const { sleeps, doses } = pairedNights(14);
    const signal = caffeineTimingSignal(sleeps, doses, now);
    expect(signal).toMatchObject({
      status: 'observed',
      label: 'Caffeine timing before sleep',
      pairedNights: 14,
      period: 'Last 30 days',
      context: 'Median time from last logged caffeine to sleep · 14 nights',
    });
    if (signal.status !== 'observed') throw new Error('expected observed');
    // Gaps run 3h, 3h 10m, ... 5h 10m; the median sits in the middle.
    expect(signal.value).toBe('4h 10m');
    expect(signal.detailRows).toEqual([
      { title: 'Middle 80% of nights', value: '3h 10m – 5h' },
      { title: 'Nights with both logged', value: '14' },
    ]);
    expect(JSON.stringify(signal)).not.toMatch(/correlat|caus|affect|impact|pattern|should|recommend/i);
  });
});

describe('sleep chart day readout', () => {
  it('reads a missing day as missing, never as zero', () => {
    const presentation = getSleepPresentation([night('manual:sleep:1', 0)], 8, 'week', now);
    const missing = presentation.points[5];
    expect(missing.durationMs).toBeNull();
    expect(describeSleepChartDay(missing).value).toBe('No sleep recorded');
    expect(describeSleepChartDay(presentation.points[6]).value).toBe('8h 0m');
    expect(describeSleepChartDay(presentation.points[6]).text).toMatch(/, 8h 0m$/);
  });

  it('averages recorded nights only', () => {
    const presentation = getSleepPresentation(
      [night('manual:sleep:a', 0, 8), night('manual:sleep:b', 2, 6)],
      8,
      'week',
      now,
    );
    expect(presentation.recordedNights).toBe(2);
    expect(presentation.averageDurationMs).toBe(7 * hour);
    expect(
      getSleepPresentation([], 8, 'month', now + day).averageDurationMs,
    ).toBeNull();
  });
});
