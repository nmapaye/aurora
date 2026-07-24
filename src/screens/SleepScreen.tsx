import React, { useEffect, useMemo, useState } from 'react';
import { Text, TextInput, View } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import {
  HealthChartCard,
  HealthEmptyState,
  HealthFormSheet,
  HealthGroupedList,
  HealthHighlightCard,
  HealthRangeControl,
} from '~/components/health';
import { createManualSleepDraft, createManualSleepId, validateManualSleep } from '~/features/sleep/manualSleep';
import { formatSleepDuration, getSleepPresentation, type SleepRange } from '~/features/sleep/presentation';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import { navigate } from '~/navigation';
import AppleHealth, { makeHealthSleepSessionId } from '~/services/platform/health/appleHealth';
import { useStore } from '~/state/store';
import { getAppPalette } from '~/theme/colors';
import { radii, spacing, typeRamp } from '~/theme/tokens';

const DAY_MS = 24 * 60 * 60 * 1000;

function formatTime(timestamp: number) {
  return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(timestamp));
}

function formatDifference(differenceMs: number) {
  if (differenceMs === 0) return 'On target';
  const value = formatSleepDuration(Math.abs(differenceMs));
  return differenceMs > 0 ? `${value} over target` : `${value} under target`;
}

function numberInput(value: string) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : Number.NaN;
}

export default function SleepScreen() {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const layout = useAdaptiveLayout();
  const cutoff = useCaffeineCutoff();
  const sleeps = useStore((state) => state.sleeps);
  const doses = useStore((state) => state.doses);
  const prefs = useStore((state) => state.prefs);
  const onboarding = useStore((state) => state.onboarding);
  const healthSync = useStore((state) => state.healthSync);
  const demoMode = useStore((state) => state.demoMode);
  const addSleep = useStore((state) => state.addSleep);
  const addDose = useStore((state) => state.addDose);
  const upsertSleepSessions = useStore((state) => state.upsertSleepSessions);
  const setOnboarding = useStore((state) => state.setOnboarding);
  const setHealthSync = useStore((state) => state.setHealthSync);
  const loadDemoData = useStore((state) => state.loadDemoData);
  const clearDemoData = useStore((state) => state.clearDemoData);
  const [range, setRange] = useState<SleepRange>('week');
  const [showForm, setShowForm] = useState(false);
  const [showSources, setShowSources] = useState(false);
  const [draft, setDraft] = useState(() => createManualSleepDraft());
  const [announcement, setAnnouncement] = useState('');
  const [healthAvailable, setHealthAvailable] = useState<boolean | undefined>();
  const [loading, setLoading] = useState(false);
  const [refreshError, setRefreshError] = useState<string | undefined>();

  useEffect(() => {
    let active = true;
    AppleHealth.isAvailable().then((available) => active && setHealthAvailable(available));
    return () => { active = false; };
  }, []);

  const now = Date.now();
  const presentation = useMemo(
    () => getSleepPresentation(sleeps, prefs.targetSleep, range, now),
    [sleeps, prefs.targetSleep, range, now],
  );
  const validation = validateManualSleep(draft, now);
  const todayTotal = useMemo(() => {
    const today = new Date(now).toDateString();
    return doses.filter((dose) => new Date(dose.timestamp).toDateString() === today).reduce((sum, dose) => sum + dose.mg, 0);
  }, [doses, now]);
  const plan = useMemo(() => {
    const wakeTime = presentation.lastNight?.wakeTime;
    if (!wakeTime || !cutoff?.nextCutoff) return [] as { time: number; mg: number; label: string }[];
    const start = Math.max(wakeTime + 30 * 60 * 1000, now);
    if (cutoff.nextCutoff <= start) return [];
    const remaining = Math.max(0, 200 - todayTotal);
    const base = [80, 80, 40];
    return base.reduce<{ time: number; mg: number; label: string }[]>((items, mg, index) => {
      const time = start + index * 3.5 * 60 * 60 * 1000;
      const allowed = Math.min(mg, Math.max(0, remaining - items.reduce((sum, item) => sum + item.mg, 0)));
      if (time >= cutoff.nextCutoff || allowed < 20) return items;
      return [...items, { time, mg: allowed, label: ['Kickstart', 'Sustain', 'Top-up'][index] ?? 'Plan' }];
    }, []);
  }, [cutoff?.nextCutoff, now, presentation.lastNight?.wakeTime, todayTotal]);
  const healthState = demoMode
    ? 'Sample Data'
    : healthAvailable === false || onboarding.permissionStatus === 'unsupported'
      ? 'Health unavailable'
      : onboarding.permissionStatus === 'denied'
        ? 'Health access denied'
        : onboarding.permissionStatus === 'granted'
          ? 'Health connected'
          : 'Manual mode';
  const healthDescription = refreshError
    ? `Health refresh failed. ${refreshError}`
    : healthState === 'Health connected'
      ? 'Aurora can refresh the most recent 30 days of read-only sleep data.'
      : healthState === 'Health access denied'
        ? 'Health access is denied. Manual sleep logging remains available.'
        : healthState === 'Health unavailable'
          ? 'Health import is unavailable on this device.'
          : healthState === 'Sample Data'
            ? 'Example sleep and caffeine data is active.'
            : 'Add sleep manually or connect Health when you are ready.';

  const connectHealth = async () => {
    setLoading(true);
    setRefreshError(undefined);
    try {
      const available = await AppleHealth.isAvailable();
      setHealthAvailable(available);
      if (!available) {
        setOnboarding({ source: 'manual', permissionStatus: 'unsupported' });
        setHealthSync({ importedCount: 0, lastSyncedAt: now, lastMessage: 'Health import is unavailable. No sleep samples were imported.' });
        return;
      }
      if (!(await AppleHealth.requestAuthorization())) {
        setOnboarding({ source: 'manual', permissionStatus: 'denied' });
        setHealthSync({ importedCount: 0, lastSyncedAt: now, lastMessage: 'Health access was denied. No sleep samples were imported.' });
        return;
      }
      const samples = await AppleHealth.getSleepSamples(now - 30 * DAY_MS, now);
      const sessions = samples.map((sample) => ({
        id: makeHealthSleepSessionId(sample), start: sample.start, end: sample.end, type: 'sleep' as const,
      }));
      upsertSleepSessions(sessions);
      setOnboarding({ source: 'healthkit', permissionStatus: 'granted' });
      setHealthSync({
        importedCount: sessions.length,
        lastSyncedAt: now,
        lastMessage: sessions.length ? `Imported ${sessions.length} sleep ${sessions.length === 1 ? 'sample' : 'samples'} from Health.` : 'Health connected with 0 imported sleep samples.',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to read sleep data.';
      setRefreshError(message);
      setHealthSync({ ...healthSync, lastSyncedAt: now, lastMessage: `Health refresh failed. ${message}` });
    } finally {
      setLoading(false);
    }
  };

  const saveManualSleep = () => {
    if (!validation.valid) return;
    addSleep({ id: createManualSleepId(now), start: draft.start, end: draft.end, type: 'sleep', ...(draft.note.trim() ? { note: draft.note.trim() } : {}) });
    setShowForm(false);
    setAnnouncement('Sleep session saved.');
  };
  const logFirstPlanDose = () => {
    const first = plan[0];
    if (!first) return;
    addDose({ id: `${now.toString(36)}-${Math.random().toString(36).slice(2)}`, timestamp: now, mg: first.mg, source: 'Plan' });
  };

  const chart = (
    <HealthChartCard title="Time Asleep" value={presentation.headline} dateRange={presentation.dateRange} accessibilitySummary={presentation.accessibilitySummary} emptyState={<HealthEmptyState message="No sleep data for this range." detail="Add a manual session or connect Health." symbol="bed.double.fill" fallback="bed" />}>
      {presentation.points.some((point) => point.durationMs !== null) ? (
        <View accessibilityElementsHidden style={{ height: 92, flexDirection: 'row', alignItems: 'flex-end', gap: 3 }}>
          {presentation.points.map((point) => <View key={point.date} style={{ flex: 1, minHeight: 3, height: point.durationMs ? Math.max(6, Math.min(92, point.durationMs / (10 * 60 * 60 * 1000) * 92)) : 3, borderRadius: 2, backgroundColor: point.durationMs ? palette.sleepAccent : palette.separator }} />)}
        </View>
      ) : undefined}
    </HealthChartCard>
  );
  const highlights = (
    <View style={{ gap: spacing.sm }}>
      <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Highlights</Text>
      {presentation.lastNight ? (
        <View style={{ flexDirection: layout.isWideLayout ? 'row' : 'column', gap: spacing.sm }}>
          <HealthHighlightCard label="Last Night" value={formatSleepDuration(presentation.lastNight.durationMs)} detail={formatDifference(presentation.lastNight.targetDifferenceMs ?? 0)} accentColor={palette.sleepAccent} />
          <HealthHighlightCard label="Wake Time" value={formatTime(presentation.lastNight.wakeTime)} detail="Used to anchor your plan" accentColor={palette.sleepAccent} />
        </View>
      ) : <HealthEmptyState message="No recent sleep session." />}
      <HealthHighlightCard label="Caffeine Impact" value={sleeps.length >= 14 ? 'Review your timing' : `${sleeps.length}/14 nights`} detail={sleeps.length >= 14 ? 'Compare your logged timing with sleep duration.' : 'Keep logging for at least 14 nights before reading a pattern.'} accentColor={palette.sleepAccent} />
    </View>
  );

  return (
    <AppScreen title="Sleep" trailing={<Button title="Add Data" variant="plain" onPress={() => { setDraft(createManualSleepDraft(Date.now())); setShowForm(true); }} />}>
      <View style={{ gap: spacing.md }}>
        <HealthRangeControl accessibilityLabel="Sleep range" value={range} onChange={setRange} options={[{ value: 'week', label: 'W' }, { value: 'month', label: 'M' }]} />
        <View testID={layout.isWideLayout ? 'sleep-wide-layout' : 'sleep-compact-layout'} style={{ flexDirection: layout.isWideLayout ? 'row' : 'column', gap: spacing.md }}>
          <View style={{ flex: 1 }}>{chart}</View>
          {layout.isWideLayout ? <View style={{ flex: 1 }}>{highlights}</View> : null}
        </View>
        {!layout.isWideLayout ? highlights : null}
        <View style={{ gap: spacing.sm }}>
          <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Next Best Actions</Text>
          {plan.length ? <HealthGroupedList rows={plan.map((item) => ({ title: item.label, subtitle: `Recommended at ${formatTime(item.time)}`, value: `${item.mg} mg` }))} /> : <HealthEmptyState message="Add a wake time to see your 200 mg plan." />}
          {plan[0] ? <Button title="Log First Dose Now" variant="tinted" onPress={logFirstPlanDose} /> : null}
          {plan[0] ? <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Based on today’s intake and your cutoff.</Text> : null}
        </View>
        <View style={{ gap: spacing.sm }}>
          <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Options</Text>
          <HealthGroupedList rows={[{ title: 'Data Sources & Access', subtitle: healthState, onPress: () => setShowSources((visible) => !visible) }, { title: 'Show All Data', subtitle: `${sleeps.length} sessions`, onPress: () => navigate('SleepHistory') }]} />
          {showSources ? <View style={{ gap: spacing.sm, padding: spacing.md, borderRadius: radii.card, backgroundColor: palette.card }}>
            <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>{healthState}</Text>
            <Text style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>{healthDescription}</Text>
            <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Imported: {healthSync.importedCount} sleep samples</Text>
            {healthSync.lastSyncedAt ? <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Last sync: {formatTime(healthSync.lastSyncedAt)}</Text> : null}
            {healthSync.lastMessage ? <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>{healthSync.lastMessage}</Text> : null}
            <Button title={onboarding.permissionStatus === 'granted' ? 'Refresh Sleep' : 'Connect to Health'} variant="primary" onPress={connectHealth} disabled={loading || healthAvailable === false} loading={loading} />
            <View style={{ flexDirection: 'row', gap: spacing.sm }}><Button title={demoMode ? 'Refresh Sample Data' : 'Load Sample Data'} onPress={loadDemoData} /><Button title="Clear Samples" variant="plain" role="destructive" onPress={clearDemoData} disabled={!demoMode} /></View>
          </View> : null}
        </View>
      </View>
      <HealthFormSheet visible={showForm} title="Add Sleep" onCancel={() => setShowForm(false)} onSave={saveManualSleep} saveDisabled={!validation.valid}>
        <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Enter local start and end times as milliseconds since 1970.</Text>
        <TextInput accessibilityLabel="Start time" keyboardType="numeric" value={String(draft.start)} onChangeText={(value) => setDraft((current) => ({ ...current, start: numberInput(value) }))} style={{ minHeight: 44, borderWidth: 1, borderColor: palette.separator, borderRadius: radii.control, color: palette.textPrimary, paddingHorizontal: spacing.sm }} />
        <TextInput accessibilityLabel="End time" keyboardType="numeric" value={String(draft.end)} onChangeText={(value) => setDraft((current) => ({ ...current, end: numberInput(value) }))} style={{ minHeight: 44, borderWidth: 1, borderColor: palette.separator, borderRadius: radii.control, color: palette.textPrimary, paddingHorizontal: spacing.sm }} />
        <TextInput accessibilityLabel="Sleep note" value={draft.note} onChangeText={(note) => setDraft((current) => ({ ...current, note }))} placeholder="Optional note" placeholderTextColor={palette.textTertiary} style={{ minHeight: 44, borderWidth: 1, borderColor: palette.separator, borderRadius: radii.control, color: palette.textPrimary, paddingHorizontal: spacing.sm }} />
        {!validation.valid ? <Text accessibilityRole="alert" style={{ ...typeRamp.footnote, color: palette.destructive }}>{validation.message}</Text> : null}
      </HealthFormSheet>
      {announcement ? <Text accessibilityLiveRegion="polite" accessibilityLabel={announcement} style={{ position: 'absolute', width: 1, height: 1, opacity: 0 }}>{announcement}</Text> : null}
    </AppScreen>
  );
}
