import en from './en.json';
import id from './id.json';

type Dictionary = Record<string, string>;
type LocaleKey = 'en' | 'id';

const dictionaries: Record<LocaleKey, Dictionary> = {
  en,
  id,
};

let current: LocaleKey = 'en';

export const availableLocales: LocaleKey[] = ['en', 'id'];

/**
 * Set the active locale. Falls back to 'en' if unknown.
 * Accepts BCP-47 codes like 'id-ID' and maps to base language.
 */
export function setLocale(locale: string) {
  const norm = locale.toLowerCase();
  if (norm.startsWith('id')) current = 'id';
  else current = 'en';
}

export function getLocale(): LocaleKey {
  return current;
}

/**
 * Translate a key with optional {placeholders}.
 * Falls back to English, and finally to the key itself.
 */
export function t(key: string, vars?: Record<string, string | number>): string {
  const dict = dictionaries[current] || dictionaries.en;
  const tpl = (dict[key] ?? dictionaries.en[key] ?? key) as string;
  if (!vars) return tpl;
  return tpl.replace(/\{(\w+)\}/g, (_, k: string) => String(vars[k] ?? `{${k}}`));
}

/**
 * Helpers for locale-aware formatting using Intl.
 */
export function formatNumber(n: number, options?: Intl.NumberFormatOptions): string {
  try {
    return new Intl.NumberFormat(current, options).format(n);
  } catch {
    return String(n);
  }
}

export function formatDate(d: number | Date, options?: Intl.DateTimeFormatOptions): string {
  try {
    const date = typeof d === 'number' ? new Date(d) : d;
    return new Intl.DateTimeFormat(current, options).format(date);
  } catch {
    return String(d);
  }
}