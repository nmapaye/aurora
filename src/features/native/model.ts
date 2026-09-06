import type { State } from '~/state/store';
import {
  availableDrinks,
  type CaffeineState,
} from '~/features/caffeine/upgrades';
import type { CustomDoseDraft } from '~/features/caffeine/logging';
import { mgActive } from '~/domain/algorithm/caffeine';
import { nextScheduledSleep } from '~/features/sleep/upgrades';
import {
  localDateKey,
  addCalendarDays,
  startOfLocalDay,
} from '~/utils/calendar';

export type NativeSnapshot = {
  version: 1;
  generatedAt: number;
  expiresAt: number;
  localDay: string;
  timezoneOffsetMinutes: number;
  loggedMg: number | null;
  activeMg: number | null;
  nextBedtime: number | null;
  cutoff: number | null;
  showLockValues: boolean;
  drinks: { id: string; name: string; mg: number }[];
};
export function buildNativeSnapshot(
  state: Pick<
    State,
    | 'doses'
    | 'caffeine'
    | 'prefs'
    | 'sleepRoutines'
    | 'onboarding'
    | 'ownership'
  >,
  now: number,
): NativeSnapshot {
  const localDay = localDateKey(now);
  const personal = state.doses.filter(
    (d) => !d.id.startsWith('demo:') && d.timestamp <= now,
  );
  const today = personal.filter((d) => localDateKey(d.timestamp) === localDay);
  const known = today.length > 0 || state.caffeine.zeroDays.includes(localDay);
  const available = state.onboarding.completed;
  const cutoff = new Date(now);
  cutoff.setHours(state.prefs.cutoffHour, 0, 0, 0);
  if (cutoff.getTime() <= now) cutoff.setDate(cutoff.getDate() + 1);
  const bedtime = nextScheduledSleep(state.sleepRoutines, now).bedtime;
  return {
    version: 1,
    generatedAt: now,
    expiresAt: Math.min(
      now + 15 * 60000,
      addCalendarDays(startOfLocalDay(now), 1),
      cutoff.getTime(),
      bedtime,
    ),
    localDay,
    timezoneOffsetMinutes: new Date(now).getTimezoneOffset(),
    loggedMg:
      available && known ? today.reduce((sum, d) => sum + d.mg, 0) : null,
    activeMg:
      available && (known || personal.length > 0)
        ? mgActive(now, personal, state.prefs.halfLife)
        : null,
    nextBedtime: available ? bedtime : null,
    cutoff: available ? cutoff.getTime() : null,
    showLockValues: state.ownership.native?.showLockValues === true,
    drinks: available
      ? availableDrinks(state.caffeine).map((d) => ({
          id: d.id,
          name: d.label,
          mg: d.mg,
        }))
      : [],
  };
}
export type NativeAction =
  | { kind: 'log'; drinkId: string }
  | { kind: 'log'; amount: number }
  | { kind: 'nap' }
  | { kind: 'summary' };
export function parseNativeAction(url: string): NativeAction | null {
  if (url.length > 2048) return null;
  try {
    const match = /^aurora:\/\/native\/(log|nap|summary)(?:\?([^#]*))?$/.exec(
      url,
    );
    if (!match) return null;
    const [, kind, query] = match;
    if (kind !== 'log')
      return query === undefined ? { kind: kind as 'nap' | 'summary' } : null;
    if (!query || query.includes('&')) return null;
    const pair = query.split('=');
    if (pair.length !== 2) return null;
    const key = decodeURIComponent(pair[0]),
      value = decodeURIComponent(pair[1]);
    if (
      key === 'drinkId' &&
      value.length > 0 &&
      value.length <= 200 &&
      !/[\x00-\x1f]/.test(value)
    )
      return { kind: 'log', drinkId: value };
    if (
      key === 'amount' &&
      /^[1-9]\d{0,3}$/.test(value) &&
      Number(value) <= 1999
    )
      return { kind: 'log', amount: Number(value) };
    return null;
  } catch {
    return null;
  }
}
export function resolveNativeDraft(
  action: NativeAction,
  caffeine: CaffeineState,
  now: number,
): CustomDoseDraft | null {
  if (action.kind !== 'log') return null;
  if ('amount' in action)
    return Number.isInteger(action.amount) &&
      action.amount >= 1 &&
      action.amount <= 1999
      ? {
          mg: String(action.amount),
          source: 'Shortcut',
          note: '',
          timestamp: now,
        }
      : null;
  const drink = availableDrinks(caffeine).find((d) => d.id === action.drinkId);
  return drink
    ? { mg: String(drink.mg), source: drink.label, note: '', timestamp: now }
    : null;
}
