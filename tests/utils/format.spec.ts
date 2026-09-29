import { formatClockHour } from '~/utils/format';

describe('formatClockHour', () => {
  it('formats an hour with the device locale instead of a fixed 24h string', () => {
    const expected = new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' })
      .format(new Date(2026, 0, 1, 16, 0));
    expect(formatClockHour(16)).toBe(expected);
  });

  it('clamps and rounds out-of-range hours', () => {
    expect(formatClockHour(27)).toBe(formatClockHour(23));
    expect(formatClockHour(-1)).toBe(formatClockHour(0));
    expect(formatClockHour(15.6)).toBe(formatClockHour(16));
  });
});
