import {
  normalizeHealthSleepSessionIdentities,
} from '~/features/sleep/healthSleep';

describe('legacy Health sleep identity normalization', () => {
  it('canonicalizes only literal boundary-equivalent legacy Health IDs', () => {
    const exact = {
      id: 'sleep:1000.4:2000.4',
      start: 1000.4,
      end: 2000.4,
      type: 'sleep' as const,
    };
    const roundedOnlyMatch = {
      id: 'sleep:3000.4:4000.4',
      start: 3000.49,
      end: 4000.49,
      type: 'sleep' as const,
    };
    const manual = {
      id: 'manual:sleep:5000.4:6000.4',
      start: 5000.4,
      end: 6000.4,
      type: 'sleep' as const,
    };

    expect(
      normalizeHealthSleepSessionIdentities([exact, roundedOnlyMatch, manual]),
    ).toEqual([
      { ...exact, id: 'healthkit:sleep:1000:2000' },
      roundedOnlyMatch,
      manual,
    ]);
  });
});
