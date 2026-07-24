import {
  createManualSleepId,
  createManualSleepDraft,
  isManualSleep,
  validateManualSleep,
} from '~/features/sleep/manualSleep';

const now = Date.parse('2026-07-24T12:00:00.000Z');

describe('manual sleep helpers', () => {
  it('creates an eight-hour draft ending now', () => {
    expect(createManualSleepDraft(now)).toEqual({
      start: now - 8 * 60 * 60 * 1000,
      end: now,
      note: '',
    });
  });

  it.each([
    [{ start: now, end: now }, 'Start time must be before end time.'],
    [{ start: now + 1, end: now }, 'Start time must be before end time.'],
    [{ start: now - 24 * 60 * 60 * 1000 - 1, end: now }, 'Sleep duration cannot exceed 24 hours.'],
    [{ start: now - 8 * 60 * 60 * 1000, end: now + 1 }, 'End time cannot be in the future.'],
  ])('rejects an invalid draft %#', (draft, message) => {
    expect(validateManualSleep({ ...draft, note: '' }, now)).toEqual({ valid: false, message });
  });

  it('accepts an exactly 24-hour session ending now', () => {
    expect(
      validateManualSleep(
        { start: now - 24 * 60 * 60 * 1000, end: now, note: 'Long flight' },
        now,
      ),
    ).toEqual({ valid: true });
  });

  it('uses stable manual IDs and distinguishes manual sessions', () => {
    expect(createManualSleepId(1234, 'abc')).toBe('manual:sleep:1234:abc');
    expect(isManualSleep('manual:sleep:1234:abc')).toBe(true);
    expect(isManualSleep('healthkit:sleep:1234:abc')).toBe(false);
  });
});
