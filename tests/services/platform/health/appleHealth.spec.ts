import {
  makeHealthSleepSessionId,
  normalizeSleepSamples,
} from '~/services/platform/health/appleHealth';

describe('normalizeSleepSamples', () => {
  test('accepts start/end and startDate/endDate aliases with number and string dates', () => {
    const samples = normalizeSleepSamples([
      {
        start: 1_772_000_000_000,
        end: 1_772_025_200_000,
        label: 'ASLEEP',
      },
      {
        startDate: '2026-03-01T00:00:00.000Z',
        endDate: '2026-03-01T07:30:00.000Z',
        value: 'INBED',
      },
      {
        start: '1772086500000',
        end: '1772111700000',
        value: 2,
      },
    ]);

    expect(samples).toEqual([
      {
        start: Date.parse('2026-03-01T00:00:00.000Z'),
        end: Date.parse('2026-03-01T07:30:00.000Z'),
        value: undefined,
        label: 'INBED',
      },
      {
        start: 1_772_086_500_000,
        end: 1_772_111_700_000,
        value: 2,
        label: undefined,
      },
      {
        start: 1_772_000_000_000,
        end: 1_772_025_200_000,
        value: undefined,
        label: 'ASLEEP',
      },
    ]);
  });

  test('falls back to aliases when the primary date fields are invalid', () => {
    const samples = normalizeSleepSamples([
      {
        start: 'invalid',
        startDate: '2026-03-03T01:00:00.000Z',
        end: null,
        endDate: '2026-03-03T08:00:00.000Z',
        label: 'ASLEEP_CORE',
      },
    ]);

    expect(samples).toEqual([
      {
        start: Date.parse('2026-03-03T01:00:00.000Z'),
        end: Date.parse('2026-03-03T08:00:00.000Z'),
        value: undefined,
        label: 'ASLEEP_CORE',
      },
    ]);
  });

  test('drops non-object samples, invalid dates, and non-positive ranges', () => {
    const samples = normalizeSleepSamples([
      null,
      'not a sample',
      { startDate: 'invalid', endDate: '2026-03-01T07:30:00.000Z' },
      {
        startDate: '2026-03-01T07:30:00.000Z',
        endDate: '2026-03-01T07:30:00.000Z',
      },
      {
        startDate: '2026-03-02T07:30:00.000Z',
        endDate: '2026-03-02T00:00:00.000Z',
      },
      {
        startDate: '2026-03-02T00:00:00.000Z',
        endDate: '2026-03-02T07:30:00.000Z',
      },
    ]);

    expect(samples).toHaveLength(1);
    expect(samples[0]).toMatchObject({
      start: Date.parse('2026-03-02T00:00:00.000Z'),
      end: Date.parse('2026-03-02T07:30:00.000Z'),
    });
  });

  test('preserves numeric values and prefers explicit labels over string values', () => {
    const samples = normalizeSleepSamples([
      {
        startDate: '2026-03-04T00:00:00.000Z',
        endDate: '2026-03-04T08:00:00.000Z',
        value: 1,
        label: 'ASLEEP_DEEP',
      },
      {
        startDate: '2026-03-03T00:00:00.000Z',
        endDate: '2026-03-03T08:00:00.000Z',
        value: 'ASLEEP_REM',
      },
    ]);

    expect(samples[0]).toMatchObject({
      value: 1,
      label: 'ASLEEP_DEEP',
    });
    expect(samples[1]).toMatchObject({
      value: undefined,
      label: 'ASLEEP_REM',
    });
  });

  test('deduplicates samples with the same normalized sleep window', () => {
    const samples = normalizeSleepSamples([
      {
        startDate: '2026-03-05T00:00:00.000Z',
        endDate: '2026-03-05T08:00:00.000Z',
        label: 'ASLEEP_CORE',
      },
      {
        start: Date.parse('2026-03-05T00:00:00.000Z'),
        end: Date.parse('2026-03-05T08:00:00.000Z'),
        label: 'ASLEEP_DEEP',
      },
      {
        startDate: '2026-03-04T00:00:00.000Z',
        endDate: '2026-03-04T08:00:00.000Z',
        label: 'ASLEEP_REM',
      },
    ]);

    expect(samples).toHaveLength(2);
    expect(samples.map((sample) => `${sample.start}:${sample.end}`)).toEqual([
      `${Date.parse('2026-03-05T00:00:00.000Z')}:${Date.parse('2026-03-05T08:00:00.000Z')}`,
      `${Date.parse('2026-03-04T00:00:00.000Z')}:${Date.parse('2026-03-04T08:00:00.000Z')}`,
    ]);
  });

  test('builds stable Health sleep session ids from normalized boundaries', () => {
    expect(
      makeHealthSleepSessionId({
        start: Date.parse('2026-03-05T00:00:00.000Z'),
        end: Date.parse('2026-03-05T08:00:00.000Z'),
      })
    ).toBe('healthkit:sleep:1772668800000:1772697600000');
  });
});
