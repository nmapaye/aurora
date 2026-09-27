import { normalizeSleepSamples } from '~/services/platform/health/appleHealth';

describe('health sleep normalization', () => {
  test('accepts HealthKit-style date strings and sorts newest first', () => {
    const samples = normalizeSleepSamples([
      { startDate: '2026-03-01T00:00:00.000Z', endDate: '2026-03-01T07:30:00.000Z', value: 'ASLEEP' },
      { startDate: '2026-03-02T00:15:00.000Z', endDate: '2026-03-02T07:15:00.000Z', value: 'ASLEEP' },
    ]);

    expect(samples).toHaveLength(2);
    expect(samples[0].start).toBe(Date.parse('2026-03-02T00:15:00.000Z'));
    expect(samples[1].start).toBe(Date.parse('2026-03-01T00:00:00.000Z'));
    expect(samples[0].label).toBe('ASLEEP');
  });

  test('drops malformed samples', () => {
    const samples = normalizeSleepSamples([
      { startDate: '2026-03-01T00:00:00.000Z', endDate: '2026-03-01T07:30:00.000Z' },
      { startDate: 'invalid', endDate: '2026-03-01T07:30:00.000Z' },
      { startDate: '2026-03-01T07:30:00.000Z', endDate: '2026-03-01T00:00:00.000Z' },
    ]);

    expect(samples).toHaveLength(1);
  });
});
  
