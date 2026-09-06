import { localDateKey, isLocalDateKey } from '~/utils/calendar';
import type { Dose } from '~/domain/models';
import { mgActive } from '~/domain/algorithm/caffeine';
import { getTodayCaffeineTotal, type CustomDoseDraft } from './logging';
import { CAFFEINE_PRESETS } from './presets';

export type PersonalDrink = {
  id: string;
  label: string;
  mg: number;
  archived: boolean;
};
export type CaffeineState = {
  drinks: PersonalDrink[];
  favoriteIds: string[];
  draft: CustomDoseDraft | null;
  zeroDays: string[];
};
export type DoseUndo = {
  before?: Dose;
  after?: Dose;
  expiresAt: number;
  zeroDays: string[];
};
export const defaultCaffeineState: CaffeineState = {
  drinks: [],
  favoriteIds: CAFFEINE_PRESETS.map((d) => d.id),
  draft: null,
  zeroDays: [],
};
export const localDayKey = localDateKey;

export function validDrink(drink: PersonalDrink) {
  return (
    typeof drink.id === 'string' &&
    drink.id.startsWith('personal:') &&
    typeof drink.label === 'string' &&
    drink.label.trim().length > 0 &&
    Number.isInteger(drink.mg) &&
    drink.mg >= 1 &&
    drink.mg <= 1999
  );
}
export function availableDrinks(state: CaffeineState) {
  return [
    ...CAFFEINE_PRESETS,
    ...state.drinks
      .filter((d) => !d.archived)
      .map((d) => ({ ...d, symbol: 'cup.and.saucer.fill' as const })),
  ];
}
export function favoriteDrinks(state: CaffeineState) {
  const drinks = availableDrinks(state);
  return state.favoriteIds.flatMap((id) => {
    const drink = drinks.find((d) => d.id === id);
    return drink ? [drink] : [];
  });
}
export function normalizeCaffeine(
  value?: Partial<CaffeineState>,
): CaffeineState {
  const drinks = Array.isArray(value?.drinks)
    ? value.drinks
        .filter((d) => d && validDrink(d))
        .map((d) => ({
          ...d,
          label: d.label.trim(),
          archived: d.archived === true,
        }))
    : [];
  const uniqueDrinks = [...new Map(drinks.map((d) => [d.id, d])).values()];
  const available = availableDrinks({
    ...defaultCaffeineState,
    drinks: uniqueDrinks,
  });
  const draft = value?.draft;
  return {
    drinks: uniqueDrinks,
    favoriteIds: Array.isArray(value?.favoriteIds)
      ? [
          ...new Set(
            value.favoriteIds.filter((id) =>
              available.some((d) => d.id === id),
            ),
          ),
        ]
      : [...defaultCaffeineState.favoriteIds],
    draft:
      draft &&
      typeof draft.mg === 'string' &&
      typeof draft.source === 'string' &&
      typeof draft.note === 'string' &&
      Number.isFinite(draft.timestamp) &&
      Number.isFinite(new Date(draft.timestamp).getTime()) &&
      (draft.editingId === undefined ||
        (typeof draft.editingId === 'string' &&
          !draft.editingId.startsWith('demo:')))
        ? draft
        : null,
    zeroDays: Array.isArray(value?.zeroDays)
      ? [
          ...new Set(
            value.zeroDays.filter(
              (d) => typeof d === 'string' && isLocalDateKey(d),
            ),
          ),
        ]
      : [],
  };
}
export function calculateServing(
  mode: 'servings' | 'volume',
  caffeine: string,
  quantity: string,
  referenceVolume: string,
) {
  const a = Number(caffeine),
    b = Number(quantity),
    c = Number(referenceVolume);
  if (
    !Number.isFinite(a) ||
    !Number.isFinite(b) ||
    a <= 0 ||
    b <= 0 ||
    (mode === 'volume' && (!Number.isFinite(c) || c <= 0))
  )
    return null;
  const result = Math.round(mode === 'servings' ? a * b : (a * b) / c);
  return result >= 1 && result <= 1999 ? result : null;
}
export type DoseFilter = {
  query?: string;
  source?: string;
  minMg?: number;
  maxMg?: number;
  start?: number;
  end?: number;
};
export function filterDoses(doses: readonly Dose[], f: DoseFilter) {
  const query = f.query?.trim().toLowerCase() ?? '';
  return doses
    .filter(
      (d) =>
        (!query ||
          `${d.source ?? ''} ${d.note ?? ''} ${d.mg}`
            .toLowerCase()
            .includes(query)) &&
        (!f.source || d.source === f.source) &&
        d.mg >= (f.minMg ?? 0) &&
        d.mg <= (f.maxMg ?? Infinity) &&
        d.timestamp >= (f.start ?? -Infinity) &&
        d.timestamp <= (f.end ?? Infinity),
    )
    .sort((a, b) => b.timestamp - a.timestamp);
}
export function previewDose(
  doses: readonly Dose[],
  draft: Dose,
  bedtime: number,
  halfLife: number,
  replacingId?: string,
) {
  const next = [
    ...doses.filter((d) => !d.id.startsWith('demo:') && d.id !== replacingId),
    draft,
  ];
  return {
    dailyTotal: getTodayCaffeineTotal(next, draft.timestamp),
    bedtimeMg: mgActive(bedtime, next, halfLife),
  };
}
export function applyDoseUndo(
  doses: Dose[],
  undo: DoseUndo | null,
  now: number,
) {
  if (!undo || now >= undo.expiresAt) return doses;
  const id = undo.after?.id ?? undo.before?.id;
  const current = doses.find((d) => d.id === id);
  if (JSON.stringify(current) !== JSON.stringify(undo.after)) return doses;
  return undo.before
    ? [...doses.filter((d) => d.id !== id), undo.before].sort(
        (a, b) => b.timestamp - a.timestamp,
      )
    : doses.filter((d) => d.id !== id);
}
