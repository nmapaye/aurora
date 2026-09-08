import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import {
  getNativeSleepSamples,
  makeHealthSleepSessionId,
  normalizeSleepSamples,
} from '~/services/platform/health/appleHealth';

describe('Health sleep query errors', () => {
  test('propagates a native query failure instead of reporting an empty successful result', async () => {
    await expect(
      getNativeSleepSamples(
        async () => {
          throw new Error('Health database unavailable');
        },
        1,
        2,
      ),
    ).rejects.toThrow('Health database unavailable');
  });

  test.each([undefined, { samples: [] }, 'not an array'])(
    'rejects malformed native response payload %p',
    async (payload) => {
      await expect(
        getNativeSleepSamples(
          async () => payload as unknown as unknown[],
          1,
          2,
        ),
      ).rejects.toThrow('Health sleep query returned an invalid payload.');
    },
  );

  test('preserves an actual empty array as a successful zero-result response', async () => {
    await expect(getNativeSleepSamples(async () => [], 1, 2)).resolves.toEqual(
      [],
    );
  });
});

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
        value: 'ASLEEP',
      },
      {
        start: '1772086500000',
        end: '1772111700000',
        value: 3,
      },
    ]);

    expect(samples).toEqual([
      {
        start: Date.parse('2026-03-01T00:00:00.000Z'),
        end: Date.parse('2026-03-01T07:30:00.000Z'),
        value: undefined,
        label: 'ASLEEP',
      },
      {
        start: 1_772_086_500_000,
        end: 1_772_111_700_000,
        value: 3,
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
      }),
    ).toBe('healthkit:sleep:1772668800000:1772697600000');
  });
});

describe('bundled HealthKit fallback', () => {
  afterEach(() => {
    jest.dontMock('react-native-health');
    jest.resetModules();
  });

  test('includes the installed HealthKit client in Metro dependency collection', () => {
    const { parse } = require('@babel/parser');
    const collectDependencies =
      require('metro/private/ModuleGraph/worker/collectDependencies').default;
    const source = readFileSync(
      join(
        __dirname,
        '../../../../src/services/platform/health/appleHealth.ts',
      ),
      'utf8',
    );
    const ast = parse(source, {
      sourceType: 'module',
      plugins: ['typescript'],
    });
    const { dependencies } = collectDependencies(ast, {
      asyncRequireModulePath: 'metro-runtime/src/modules/asyncRequire',
      dynamicRequires: 'reject',
      inlineableCalls: [],
      keepRequireNames: true,
      allowOptionalDependencies: true,
    });
    expect(
      dependencies.map((dependency: { name: string }) => dependency.name),
    ).toContain('react-native-health');
  });

  test('does not report Constants-only Expo Go modules as available', async () => {
    jest.resetModules();
    jest.doMock('react-native-health', () => ({
      Constants: { Permissions: { SleepAnalysis: 'SleepAnalysis' } },
    }));
    const health = require('~/services/platform/health/appleHealth');
    await expect(health.isAvailable()).resolves.toBe(false);
    await expect(health.requestAuthorization()).resolves.toBe(false);
    await expect(health.getSleepSamples(1, 2)).rejects.toThrow(
      'Apple Health is unavailable in this build.',
    );
  });

  test.each([
    [null, false],
    [new Error('HealthKit unavailable'), true],
  ])(
    'respects native availability result %p / %p',
    async (error, available) => {
      jest.resetModules();
      jest.doMock('react-native-health', () => ({
        isAvailable: (callback: (error: unknown, available: unknown) => void) =>
          callback(error, available),
        initHealthKit: jest.fn(),
        getSleepSamples: jest.fn(),
      }));
      const health = require('~/services/platform/health/appleHealth');
      await expect(health.isAvailable()).resolves.toBe(false);
    },
  );

  test('uses the native client with sleep read permission and no write permissions', async () => {
    jest.resetModules();
    const initHealthKit = jest.fn((_options, callback) => callback(null));
    const getSleepSamples = jest.fn((_options, callback) =>
      callback(null, [{ start: 1, end: 2, value: 'ASLEEP' }]),
    );
    jest.doMock('react-native-health', () => ({
      isAvailable: (callback: (error: unknown, available: boolean) => void) =>
        callback(null, true),
      initHealthKit,
      getSleepSamples,
      Constants: { Permissions: { SleepAnalysis: 'SleepAnalysis' } },
    }));
    const health = require('~/services/platform/health/appleHealth');
    await expect(health.isAvailable()).resolves.toBe(true);
    await expect(health.requestAuthorization()).resolves.toBe(true);
    expect(initHealthKit).toHaveBeenCalledWith(
      { permissions: { read: ['SleepAnalysis'], write: [] } },
      expect.any(Function),
    );
    await expect(health.getSleepSamples(1, 2)).resolves.toEqual([
      { start: 1, end: 2, value: undefined, label: 'ASLEEP' },
    ]);
  });
});

describe('Health sleep categories', () => {
  test.each(['INBED', 'AWAKE', 'UNKNOWN', 'inBed', 0, 2, 99])(
    'excludes non-sleep category %p',
    (value) => {
      expect(normalizeSleepSamples([{ start: 1, end: 2, value }])).toEqual([]);
    },
  );

  test.each([
    'ASLEEP',
    'CORE',
    'DEEP',
    'REM',
    'ASLEEP_CORE',
    'ASLEEP_DEEP',
    'ASLEEP_REM',
    1,
    3,
    4,
    5,
  ])('retains sleep category %p', (value) => {
    expect(normalizeSleepSamples([{ start: 1, end: 2, value }])).toHaveLength(
      1,
    );
  });

  test('filters non-sleep labels before deduplicating identical windows', () => {
    expect(
      normalizeSleepSamples([
        { start: 1, end: 2, label: 'INBED' },
        { start: 1, end: 2, label: 'ASLEEP' },
        { start: 3, end: 4, label: 'AWAKE' },
      ]),
    ).toEqual([{ start: 1, end: 2, value: undefined, label: 'ASLEEP' }]);
  });
});
