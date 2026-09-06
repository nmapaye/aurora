import { sleepDebt, totalSleepHoursLast24 } from '~/domain/algorithm/sleepDebt';

const now = new Date(2026, 8, 7, 12).getTime();
const hour = 3_600_000;
const interval = (startHoursAgo: number, endHoursAgo: number) => ({
  start: now - startHoursAgo * hour,
  end: now - endHoursAgo * hour,
});

describe('sleep overlap accounting', () => {
  it('counts overlapping imports and manual entries once', () => {
    expect(totalSleepHoursLast24(now, [interval(10, 2), interval(6, 0)])).toBe(
      10,
    );
  });

  it('handles duplicates and nested intervals independent of input order', () => {
    expect(
      totalSleepHoursLast24(now, [
        interval(5, 3),
        interval(8, 0),
        interval(8, 0),
      ]),
    ).toBe(8);
  });

  it('clips the union to the rolling 24-hour window and excludes future time', () => {
    expect(
      totalSleepHoursLast24(now, [
        interval(30, 20),
        interval(23, 19),
        interval(2, -4),
      ]),
    ).toBe(7);
  });

  it('preserves gaps between separate sleep opportunities', () => {
    expect(totalSleepHoursLast24(now, [interval(10, 6), interval(4, 2)])).toBe(
      6,
    );
  });

  it('ignores malformed and reversed intervals', () => {
    expect(
      totalSleepHoursLast24(now, [
        interval(4, 2),
        interval(1, 3),
        { start: NaN, end: now },
        { start: -Infinity, end: now },
        { start: -1e100, end: now },
      ]),
    ).toBe(2);
  });

  it('keeps duplicated records from hiding a sleep deficit', () => {
    expect(sleepDebt(now, [interval(4, 0), interval(4, 0)], 8)).toBe(0.5);
  });
});
