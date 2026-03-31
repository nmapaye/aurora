import React, { useEffect, useMemo, useState } from 'react';
import { ActivityIndicator, Text, View, useColorScheme } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import { InlineStatus, ListRow, SectionCard, SectionTitle, StatTile } from '~/components/ui';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import AppleHealth from '~/services/platform/health/appleHealth';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';

type SleepSample = { start: number; end: number; type?: string };

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

export default function SleepScreen() {
  const scheme = useColorScheme();
  const palette = getAppPalette(scheme);
  const doses = useStore((state) => state.doses);
  const addDose = useStore((state) => state.addDose);
  const onboarding = useStore((state) => state.onboarding);
  const setOnboarding = useStore((state) => state.setOnboarding);
  const upsertSleepSessions = useStore((state) => state.upsertSleepSessions);
  const cutoff = useCaffeineCutoff();

  const [healthAvailable, setHealthAvailable] = useState(false);
  const [healthAuthorized, setHealthAuthorized] = useState<boolean | undefined>(undefined);
  const [loading, setLoading] = useState(false);
  const [lastSleep, setLastSleep] = useState<SleepSample | undefined>();
  const [sleepSamples, setSleepSamples] = useState<SleepSample[]>([]);
  const [wakeTime, setWakeTime] = useState<number | undefined>();
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
      if (!available) {
        setError('Health import is unavailable on this device.');
        setHealthAuthorized(false);
        return;
      }
      const ok = await AppleHealth.requestAuthorization();
      if (!ok) {
        setError('Authorization was not granted.');
        setHealthAuthorized(false);
        return;
      }
      setHealthAuthorized(true);
      const end = Date.now();
      const start = end - 3 * 24 * 3_600_000;
      const samples = await AppleHealth.getSleepSamples(start, end);
      const mapped: SleepSample[] = (samples || [])
        .map((sample: any) => ({
          start: Number(sample.start),
          end: Number(sample.end),
          type: sample.label,
        }))
        .filter((sample) => Number.isFinite(sample.start) && Number.isFinite(sample.end))
        .sort((a, b) => b.end - a.end);
      upsertSleepSessions(
        mapped.map((sample) => ({
          id: `sleep:${sample.start}:${sample.end}`,
          start: sample.start,
          end: sample.end,
          type: 'sleep' as const,
        }))
      );
      const latest = mapped[0];
      setSleepSamples(mapped);
      setLastSleep(latest);
      setWakeTime(latest?.end);
      setOnboarding({ source: 'healthkit', permissionStatus: 'granted' });
    } catch (nextError: any) {
      setError(nextError?.message || 'Failed to read sleep data.');
      setHealthAuthorized(false);
      setOnboarding({ permissionStatus: 'denied' });
    } finally {
      setLoading(false);
    }
  };

  const lastNightTotalMs = useMemo(() => {
    if (!sleepSamples.length) return 0;
    const referenceEnd = lastSleep?.end ?? sleepSamples[0]?.end;
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
    for (const sample of sleepSamples) {
      if (!isAsleep(sample.type)) continue;
      const start = Math.max(sample.start, startMs);
      const end = Math.min(sample.end, endMs);
      if (end > start) total += end - start;
    }
    return total;
  }, [lastSleep?.end, sleepSamples]);

  const sleepImpact = useMemo(() => {
    const pairs: { deltaMin: number; sleepMin: number }[] = [];
    for (const sample of sleepSamples) {
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
  }, [doses, sleepSamples]);

  const addNow = (mg: number) => {
    addDose({
      id: `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`,
      timestamp: Date.now(),
      mg,
      source: 'Plan',
    });
  };

  const healthStatus =
    loading
      ? 'Syncing'
      : healthAuthorized
      ? 'Connected'
      : onboarding.source === 'manual'
      ? 'Manual mode'
      : healthAvailable
      ? 'Not connected'
      : 'Unavailable';

  const healthTone =
    error
      ? 'error'
      : healthAuthorized
      ? 'success'
      : onboarding.source === 'manual'
      ? 'neutral'
      : healthAvailable
      ? 'warning'
      : 'neutral';

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
            {onboarding.source === 'manual'
              ? 'Aurora is currently using manual logging only. Connect Health any time to import sleep automatically.'
              : 'Aurora reads recent sleep from Health so wake time and guidance stay grounded in actual recovery.'}
          </Text>
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
              disabled={!healthAvailable}
            />
          )}
          {!healthAvailable && !loading ? (
            <Text
              style={{
                fontSize: 13,
                lineHeight: 18,
                color: palette.textTertiary,
              }}
            >
              Health import is currently available on iPhone only.
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
                subtitle="Most recent Health session"
                value={fmtDate(lastSleep.start)}
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
              Connect Health to bring in recent sleep. Aurora will then show your latest wake time and tailor the suggested caffeine plan below.
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
