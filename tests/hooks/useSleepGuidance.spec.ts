import type { Dose } from '~/domain/models';
import { getSleepGuidance } from '~/hooks/useSleepGuidance';

const now = new Date(2026, 6, 24, 12, 0, 0, 0).getTime();
const dose = (id: string, timestamp: number, mg: number): Dose => ({ id, timestamp, mg });

describe('getSleepGuidance', () => {
  it('derives guidance from the supplied selected-range doses', () => {
    const selectedRange = [dose('selected', now, 240)];

    const selected = getSleepGuidance(selectedRange, 5, now);
    const empty = getSleepGuidance([], 5, now);

    expect(selected.mgAtBed).toBeGreaterThan(0);
    expect(empty).not.toEqual(selected);
  });
});
