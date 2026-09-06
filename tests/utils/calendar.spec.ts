import { addCalendarDays, isLocalDateKey, localDateKey, startOfLocalDay } from '~/utils/calendar';

describe('local calendar dates', () => {
  it('uses local components rather than UTC dates', () => {
    const instant = new Date(2026, 8, 7, 0, 15).getTime();
    expect(localDateKey(instant)).toBe('2026-09-07');
    expect(startOfLocalDay(instant)).toBe(new Date(2026, 8, 7).getTime());
  });

  it('crosses month and leap-year boundaries without losing wall time', () => {
    const instant = new Date(2024, 1, 28, 22, 30).getTime();
    expect(addCalendarDays(instant, 2)).toBe(new Date(2024, 2, 1, 22, 30).getTime());
    expect(addCalendarDays(instant, -28)).toBe(new Date(2024, 0, 31, 22, 30).getTime());
  });

  it('keeps wall time across daylight-saving transitions', () => {
    const spring = new Date(2026, 2, 7, 22, 30).getTime();
    const fall = new Date(2026, 9, 31, 22, 30).getTime();
    expect(addCalendarDays(spring, 1)).toBe(new Date(2026, 2, 8, 22, 30).getTime());
    expect(addCalendarDays(fall, 1)).toBe(new Date(2026, 10, 1, 22, 30).getTime());
    // The delivery gate also runs this suite with TZ=America/New_York.
    if (process.env.TZ === 'America/New_York') {
      expect(addCalendarDays(spring, 1) - spring).toBe(23 * 3_600_000);
      expect(addCalendarDays(fall, 1) - fall).toBe(25 * 3_600_000);
    }
  });

  it.each(['2026-02-29', '2026-04-31', '2026-13-01', '2026-1-01', '', 'NaN'])('rejects invalid date %s', (value) => {
    expect(isLocalDateKey(value)).toBe(false);
  });

  it('accepts leap days and ordinary date keys', () => {
    expect(isLocalDateKey('2024-02-29')).toBe(true);
    expect(isLocalDateKey('2026-09-07')).toBe(true);
    expect(isLocalDateKey('0001-01-01')).toBe(true);
  });
});
