import {
  describeNoCaffeineNote,
  hasCaffeineSignal,
} from '~/features/summary/presentation';

const dayStart = new Date(2026, 8, 27, 0, 0, 0, 0).getTime();
const dayEnd = new Date(2026, 8, 28, 0, 0, 0, 0).getTime();
const at = (hour: number) => new Date(2026, 8, 27, hour, 0, 0, 0).getTime();
const flat = [0, 6, 12, 18].map((hour) => ({ t: at(hour), mg: 0 }));

describe('caffeine signal for today’s curve', () => {
  it('is empty with no doses and a flat series', () => {
    expect(
      hasCaffeineSignal({ series: flat, doses: [], dayStart, dayEnd }),
    ).toBe(false);
  });

  it('treats sub-milligram model residue as empty, matching the 0 mg summary', () => {
    const residue = flat.map((point) => ({ ...point, mg: 0.4 }));
    expect(
      hasCaffeineSignal({ series: residue, doses: [], dayStart, dayEnd }),
    ).toBe(false);
  });

  it('ignores doses outside today when nothing carries over', () => {
    const doses = [
      { id: 'old', timestamp: dayStart - 3 * 86_400_000, mg: 95 },
      { id: 'tomorrow', timestamp: dayEnd, mg: 95 },
    ];
    expect(hasCaffeineSignal({ series: flat, doses, dayStart, dayEnd })).toBe(
      false,
    );
  });

  it('has a signal once a dose is logged today, even before it registers on the curve', () => {
    const doses = [{ id: 'd', timestamp: at(9), mg: 60 }];
    expect(hasCaffeineSignal({ series: flat, doses, dayStart, dayEnd })).toBe(
      true,
    );
  });

  it('has a signal for modeled carryover with nothing logged today', () => {
    const carryover = [{ t: at(0), mg: 42 }, ...flat.slice(1)];
    expect(
      hasCaffeineSignal({ series: carryover, doses: [], dayStart, dayEnd }),
    ).toBe(true);
  });

  it('describes the empty note, with the cutoff when there is one', () => {
    expect(describeNoCaffeineNote()).toBe(
      'Caffeine today. No caffeine logged today, and none is carried over from earlier. Today’s active-caffeine curve appears once you log a dose.',
    );
    expect(describeNoCaffeineNote('Your cutoff: 2 PM today.')).toMatch(
      /log a dose\. Your cutoff: 2 PM today\.$/,
    );
  });
});
