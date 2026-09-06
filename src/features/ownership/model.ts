import { addCalendarDays, localDateKey } from '~/utils/calendar';
import {
  nextScheduledSleep,
  scheduledSleep,
  type SleepRoutines,
} from '~/features/sleep/upgrades';
export const SUMMARY_CARDS = [
  'caffeine',
  'active-caffeine',
  'sleep',
  'vigilance',
  'cutoff',
] as const;
export type SummaryCard = (typeof SUMMARY_CARDS)[number];
export type ReminderKind = 'cutoff' | 'windDown' | 'checkIn' | 'weeklyReview';
export const REMINDER_KINDS: ReminderKind[] = [
  'cutoff',
  'windDown',
  'checkIn',
  'weeklyReview',
];
export type OwnershipState = {
  summary: { order: SummaryCard[]; hidden: SummaryCard[] };
  reminders: {
    cutoff: { weekdays: number[] };
    windDown: { weekdays: number[] };
    checkIn: { enabled: boolean; minute: number; weekdays: number[] };
    weeklyReview: { enabled: boolean; minute: number; weekdays: number[] };
    quiet: { enabled: boolean; start: number; end: number };
  };
};
const allDays = () => [0, 1, 2, 3, 4, 5, 6];
export const defaultOwnership = (): OwnershipState => ({
  summary: { order: [...SUMMARY_CARDS], hidden: [] },
  reminders: {
    cutoff: { weekdays: allDays() },
    windDown: { weekdays: allDays() },
    checkIn: { enabled: false, minute: 840, weekdays: allDays() },
    weeklyReview: { enabled: false, minute: 1080, weekdays: [0] },
    quiet: { enabled: false, start: 1320, end: 420 },
  },
});
const record = (v: unknown): Record<string, unknown> =>
  v && typeof v === 'object' && !Array.isArray(v)
    ? (v as Record<string, unknown>)
    : {};
const minute = (v: unknown, fallback: number) =>
  typeof v === 'number' && Number.isInteger(v) && v >= 0 && v < 1440
    ? v
    : fallback;
const days = (v: unknown, fallback: number[]) =>
  Array.isArray(v)
    ? [
        ...new Set(
          v.filter((x): x is number => Number.isInteger(x) && x >= 0 && x <= 6),
        ),
      ]
    : fallback;
export function normalizeOwnership(value: unknown): OwnershipState {
  const d = defaultOwnership(),
    v = record(value),
    s = record(v.summary),
    r = record(v.reminders);
  const cards = (x: unknown) =>
    Array.isArray(x)
      ? [
          ...new Set(
            x.filter((v): v is SummaryCard => SUMMARY_CARDS.includes(v)),
          ),
        ]
      : [];
  d.summary.order = [
    ...cards(s.order),
    ...SUMMARY_CARDS.filter((x) => !cards(s.order).includes(x)),
  ];
  d.summary.hidden = cards(s.hidden);
  for (const key of REMINDER_KINDS) {
    const item = record(r[key]);
    d.reminders[key].weekdays = days(item.weekdays, d.reminders[key].weekdays);
  }
  for (const key of ['checkIn', 'weeklyReview'] as const) {
    const item = record(r[key]);
    d.reminders[key].enabled = item.enabled === true;
    d.reminders[key].minute = minute(item.minute, d.reminders[key].minute);
  }
  const q = record(r.quiet);
  d.reminders.quiet = {
    enabled: q.enabled === true,
    start: minute(q.start, 1320),
    end: minute(q.end, 420),
  };
  return d;
}
export function visibleSummaryCards(
  state: OwnershipState,
  walkthrough: boolean,
): SummaryCard[] {
  return walkthrough
    ? [...SUMMARY_CARDS]
    : state.summary.order.filter((x) => !state.summary.hidden.includes(x));
}
export type PlannedReminder = {
  id: string;
  kind: ReminderKind;
  at: number;
  title: string;
  body: string;
};
export function reminderPlan(
  state: OwnershipState,
  routines: SleepRoutines,
  prefs: { notifyCutoff: boolean; cutoffHour: number },
  now: number,
): PlannedReminder[] {
  const reminders: PlannedReminder[] = [];
  const q = state.reminders.quiet;
  for (let day = 0; day < 14; day++) {
    const date = addCalendarDays(now, day);
    for (const kind of REMINDER_KINDS) {
      if (
        kind === 'cutoff'
          ? !prefs.notifyCutoff
          : kind === 'windDown'
            ? !routines.windDown.enabled
            : !state.reminders[kind].enabled
      )
        continue;
      const atDate = new Date(date);
      const schedule = scheduledSleep(routines, localDateKey(date));
      let at: number;
      if (kind === 'windDown')
        at = schedule.bedtime - routines.windDown.leadMinutes * 60000;
      else {
        const m =
          kind === 'cutoff'
            ? prefs.cutoffHour * 60
            : state.reminders[kind].minute;
        atDate.setHours(Math.floor(m / 60), m % 60, 0, 0);
        at = atDate.getTime();
      }
      const fire = new Date(at),
        m = fire.getHours() * 60 + fire.getMinutes();
      if (at <= now || !state.reminders[kind].weekdays.includes(fire.getDay()))
        continue;
      if (
        q.enabled &&
        (q.start === q.end ||
          (q.start < q.end
            ? m >= q.start && m < q.end
            : m >= q.start || m < q.end))
      )
        continue;
      const bedtime = nextScheduledSleep(routines, at).bedtime;
      const content = {
        cutoff: [
          'Caffeine cutoff',
          `Your chosen caffeine cutoff. Planned bedtime ${new Date(bedtime).toLocaleString()}.`,
        ],
        windDown: [
          'Time to wind down',
          `Planned bedtime ${new Date(schedule.bedtime).toLocaleString()}.`,
        ],
        checkIn: [
          'Alertness check-in',
          'Open Aurora to record how alert you feel.',
        ],
        weeklyReview: [
          'Your weekly review',
          'Open Aurora to review your recorded week.',
        ],
      }[kind];
      reminders.push({
        id: `aurora-reminder:${kind}:${day}`,
        kind,
        at,
        title: content[0],
        body: content[1],
      });
    }
  }
  return reminders.sort((a, b) => a.at - b.at);
}
