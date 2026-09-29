import AppleHealth from '~/services/platform/health/appleHealth';
import {
  countSleepNights,
  describeImportedNights,
  importHealthSleep,
  NO_HEALTH_SLEEP_MESSAGE,
} from '~/features/sleep/healthImport';
import { useStore } from '~/state/store';

const HOUR = 3_600_000;
const NIGHT = 1_800_000_000_000;

afterEach(() => jest.restoreAllMocks());

describe('countSleepNights', () => {
  it('counts overlapping Watch and iPhone samples and stage segments as one night', () => {
    expect(
      countSleepNights([
        { start: NIGHT, end: NIGHT + 8 * HOUR },
        { start: NIGHT + 10 * 60_000, end: NIGHT + 3 * HOUR },
        { start: NIGHT + 3 * HOUR + 5 * 60_000, end: NIGHT + 8 * HOUR },
        { start: NIGHT + 24 * HOUR, end: NIGHT + 31 * HOUR },
      ]),
    ).toBe(2);
  });

  it('describes nights in plain language', () => {
    expect(describeImportedNights(1)).toBe('Imported 1 night of sleep from Health.');
    expect(describeImportedNights(3)).toBe('Imported 3 nights of sleep from Health.');
    expect(describeImportedNights(0)).toBe(NO_HEALTH_SLEEP_MESSAGE);
  });
});

describe('importHealthSleep', () => {
  beforeEach(() => {
    jest.spyOn(Date, 'now').mockReturnValue(NIGHT + 40 * HOUR);
    useStore.setState({ sleeps: [] });
  });

  it('queries the requested window, stores sessions, and reports nights', async () => {
    const query = jest.spyOn(AppleHealth, 'getSleepSamples').mockResolvedValue([
      { start: NIGHT, end: NIGHT + 4 * HOUR },
      { start: NIGHT + 4 * HOUR, end: NIGHT + 8 * HOUR },
    ]);
    const now = NIGHT + 40 * HOUR;

    await expect(importHealthSleep({ days: 30, now })).resolves.toEqual({ ok: true, nights: 1 });

    expect(query).toHaveBeenCalledWith(now - 30 * 24 * HOUR, now);
    expect(useStore.getState().sleeps).toHaveLength(2);
    expect(useStore.getState().healthSync).toMatchObject({
      importStatus: 'succeeded',
      importedCount: 1,
      lastMessage: 'Imported 1 night of sleep from Health.',
    });
  });

  it('records a failure without touching stored sleep', async () => {
    jest.spyOn(AppleHealth, 'getSleepSamples').mockRejectedValue(new Error('Locked'));

    await expect(
      importHealthSleep({ days: 14, failurePrefix: 'Health import failed.' }),
    ).resolves.toEqual({ ok: false, error: 'Locked' });

    expect(useStore.getState().healthSync).toMatchObject({
      importStatus: 'failed',
      lastMessage: 'Health import failed. Locked',
    });
  });
});
