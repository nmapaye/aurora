import type { Dose, SleepSession } from '~/domain/models';
import type { VigilanceSession } from '~/domain/vigilance';

export const HEALTH_SLEEP_RETENTION_DAYS = 180;
const DAY_MS = 24 * 60 * 60 * 1000;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function isId(value: unknown): value is string {
  return typeof value === 'string' && value.length > 0;
}

export function isDose(value: unknown): value is Dose {
  return (
    isRecord(value) &&
    isId(value.id) &&
    isFiniteNumber(value.timestamp) &&
    isFiniteNumber(value.mg) &&
    value.mg >= 0
  );
}

export function isSleepSession(value: unknown): value is SleepSession {
  return (
    isRecord(value) &&
    isId(value.id) &&
    isFiniteNumber(value.start) &&
    isFiniteNumber(value.end) &&
    value.end > value.start &&
    (value.type === 'sleep' || value.type === 'nap')
  );
}

export function isVigilanceSession(value: unknown): value is VigilanceSession {
  return (
    isRecord(value) &&
    isId(value.id) &&
    isFiniteNumber(value.startedAt) &&
    isFiniteNumber(value.completedAt) &&
    isFiniteNumber(value.score) &&
    typeof value.rating === 'string'
  );
}

/** Keeps only well-formed items; anything else in storage is dropped. */
export function validItems<T>(value: unknown, guard: (item: unknown) => item is T): T[] {
  return Array.isArray(value) ? value.filter(guard) : [];
}

export function isHealthSleepId(id: string) {
  return id.startsWith('healthkit:sleep:');
}

/**
 * Health-imported sleep is a cache of data that stays in Apple Health, so it is
 * trimmed to a rolling window. Manual and sample entries are the user's own
 * records and are never trimmed.
 */
export function withinHealthRetention(
  sleeps: readonly SleepSession[],
  now = Date.now(),
): SleepSession[] {
  const oldest = now - HEALTH_SLEEP_RETENTION_DAYS * DAY_MS;
  return sleeps.filter((sleep) => !isHealthSleepId(sleep.id) || sleep.end >= oldest);
}
