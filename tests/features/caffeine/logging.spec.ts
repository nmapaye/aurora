import type { Dose } from '~/domain/models';
import {
  buildCustomDose,
  buildQuickAddDose,
  createCustomDoseDraft,
  getTodayCaffeineTotal,
  getRemainingDailyCaffeineLimit,
  validateCustomDoseDraft,
} from '~/features/caffeine/logging';

const localTime = (year: number, month: number, day: number, hour = 0, minute = 0) =>
  new Date(year, month, day, hour, minute).getTime();

describe('caffeine logging helpers', () => {
  const now = localTime(2026, 6, 24, 12);
  const doses: Dose[] = [
    { id: 'yesterday', timestamp: localTime(2026, 6, 23, 23, 59), mg: 90 },
    { id: 'morning', timestamp: localTime(2026, 6, 24, 8), mg: 95 },
    { id: 'noon', timestamp: localTime(2026, 6, 24, 11, 59), mg: 60 },
    { id: 'tomorrow', timestamp: localTime(2026, 6, 25), mg: 160 },
  ];

  it('totals doses inside the current local-day boundary only', () => {
    expect(getTodayCaffeineTotal(doses, now)).toBe(155);
    expect(getRemainingDailyCaffeineLimit(doses, now, 400)).toBe(245);
  });

  it.each([
    [1, true],
    [1999, true],
    [0, false],
    [2000, false],
  ])('validates the %i mg custom amount boundary', (mg, valid) => {
    expect(
      validateCustomDoseDraft(
        { ...createCustomDoseDraft(now), mg: String(mg) },
        now,
      ).valid,
    ).toBe(valid);
  });

  it('rejects a custom entry time in the future', () => {
    expect(
      validateCustomDoseDraft(
        { ...createCustomDoseDraft(now), timestamp: now + 1 },
        now,
      ),
    ).toEqual({ valid: false, message: 'Time cannot be in the future.' });
  });

  it('builds quick additions at now with the exact preset source', () => {
    expect(
      buildQuickAddDose(
        { id: 'drip', label: 'Drip', mg: 95, symbol: 'cup.and.saucer.fill' },
        now,
        () => 'dose:quick',
      ),
    ).toEqual({ id: 'dose:quick', timestamp: now, mg: 95, source: 'Drip' });
  });

  it('builds custom additions with their selected time and optional note', () => {
    expect(
      buildCustomDose(
        { mg: '80', source: 'Tea', timestamp: now - 30 * 60_000, note: 'After lunch' },
        () => 'dose:custom',
      ),
    ).toEqual({
      id: 'dose:custom',
      timestamp: now - 30 * 60_000,
      mg: 80,
      source: 'Tea',
      note: 'After lunch',
    });
  });
});
