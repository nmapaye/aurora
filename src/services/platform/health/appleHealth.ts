import { Platform } from 'react-native';
import { requireNativeModule } from 'expo-modules-core';
import { makeHealthSleepSessionId } from '~/features/sleep/healthSleep';

export { makeHealthSleepSessionId } from '~/features/sleep/healthSleep';

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
type HealthKitAvailability = (
  callback: (error: unknown, available: boolean) => void,
) => void;
type HealthKitClient = {
  isAvailable?: HealthKitAvailability;
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
    isAvailable:
      typeof value.isAvailable === 'function'
        ? (value.isAvailable as HealthKitAvailability)
        : undefined,
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
  try {
    // Metro must see the literal dependency to include it in release bundles.
    // Expo Go exposes constants without native methods, checked by isAvailable.
    return toHealthKitModule(require('react-native-health'));
  } catch {
    return null;
  }
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

function isSleepCategory(sample: Record<string, unknown>): boolean {
  const category = toLabel(sample.label) ?? sample.value;
  // The optional custom bridge can provide already-filtered, unlabelled sleep.
  if (category === undefined || category === null) {
    return true;
  }
  if (typeof category === 'number') {
    // HealthKit: asleep (1), core (3), deep (4), REM (5).
    return [1, 3, 4, 5].includes(category);
  }
  if (typeof category === 'string') {
    return [
      'ASLEEP',
      'ASLEEP_UNSPECIFIED',
      'CORE',
      'DEEP',
      'REM',
      'ASLEEP_CORE',
      'ASLEEP_DEEP',
      'ASLEEP_REM',
    ].includes(category.trim().toUpperCase());
  }
  return false;
}

export function normalizeSleepSamples(rawSamples: unknown[]): SleepSample[] {
  const seen = new Set<string>();
  return rawSamples
    .reduce<SleepSample[]>((acc, sample) => {
      if (!isRecord(sample) || !isSleepCategory(sample)) {
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

export async function getNativeSleepSamples(
  query: (startMs: number, endMs: number) => unknown | Promise<unknown>,
  startMs: number,
  endMs: number,
): Promise<SleepSample[]> {
  const samples = await query(startMs, endMs);
  if (!Array.isArray(samples)) {
    throw new Error('Health sleep query returned an invalid payload.');
  }
  return normalizeSleepSamples(samples);
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
  const mod = getHealthModule();
  const client = mod?.default ?? mod;
  const checkAvailability = client?.isAvailable;
  if (
    typeof checkAvailability !== 'function' ||
    typeof (client?.initHealthKit ?? client?.initializeHealthKit) !==
      'function' ||
    typeof client?.getSleepSamples !== 'function'
  ) {
    return false;
  }
  return new Promise((resolve) => {
    try {
      checkAvailability((error, available) =>
        resolve(!error && available === true),
      );
    } catch {
      resolve(false);
    }
  });
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

  if (typeof initialize !== 'function' || !sleepPermission) {
    return false;
  }

  return new Promise((resolve) => {
    initialize(
      {
        permissions: {
          read: [sleepPermission],
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
  if (Native?.getSleepSamples) {
    return getNativeSleepSamples(Native.getSleepSamples, startMs, endMs);
  }

  const mod = getHealthModule();
  const client = mod?.default ?? mod;
  const getter = client?.getSleepSamples;
  if (typeof getter !== 'function') {
    throw new Error('Apple Health is unavailable in this build.');
  }

  return new Promise((resolve, reject) => {
    getter(
      {
        startDate: new Date(startMs).toISOString(),
        endDate: new Date(endMs).toISOString(),
      },
      (error: unknown, results?: unknown[]) => {
        if (error) {
          reject(
            error instanceof Error
              ? error
              : new Error('Health sleep query failed.'),
          );
          return;
        }
        if (!Array.isArray(results)) {
          reject(new Error('Health sleep query returned an invalid payload.'));
          return;
        }
        resolve(normalizeSleepSamples(results));
      },
    );
  });
}

export default { isAvailable, requestAuthorization, getSleepSamples };
