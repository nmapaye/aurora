import { Platform } from 'react-native';
import { requireNativeModule } from 'expo-modules-core';

export type SleepSample = {
  start: number;
  end: number;
  value?: number;
  label?: string;
};

type NativeHealthBridge = {
  isAvailable?: () => boolean | Promise<boolean>;
  requestAuthorization?: () => boolean | Promise<boolean>;
  getSleepSamples?: (
    startMs: number,
    endMs: number,
  ) => unknown[] | Promise<unknown[]>;
};

type HealthKitPermissions = Record<string, unknown>;
type HealthKitAuthorizationOptions = {
  permissions: {
    read: unknown[];
    write: unknown[];
  };
};
type HealthKitInitialize = (
  options: HealthKitAuthorizationOptions,
  callback: (error: unknown) => void,
) => void;
type HealthKitSleepGetter = (
  options: { startDate: string; endDate: string },
  callback: (error: unknown, results?: unknown[]) => void,
) => void;
type HealthKitClient = {
  initHealthKit?: HealthKitInitialize;
  initializeHealthKit?: HealthKitInitialize;
  getSleepSamples?: HealthKitSleepGetter;
  Constants?: { Permissions?: HealthKitPermissions };
};
type HealthKitModule = HealthKitClient & {
  default?: HealthKitClient;
};

let Native: NativeHealthBridge | null = null;
try {
  Native = requireNativeModule<NativeHealthBridge>('HealthBridge');
} catch {
  Native = null;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function optionalRequire(name: string): unknown | null {
  try {
    const rq = eval('require') as (moduleName: string) => unknown;
    return rq(name);
  } catch {
    return null;
  }
}

function toHealthKitClient(value: unknown): HealthKitClient | null {
  if (!isRecord(value)) {
    return null;
  }

  const constants = isRecord(value.Constants) ? value.Constants : undefined;
  const permissions =
    constants && isRecord(constants.Permissions)
      ? constants.Permissions
      : undefined;

  return {
    initHealthKit:
      typeof value.initHealthKit === 'function'
        ? (value.initHealthKit as HealthKitInitialize)
        : undefined,
    initializeHealthKit:
      typeof value.initializeHealthKit === 'function'
        ? (value.initializeHealthKit as HealthKitInitialize)
        : undefined,
    getSleepSamples:
      typeof value.getSleepSamples === 'function'
        ? (value.getSleepSamples as HealthKitSleepGetter)
        : undefined,
    Constants: permissions ? { Permissions: permissions } : undefined,
  };
}

function toHealthKitModule(value: unknown): HealthKitModule | null {
  const client = toHealthKitClient(value);
  if (!client || !isRecord(value)) {
    return null;
  }

  const defaultClient = toHealthKitClient(value.default);
  return defaultClient ? { ...client, default: defaultClient } : client;
}

function getHealthModule(): HealthKitModule | null {
  return (
    toHealthKitModule(optionalRequire('react-native-health')) ??
    toHealthKitModule(optionalRequire('react-native-apple-healthkit'))
  );
}

function toMillis(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const trimmed = value.trim();
    if (trimmed === '') {
      return null;
    }
    const numeric = Number(trimmed);
    if (Number.isFinite(numeric)) {
      return numeric;
    }
    const ts = Date.parse(trimmed);
    return Number.isNaN(ts) ? null : ts;
  }
  return null;
}

function firstMillis(...values: unknown[]): number | null {
  for (const value of values) {
    const millis = toMillis(value);
    if (millis !== null) {
      return millis;
    }
  }
  return null;
}

function toLabel(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() !== '' ? value : undefined;
}

export function normalizeSleepSamples(rawSamples: unknown[]): SleepSample[] {
  const seen = new Set<string>();
  return rawSamples
    .reduce<SleepSample[]>((acc, sample) => {
      if (!isRecord(sample)) {
        return acc;
      }

      const start = firstMillis(sample.start, sample.startDate);
      const end = firstMillis(sample.end, sample.endDate);
      if (start === null || end === null || end <= start) {
        return acc;
      }
      const key = makeHealthSleepSessionId({ start, end });
      if (seen.has(key)) {
        return acc;
      }
      seen.add(key);
      acc.push({
        start,
        end,
        value:
          typeof sample.value === 'number' && Number.isFinite(sample.value)
            ? sample.value
            : undefined,
        label: toLabel(sample.label) ?? toLabel(sample.value),
      });
      return acc;
    }, [])
    .sort((a, b) => b.end - a.end);
}

export function makeHealthSleepSessionId(sample: Pick<SleepSample, 'start' | 'end'>): string {
  return `healthkit:sleep:${Math.round(sample.start)}:${Math.round(sample.end)}`;
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
  const initialize = client?.initHealthKit ?? client?.initializeHealthKit;
  const permissions =
    client?.Constants?.Permissions ?? mod?.Constants?.Permissions;
  const sleepPermission =
    permissions?.SleepAnalysis ??
    permissions?.SleepAnalysisRead ??
    permissions?.Sleep;

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
      (error: unknown) => resolve(!error),
    );
  });
}

export async function getSleepSamples(
  startMs: number,
  endMs: number,
): Promise<SleepSample[]> {
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
      },
    );
  });
}

export default { isAvailable, requestAuthorization, getSleepSamples };
