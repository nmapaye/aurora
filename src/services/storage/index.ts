import { MMKV } from 'react-native-mmkv';
export const kv = new MMKV({ id: 'aurora' });

export const saveJSON = (key: string, value: unknown) => {
  kv.set(key, JSON.stringify(value));
};

export const loadJSON = <T>(key: string, fallback: T): T => {
  const raw = kv.getString(key);
  if (!raw) return fallback;
  try { return JSON.parse(raw) as T; } catch { return fallback; }
};
