import { Platform } from 'react-native';
import { requireNativeModule } from 'expo-modules-core';

export type SleepSample = { start: number; end: number; value?: number; label?: string };

let Native: any = null;
try {
  Native = requireNativeModule('HealthBridge');
} catch {
  Native = null;
}

function optionalRequire(name: string): any | null {
  try {
    const rq = eval('require');
    return rq(name);
  } catch {
    return null;
  }
}

function getHealthModule(): any | null {
  return optionalRequire('react-native-health') ?? optionalRequire('react-native-apple-healthkit');
}

function toMillis(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const ts = Date.parse(value);
    return Number.isNaN(ts) ? null : ts;
  }
  return null;
}

export function normalizeSleepSamples(rawSamples: unknown[]): SleepSample[] {
  return rawSamples
    .reduce<SleepSample[]>((acc, sample) => {
      const raw = sample as Record<string, unknown>;
      const start = toMillis(raw.start ?? raw.startDate);
      const end = toMillis(raw.end ?? raw.endDate);
      if (start === null || end === null || end <= start) {
        return acc;
      }
      acc.push({
        start,
        end,
        value: typeof raw.value === 'number' ? raw.value : undefined,
        label:
          typeof raw.label === 'string'
            ? raw.label
            : typeof raw.value === 'string'
              ? raw.value
              : undefined,
      });
      return acc;
    }, [])
    .sort((a, b) => b.end - a.end);
}

export async function isAvailable(): Promise<boolean> {
  if (Platform.OS !== 'ios') {
    return false;
  }
  try {
    if ((await Native?.isAvailable?.()) === true) {
      return true;
    }
  } catch {}
  return getHealthModule() !== null;
}

export async function requestAuthorization(): Promise<boolean> {
  try {
    if ((await Native?.requestAuthorization?.()) === true) {
      return true;
    }
  } catch {}

  const mod = getHealthModule();
  const client = mod?.default ?? mod;
  const initialize =
    client?.initHealthKit ??
    client?.initializeHealthKit;
  const permissions = client?.Constants?.Permissions ?? mod?.Constants?.Permissions ?? {};
  const sleepPermission =
    permissions.SleepAnalysis ??
    permissions.SleepAnalysisRead ??
    permissions.Sleep;

  if (typeof initialize !== 'function') {
    return false;
  }

  return new Promise((resolve) => {
    initialize(
      {
        permissions: {
          read: sleepPermission ? [sleepPermission] : [],
          write: [],
        },
      },
      (error: unknown) => resolve(!error)
    );
  });
}

export async function getSleepSamples(startMs: number, endMs: number): Promise<SleepSample[]> {
  try {
    const nativeSamples = await Native?.getSleepSamples?.(startMs, endMs);
    if (Array.isArray(nativeSamples)) {
      return normalizeSleepSamples(nativeSamples);
    }
  } catch {}

  const mod = getHealthModule();
  const client = mod?.default ?? mod;
  const getter = client?.getSleepSamples;
  if (typeof getter !== 'function') {
    return [];
  }

  return new Promise((resolve) => {
    getter(
      {
        startDate: new Date(startMs).toISOString(),
        endDate: new Date(endMs).toISOString(),
      },
      (error: unknown, results?: unknown[]) => {
        if (error || !Array.isArray(results)) {
          resolve([]);
          return;
        }
        resolve(normalizeSleepSamples(results));
      }
    );
  });
}

export default { isAvailable, requestAuthorization, getSleepSamples };
