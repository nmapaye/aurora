import React, { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Text, View, useColorScheme } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { InlineStatus, ListRow, SectionCard, SectionTitle, StatTile } from '~/components/ui';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import AppleHealth, { makeHealthSleepSessionId } from '~/services/platform/health/appleHealth';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';

type SleepSample = { start: number; end: number; type?: string };
type HealthConnectionState =
  | 'unavailable'
  | 'denied'
  | 'connected'
  | 'manual'
  | 'demo'
  | 'ready';

function fmtTime(ts?: number) {
  if (!ts) return '—';
  try {
    return new Intl.DateTimeFormat(undefined, {
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toLocaleTimeString();
  }
}

function fmtDate(ts?: number) {
  if (!ts) return '—';
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toDateString();
  }
}

function fmtDuration(ms: number) {
  const hours = Math.floor(ms / 3_600_000);
  const minutes = Math.round((ms % 3_600_000) / 60_000);
  return `${hours}h ${minutes}m`;
}

function pluralizeSamples(count: number) {
  return `${count} sleep sample${count === 1 ? '' : 's'}`;
}

export default function SleepScreen() {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const doses = useStore((state) => state.doses);
  const sleeps = useStore((state) => state.sleeps);
  const addDose = useStore((state) => state.addDose);
  const onboarding = useStore((state) => state.onboarding);
  const setOnboarding = useStore((state) => state.setOnboarding);
  const healthSync = useStore((state) => state.healthSync);
  const setHealthSync = useStore((state) => state.setHealthSync);
  const demoMode = useStore((state) => state.demoMode);
  const loadDemoData = useStore((state) => state.loadDemoData);
  const clearDemoData = useStore((state) => state.clearDemoData);
  const upsertSleepSessions = useStore((state) => state.upsertSleepSessions);
  const cutoff = useCaffeineCutoff();

  const [healthAvailable, setHealthAvailable] = useState<boolean | undefined>(undefined);
  const [healthAuthorized, setHealthAuthorized] = useState<boolean | undefined>(undefined);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | undefined>();

  useEffect(() => {
    let active = true;
    AppleHealth.isAvailable().then((available) => {
      if (active) {
        setHealthAvailable(available);
      }
    });
    return () => {
      active = false;
    };
  }, []);

  const todayTotals = useMemo(() => {
    const now = new Date();
    const key = (date: Date) =>
      `${date.getFullYear()}-${date.getMonth()}-${date.getDate()}`;
    const todayKey = key(now);
    let total = 0;
    for (const dose of doses) {
      if (key(new Date(dose.timestamp)) === todayKey) {
        total += dose.mg;
      }
    }
    return total;
  }, [doses]);

  const storedSleepSamples = useMemo<SleepSample[]>(
    () =>
      sleeps
        .map((sample) => ({
          start: sample.start,
          end: sample.end,
          type: sample.type,
        }))
        .sort((a, b) => b.end - a.end),
    [sleeps]
  );
  const lastSleep = storedSleepSamples[0];
  const wakeTime = lastSleep?.end;

  const plan = useMemo(() => {
    const budget = 200;
    if (!wakeTime || !cutoff?.nextCutoff) return [] as { t: number; mg: number; label: string }[];
    const start = Math.max(wakeTime + 30 * 60 * 1000, Date.now());
    const end = cutoff.nextCutoff;
    if (end <= start) return [];
    const windowHours = (end - start) / 3_600_000;
    const slots = Math.max(1, Math.min(3, Math.floor(windowHours / 3.5) + 1));
    const base = [80, 80, 40];
    const times: number[] = [];
    for (let index = 0; index < slots; index += 1) {
      const time = start + index * 3.5 * 3_600_000;
      if (time < end) times.push(time);
    }
    const remaining = Math.max(0, budget - todayTotals);
    const recommendations: { t: number; mg: number; label: string }[] = [];
    let used = 0;
    for (let index = 0; index < times.length; index += 1) {
      let mg = base[index] ?? 40;
      if (used + mg > remaining) {
        mg = Math.max(0, remaining - used);
      }
      if (mg < 20) break;
      used += mg;
      recommendations.push({
        t: times[index],
        mg,
        label: index === 0 ? 'Kickstart' : index === 1 ? 'Sustain' : 'Top-up',
      });
      if (used >= remaining) break;
    }
    return recommendations;
  }, [cutoff?.nextCutoff, todayTotals, wakeTime]);

  const connectHealth = async () => {
    setError(undefined);
    setLoading(true);
    try {
      const available = await AppleHealth.isAvailable();
      setHealthAvailable(available);
      if (!available) {
        setError('Health import is unavailable on this device.');
        setHealthAuthorized(false);
        setOnboarding({ source: 'manual', permissionStatus: 'unsupported' });
        setHealthSync({
          importedCount: 0,
          lastSyncedAt: Date.now(),
          lastMessage: 'Health is unavailable here. No sleep samples imported; manual logging and demo data remain available.',
        });
        return;
      }
      const ok = await AppleHealth.requestAuthorization();
      if (!ok) {
        setError('Authorization was not granted.');
        setHealthAuthorized(false);
        setOnboarding({ source: 'manual', permissionStatus: 'denied' });
        setHealthSync({
          importedCount: 0,
          lastSyncedAt: Date.now(),
          lastMessage: 'Health access was denied. No sleep samples imported; continue manually or use demo sample data.',
        });
        return;
      }
      setHealthAuthorized(true);
      const end = Date.now();
      const start = end - 3 * 24 * 3_600_000;
      const samples = await AppleHealth.getSleepSamples(start, end);
      const mapped: SleepSample[] = (samples || [])
        .map((sample) => ({
          start: sample.start,
          end: sample.end,
          type: sample.label,
        }))
        .filter((sample) => Number.isFinite(sample.start) && Number.isFinite(sample.end))
        .sort((a, b) => b.end - a.end);
      upsertSleepSessions(
        mapped.map((sample) => ({
          id: makeHealthSleepSessionId(sample),
          start: sample.start,
          end: sample.end,
          type: 'sleep' as const,
        }))
      );
      setHealthSync({
        importedCount: mapped.length,
        lastSyncedAt: Date.now(),
        lastMessage:
          mapped.length > 0
            ? `Imported ${pluralizeSamples(mapped.length)} from Health. Last sync completed.`
            : 'Health connected. Last sync completed with 0 imported sleep samples.',
      });
      setOnboarding({ source: 'healthkit', permissionStatus: 'granted' });
    } catch (nextError) {
      const message = nextError instanceof Error ? nextError.message : 'Failed to read sleep data.';
      setError(message);
      setHealthAuthorized(false);
      setOnboarding({ permissionStatus: 'denied' });
      setHealthSync({
        importedCount: 0,
        lastSyncedAt: Date.now(),
        lastMessage: `Health refresh failed. No sleep samples imported. ${message}`,
      });
    } finally {
      setLoading(false);
    }
  };

  const lastNightTotalMs = useMemo(() => {
    if (!storedSleepSamples.length) return 0;
    const referenceEnd = lastSleep?.end ?? storedSleepSamples[0]?.end;
    if (!referenceEnd) return 0;
    const windowEnd = new Date(referenceEnd);
    windowEnd.setHours(12, 0, 0, 0);
    const windowStart = new Date(windowEnd);
    windowStart.setDate(windowStart.getDate() - 1);
    windowStart.setHours(18, 0, 0, 0);
    const startMs = windowStart.getTime();
    const endMs = windowEnd.getTime();
    const isAsleep = (value?: string) => {
      if (!value) return false;
      const normalized = String(value).toUpperCase();
      return normalized.includes('ASLEEP') || normalized === 'SLEEP';
    };
    let total = 0;
    for (const sample of storedSleepSamples) {
      if (!isAsleep(sample.type)) continue;
      const start = Math.max(sample.start, startMs);
      const end = Math.min(sample.end, endMs);
      if (end > start) total += end - start;
    }
    return total;
  }, [lastSleep?.end, storedSleepSamples]);

  const sleepImpact = useMemo(() => {
    const pairs: { deltaMin: number; sleepMin: number }[] = [];
    for (const sample of storedSleepSamples) {
      const sleepStart = sample.start;
      const windowStart = sleepStart - 12 * 3_600_000;
      let latestDose: number | undefined;
      for (const dose of doses) {
        if (dose.timestamp <= sleepStart && dose.timestamp >= windowStart) {
          if (!latestDose || dose.timestamp > latestDose) {
            latestDose = dose.timestamp;
          }
        }
      }
      if (latestDose) {
        pairs.push({
          deltaMin: Math.round((sleepStart - latestDose) / 60_000),
          sleepMin: Math.round((sample.end - sample.start) / 60_000),
        });
      }
    }

    const median = (values: number[]) => {
      const sorted = [...values].sort((a, b) => a - b);
      return sorted.length ? sorted[Math.floor(sorted.length / 2)] : 0;
    };
    const percentile = (values: number[], q: number) => {
      const sorted = [...values].sort((a, b) => a - b);
      const index = Math.max(
        0,
        Math.min(sorted.length - 1, Math.round(q * (sorted.length - 1)))
      );
      return sorted[index] || 0;
    };

    const deltas = pairs.map((pair) => pair.deltaMin);
    const sleepDurations = pairs.map((pair) => pair.sleepMin);
    return {
      n: pairs.length,
      medianDeltaMin: median(deltas),
      p10: percentile(deltas, 0.1),
      p90: percentile(deltas, 0.9),
      showCorrelation: pairs.length >= 14,
      medianSleepMin: median(sleepDurations),
    };
  }, [doses, storedSleepSamples]);

  const addNow = (mg: number) => {
    addDose({
      id: `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`,
      timestamp: Date.now(),
      mg,
      source: 'Plan',
    });
  };

  const healthConnectionState: HealthConnectionState = demoMode
    ? 'demo'
    : healthAvailable === false || onboarding.permissionStatus === 'unsupported'
    ? 'unavailable'
    : onboarding.permissionStatus === 'denied' || healthAuthorized === false
    ? 'denied'
    : healthAuthorized || onboarding.permissionStatus === 'granted'
    ? 'connected'
    : onboarding.source === 'manual'
    ? 'manual'
    : 'ready';

  const healthStatus = loading
    ? 'Syncing Health'
    : healthConnectionState === 'demo'
    ? 'Demo data'
    : healthConnectionState === 'connected'
    ? 'Health connected'
    : healthConnectionState === 'denied'
    ? 'Health access denied'
    : healthConnectionState === 'manual'
    ? 'Manual mode'
    : healthConnectionState === 'unavailable'
    ? 'Health unavailable'
    : 'Ready to connect';

  const healthTone =
    error || healthConnectionState === 'denied'
      ? 'error'
      : healthConnectionState === 'demo'
      ? 'info'
      : healthConnectionState === 'connected'
      ? 'success'
      : healthConnectionState === 'ready'
      ? 'warning'
      : 'neutral';

  const healthDescription =
    healthConnectionState === 'demo'
      ? 'Aurora is showing deterministic demo sleep and caffeine data for screenshots and reviewer walkthroughs.'
      : healthConnectionState === 'connected'
      ? 'Aurora can refresh recent sleep from Health and update wake-time guidance from imported sessions.'
      : healthConnectionState === 'denied'
      ? 'Health access is denied. Manual logging stays available, and demo data can fill the screen for walkthroughs.'
      : healthConnectionState === 'manual'
      ? 'Aurora is using manual sleep logging. Connect Health any time to import sleep automatically.'
      : healthConnectionState === 'unavailable'
      ? 'Health import is unavailable on this device. Manual logging and demo data remain available.'
      : 'Aurora can read recent sleep from Health after you connect.';

  return (
    <AppScreen
      title="Sleep"
      subtitle="Connect Health, review last night, and keep your caffeine plan inside your recovery window."
    >
      <View style={{ gap: 16 }}>
        <SectionTitle>Connection</SectionTitle>
        <SectionCard>
          <InlineStatus tone={healthTone} text={healthStatus} />
          <Text
            style={{
              fontSize: 15,
              lineHeight: 20,
              color: palette.textSecondary,
            }}
          >
            {healthDescription}
          </Text>
          {healthSync.lastSyncedAt || healthSync.lastMessage ? (
            <View style={{ gap: 2 }}>
              <ListRow
                title="Imported"
                subtitle="Most recent Health refresh"
                value={pluralizeSamples(healthSync.importedCount)}
              />
              {healthSync.lastSyncedAt ? (
                <ListRow
                  title="Last sync"
                  subtitle={fmtDate(healthSync.lastSyncedAt)}
                  value={fmtTime(healthSync.lastSyncedAt)}
                />
              ) : null}
              {healthSync.lastMessage ? (
                <Text
                  style={{
                    fontSize: 13,
                    lineHeight: 18,
                    color: palette.textTertiary,
                  }}
                >
                  {healthSync.lastMessage}
                </Text>
              ) : null}
            </View>
          ) : null}
          {loading ? (
            <View style={{ flexDirection: 'row', alignItems: 'center', gap: 10 }}>
              <ActivityIndicator color={palette.tint} />
              <Text
                style={{
                  fontSize: 15,
                  lineHeight: 20,
                  color: palette.textSecondary,
                }}
              >
                Syncing recent sleep…
              </Text>
            </View>
          ) : (
            <Button
              title={healthAuthorized ? 'Refresh sleep' : 'Connect to Health'}
              onPress={connectHealth}
              disabled={healthAvailable === false}
            />
          )}
          {healthAvailable === false && !loading ? (
            <Text
              style={{
                fontSize: 13,
                lineHeight: 18,
                color: palette.textTertiary,
              }}
            >
              Health import is available on iPhone only. Use manual mode or load demo data on this device.
            </Text>
          ) : null}
          {error ? (
            <Text
              style={{
                fontSize: 13,
                lineHeight: 18,
                color: palette.destructive,
              }}
            >
              {error}
            </Text>
          ) : null}
          <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
            <Button
              title={demoMode ? 'Refresh demo data' : 'Load demo data'}
              variant="secondary"
              onPress={loadDemoData}
              disabled={loading}
            />
            {demoMode ? (
              <Button
                title="Clear demo data"
                variant="plain"
                onPress={clearDemoData}
                disabled={loading}
              />
            ) : null}
          </View>
        </SectionCard>

        <SectionTitle>Last night</SectionTitle>
        {lastSleep ? (
          <>
            <View style={{ flexDirection: 'row', gap: 12 }}>
              <StatTile
                label="Sleep window"
                value={fmtDuration(lastSleep.end - lastSleep.start)}
                detail={`${fmtTime(lastSleep.start)} – ${fmtTime(lastSleep.end)}`}
              />
              <StatTile
                label="Total asleep"
                value={fmtDuration(lastNightTotalMs)}
                detail={`Wake time ${fmtTime(lastSleep.end)}`}
              />
            </View>
            <SectionCard>
              <ListRow
                title="Imported night"
                subtitle={demoMode ? 'Most recent demo session' : 'Most recent sleep session'}
                value={fmtDate(lastSleep.start)}
              />
              <ListRow
                title="Sleep samples"
                subtitle={demoMode ? 'Demo sessions loaded' : 'Stored sessions available'}
                value={`${storedSleepSamples.length}`}
              />
              <ListRow
                title="Wake time"
                subtitle="Used to anchor your plan"
                value={fmtTime(lastSleep.end)}
              />
            </SectionCard>
          </>
        ) : (
          <SectionCard>
            <Text
              style={{
                fontSize: 15,
                lineHeight: 20,
                color: palette.textSecondary,
              }}
            >
              Connect Health to bring in recent sleep, log sleep manually, or load demo data for screenshots and reviewer walkthroughs.
            </Text>
          </SectionCard>
        )}

        <SectionTitle>Caffeine impact</SectionTitle>
        <SectionCard>
          {sleepImpact.n >= 1 ? (
            <>
              <ListRow
                title="Last-dose timing"
                subtitle="Median time between final dose and sleep"
                value={`${Math.round(sleepImpact.medianDeltaMin)} min`}
              />
              <ListRow
                title="Typical range"
                subtitle="10th to 90th percentile"
                value={`${sleepImpact.p10}–${sleepImpact.p90} min`}
              />
              <ListRow
                title="Median sleep span"
                subtitle="Across nights with dose timing data"
                value={`${Math.round(sleepImpact.medianSleepMin / 60)}h`}
              />
              {!sleepImpact.showCorrelation ? (
                <Text
                  style={{
                    fontSize: 13,
                    lineHeight: 18,
                    color: palette.textTertiary,
                  }}
                >
                  Keep logging for at least 14 nights before reading this as a pattern.
                </Text>
              ) : null}
            </>
          ) : (
            <Text
              style={{
                fontSize: 15,
                lineHeight: 20,
                color: palette.textSecondary,
              }}
            >
              Once Aurora has sleep history and nearby dose timing, this section will summarize how close your final dose tends to land before bed.
            </Text>
          )}
        </SectionCard>

        <SectionTitle>Suggested plan</SectionTitle>
        <SectionCard>
          {!wakeTime || plan.length === 0 ? (
            <Text
              style={{
                fontSize: 15,
                lineHeight: 20,
                color: palette.textSecondary,
              }}
            >
              A plan appears after Aurora has a wake time and there is still room before today’s cutoff.
            </Text>
          ) : (
            <>
              {plan.map((item, index) => (
                <View
                  key={item.t}
                  style={{
                    gap: 10,
                    paddingTop: index === 0 ? 0 : 12,
                    borderTopWidth: index === 0 ? 0 : 1,
                    borderColor: palette.separator,
                  }}
                >
                  <ListRow
                    title={item.label}
                    subtitle={`Recommended at ${fmtTime(item.t)}`}
                    value={`${item.mg} mg`}
                  />
                  {index === 0 ? (
                    <Button
                      title="Log first dose now"
                      variant="secondary"
                      onPress={() => addNow(item.mg)}
                    />
                  ) : null}
                </View>
              ))}
              <Text
                style={{
                  fontSize: 13,
                  lineHeight: 18,
                  color: palette.textTertiary,
                }}
              >
                Based on a soft 200 mg budget and the time between your latest wake point and cutoff.
              </Text>
            </>
          )}
        </SectionCard>
      </View>
    </AppScreen>
  );
}
