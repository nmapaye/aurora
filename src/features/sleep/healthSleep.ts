import type { SleepSession } from '~/domain/models';

const LEGACY_HEALTH_SLEEP_ID = /^sleep:(-?\d+(?:\.\d+)?):(-?\d+(?:\.\d+)?)$/;

export function makeHealthSleepSessionId(
  sample: Pick<SleepSession, 'start' | 'end'>,
): string {
  return `healthkit:sleep:${Math.round(sample.start)}:${Math.round(sample.end)}`;
}

function isBoundaryEquivalentLegacyHealthSession(session: SleepSession) {
  const match = LEGACY_HEALTH_SLEEP_ID.exec(session.id);
  if (!match) return false;
  return (
    Number(match[1]) === session.start &&
    Number(match[2]) === session.end
  );
}

export function normalizeHealthSleepSessionIdentity(
  session: SleepSession,
): SleepSession {
  if (
    session.id.startsWith('healthkit:sleep:') ||
    isBoundaryEquivalentLegacyHealthSession(session)
  ) {
    return {
      ...session,
      id: makeHealthSleepSessionId(session),
    };
  }
  return session;
}

export function normalizeHealthSleepSessionIdentities(
  sessions: readonly SleepSession[],
): SleepSession[] {
  const deduped = new Map<string, SleepSession>();
  sessions.forEach((session) => {
    const normalized = normalizeHealthSleepSessionIdentity(session);
    deduped.set(normalized.id, normalized);
  });
  return [...deduped.values()];
}
