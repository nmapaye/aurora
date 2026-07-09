import { cutoffReminder } from '~/services/platform/notificationContent';

describe('cutoffReminder', () => {
  it('schedules at the cutoff hour on the hour', () => {
    const reminder = cutoffReminder(16);
    expect(reminder.hour).toBe(16);
    expect(reminder.minute).toBe(0);
    expect(reminder.body).toContain('16:00');
  });

  it('clamps out-of-range hours into 0-23', () => {
    expect(cutoffReminder(-2).hour).toBe(0);
    expect(cutoffReminder(27).hour).toBe(23);
  });

  it('rounds fractional hours', () => {
    expect(cutoffReminder(15.6).hour).toBe(16);
  });
});
