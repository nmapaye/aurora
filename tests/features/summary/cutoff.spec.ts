import { getCutoffAnnotation } from '~/features/summary/presentation';

const at = (day: number, hour: number, minute = 0) =>
  new Date(2026, 8, day, hour, minute).getTime();
const time = (ts: number) => {
  const d = new Date(ts);
  return `${d.getDate()}@${d.getHours()}h`;
};

describe('caffeine cutoff annotation', () => {
  it('marks today’s cutoff before it arrives, even with nothing logged', () => {
    const annotation = getCutoffAnnotation({
      now: at(26, 10),
      cutoffHour: 16,
      doses: [],
      formatTime: time,
    });

    expect(annotation).toEqual({
      at: at(26, 16),
      isPast: false,
      nextAt: at(26, 16),
      text: 'Your cutoff: 26@16h today.',
    });
  });

  it('keeps today’s mark after the cutoff and names tomorrow as next when caffeine was logged', () => {
    const annotation = getCutoffAnnotation({
      now: at(26, 20),
      cutoffHour: 16,
      doses: [{ timestamp: at(26, 9), mg: 95 }],
      formatTime: time,
    });

    expect(annotation).toEqual({
      at: at(26, 16),
      isPast: true,
      nextAt: at(27, 16),
      text: 'Your cutoff was 26@16h. Next: tomorrow, 27@16h.',
    });
  });

  it('treats the exact cutoff minute as passed', () => {
    const annotation = getCutoffAnnotation({
      now: at(26, 16),
      cutoffHour: 16,
      doses: [{ timestamp: at(26, 8), mg: 60 }],
      formatTime: time,
    });

    expect(annotation?.isPast).toBe(true);
    expect(annotation?.nextAt).toBe(at(27, 16));
  });

  it('is omitted after the cutoff when nothing was logged today', () => {
    expect(
      getCutoffAnnotation({
        now: at(26, 20),
        cutoffHour: 16,
        // Yesterday's dose and a future-dated entry do not count as today.
        doses: [
          { timestamp: at(25, 15), mg: 95 },
          { timestamp: at(26, 22), mg: 60 },
        ],
      }),
    ).toBeNull();
  });

  it('clamps and rounds the stored hour and ignores invalid values', () => {
    expect(
      getCutoffAnnotation({ now: at(26, 1), cutoffHour: 30, doses: [] })?.at,
    ).toBe(at(26, 23));
    expect(
      getCutoffAnnotation({ now: at(26, 1), cutoffHour: 14.6, doses: [] })?.at,
    ).toBe(at(26, 15));
    expect(
      getCutoffAnnotation({ now: at(26, 1), cutoffHour: Number.NaN, doses: [] }),
    ).toBeNull();
  });
});
