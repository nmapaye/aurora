import type { Dose } from '~/domain/models';
import {
  acceptsQuickAdd,
  describeDose,
  displayDoseNote,
  doseSourceLabel,
  formatDoseDateTime,
  formatDoseTitle,
  getLoggedTodaySummary,
  getRecentDoses,
  isEditableDose,
  QUICK_ADD_REPEAT_GUARD_MS,
  quickAddConfirmation,
  RECENT_DOSE_LIMIT,
} from '~/features/caffeine/presentation';

const localTime = (year: number, month: number, day: number, hour = 0, minute = 0) =>
  new Date(year, month, day, hour, minute).getTime();
const clock = (ts: number) => `@${new Date(ts).getHours()}:${String(new Date(ts).getMinutes()).padStart(2, '0')}`;

describe('caffeine log presentation', () => {
  const now = localTime(2026, 8, 27, 15);

  describe('Logged Today', () => {
    it('states the recorded total and its source without any limit or remaining framing', () => {
      const doses: Dose[] = [
        { id: 'a', timestamp: localTime(2026, 8, 27, 8), mg: 95, source: 'Drip' },
        { id: 'b', timestamp: localTime(2026, 8, 27, 13, 5), mg: 60, source: 'Espresso' },
        { id: 'yesterday', timestamp: localTime(2026, 8, 26, 22), mg: 160 },
      ];

      const summary = getLoggedTodaySummary(doses, now, clock);

      expect(summary).toEqual({
        label: 'Logged Today',
        value: '155 mg',
        source: 'Manual',
        sample: false,
        detail: '2 entries · last at @13:05',
        accessibilityLabel: 'Logged Today, 155 mg, Manual, 2 entries · last at @13:05',
      });
      expect(JSON.stringify(summary)).not.toMatch(/remaining|limit|allowance|budget|left|safe/i);
    });

    it('labels sample-only and mixed days honestly', () => {
      const sample: Dose = { id: 'demo:dose:1', timestamp: localTime(2026, 8, 27, 9), mg: 80 };
      const manual: Dose = { id: 'm', timestamp: localTime(2026, 8, 27, 10), mg: 60 };

      expect(getLoggedTodaySummary([sample], now, clock)).toMatchObject({
        value: '80 mg',
        source: 'Sample Data',
        sample: true,
      });
      expect(getLoggedTodaySummary([sample, manual], now, clock)).toMatchObject({
        value: '140 mg',
        source: 'Manual and Sample Data',
        sample: true,
      });
    });

    it('reads as nothing logged, with no source, on an empty day', () => {
      expect(getLoggedTodaySummary([], now, clock)).toEqual({
        label: 'Logged Today',
        value: '0 mg',
        sample: false,
        detail: 'Nothing logged yet today.',
        accessibilityLabel: 'Logged Today, 0 mg, Nothing logged yet today.',
      });
    });
  });

  describe('Recent entries', () => {
    it('lists the newest entries first, capped to a short list', () => {
      const doses: Dose[] = Array.from({ length: RECENT_DOSE_LIMIT + 2 }, (_, index) => ({
        id: `d${index}`,
        timestamp: localTime(2026, 8, 20 + index, 9),
        mg: 50 + index,
      }));

      const recent = getRecentDoses(doses);

      expect(recent).toHaveLength(RECENT_DOSE_LIMIT);
      expect(recent[0].id).toBe(`d${RECENT_DOSE_LIMIT + 1}`);
      expect(recent.map((dose) => dose.timestamp)).toEqual(
        [...recent.map((dose) => dose.timestamp)].sort((a, b) => b - a),
      );
    });

    it('formats a full local date and time, not a bare clock time', () => {
      const formatted = formatDoseDateTime(localTime(2026, 8, 21, 7, 30));

      expect(formatted).toMatch(/2026/);
      expect(formatted).toMatch(/21/);
      expect(formatted).toMatch(/7:30/);
    });

    it('treats manual entries as editable and sample entries as read-only', () => {
      expect(isEditableDose({ id: 'abc-123' })).toBe(true);
      expect(doseSourceLabel({ id: 'abc-123' })).toBe('Manual');
      expect(isEditableDose({ id: 'demo:dose:3' })).toBe(false);
      expect(doseSourceLabel({ id: 'demo:dose:3' })).toBe('Sample Data');
    });

    it('skips only the stored sample-data note, never a genuine note', () => {
      expect(displayDoseNote({ id: 'demo:dose:0', note: 'Sample data' })).toBeUndefined();
      expect(displayDoseNote({ id: 'demo:dose:0', note: ' sample DATA ' })).toBeUndefined();
      expect(displayDoseNote({ id: 'demo:dose:0', note: 'Iced' })).toBe('Iced');
      expect(displayDoseNote({ id: 'abc-123', note: 'Sample data' })).toBe('Sample data');
      expect(displayDoseNote({ id: 'abc-123', note: 'Before class' })).toBe('Before class');
      expect(displayDoseNote({ id: 'abc-123', note: '   ' })).toBeUndefined();
      expect(displayDoseNote({ id: 'abc-123' })).toBeUndefined();
    });

    it('describes one entry fully for VoiceOver', () => {
      const format = () => 'Sun, Sep 27, 2026, 9:41 AM';

      expect(describeDose({ id: 'x', timestamp: 0, mg: 60, source: 'Espresso', note: 'Before class' }, format)).toBe(
        '60 mg, Espresso, Sun, Sep 27, 2026, 9:41 AM, Manual, Note: Before class',
      );
      expect(describeDose({ id: 'demo:dose:0', timestamp: 0, mg: 80 }, format)).toBe(
        '80 mg, Sun, Sep 27, 2026, 9:41 AM, Sample Data, read-only',
      );
      expect(describeDose({ id: 'demo:dose:0', timestamp: 0, mg: 80, note: 'Sample data' }, format)).toBe(
        '80 mg, Sun, Sep 27, 2026, 9:41 AM, Sample Data, read-only',
      );
      expect(formatDoseTitle({ mg: 80 })).toBe('80 mg');
      expect(formatDoseTitle({ mg: 95, source: 'Drip' })).toBe('95 mg · Drip');
    });
  });

  describe('quick add safety', () => {
    it('ignores an accidental double tap but accepts a deliberate second drink', () => {
      expect(acceptsQuickAdd(undefined, now)).toBe(true);
      expect(acceptsQuickAdd(now, now)).toBe(false);
      expect(acceptsQuickAdd(now, now + QUICK_ADD_REPEAT_GUARD_MS - 1)).toBe(false);
      expect(acceptsQuickAdd(now, now + QUICK_ADD_REPEAT_GUARD_MS)).toBe(true);
      // A clock that moved backwards never blocks logging.
      expect(acceptsQuickAdd(now, now - 5_000)).toBe(true);
    });

    it('confirms what was logged and when', () => {
      expect(quickAddConfirmation({ mg: 60, source: 'Espresso', timestamp: localTime(2026, 8, 27, 9, 41) }, clock)).toBe(
        'Logged Espresso, 60 mg at @9:41.',
      );
    });
  });
});
