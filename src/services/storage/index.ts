import { MMKV } from 'react-native-mmkv';

// Provide a safe fallback when MMKV 3.x cannot initialize (e.g., new architecture disabled)
type KVLike = { getString(key: string): string | undefined; set(key: string, value: string): void; delete?(key: string): void };

let nativeKv: MMKV | null = null;
let fallbackMap: Map<string, string> | null = null;
let usingFallback = false;

try {
  nativeKv = new MMKV({ id: 'aurora' });
} catch (e) {
  // Gracefully degrade to in-memory storage so the app can run
  usingFallback = true;
  fallbackMap = new Map<string, string>();
  // eslint-disable-next-line no-console
  console.warn('[storage] MMKV unavailable; using in-memory fallback. Data will not persist.');
}

export const kv: KVLike = nativeKv
  ? {
      getString: (k) => nativeKv!.getString(k) ?? undefined,
      set: (k, v) => nativeKv!.set(k, v),
      delete: (k) => {
        try { (nativeKv as any).delete?.(k); } catch { nativeKv!.set(k, ''); }
      },
    }
  : {
      getString: (k) => fallbackMap!.get(k),
      set: (k, v) => { fallbackMap!.set(k, v); },
      delete: (k) => { fallbackMap!.delete(k); },
    };

export function isUsingFallbackStorage() { return usingFallback; }

export const saveJSON = (key: string, value: unknown) => {
  kv.set(key, JSON.stringify(value));
};

export const loadJSON = <T>(key: string, fallback: T): T => {
  const raw = kv.getString(key);
  if (!raw) return fallback;
  try { return JSON.parse(raw) as T; } catch { return fallback; }
};

// Provide a generic storage backend for zustand persist
export const jsonStringStorage = {
  getItem: (name: string) => kv.getString(name) ?? null,
  setItem: (name: string, value: string) => { kv.set(name, value); },
  removeItem: (name: string) => { try { kv.delete?.(name); } catch { /* noop */ } },
};
