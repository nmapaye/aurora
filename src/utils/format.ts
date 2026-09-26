export const fmtMg=(x:number)=>`${Math.round(x)} mg`;

// Formats a whole hour (0-23) as a clock time in the device locale, e.g. "4:00 PM".
export function formatClockHour(hour: number) {
  const h = Math.max(0, Math.min(23, Math.round(hour)));
  return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' })
    .format(new Date(2026, 0, 1, h, 0));
}
