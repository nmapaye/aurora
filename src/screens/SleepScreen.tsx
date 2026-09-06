import ChartTable from '~/components/ChartTable';
import React, { useEffect, useMemo, useRef, useState } from 'react';
import { AccessibilityInfo, ScrollView, Text, TextInput, View } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';

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
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import { createManualSleepDraft, createManualSleepId, validateManualSleep } from '~/features/sleep/manualSleep';
import { formatSleepDuration, getCaffeineImpact, getSleepPresentation, type SleepRange } from '~/features/sleep/presentation';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useAppScheme from '~/hooks/useAppScheme';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import useReduceMotion from '~/hooks/useReduceMotion';
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

function formatDateTime(timestamp: number) {
  return new Intl.DateTimeFormat(undefined, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  }).format(new Date(timestamp));
}

export default function SleepScreen() {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const layout = useAdaptiveLayout();
  const reduceMotion = useReduceMotion();
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
  const [pickerField, setPickerField] = useState<'start' | 'end' | undefined>();
  const addDataRef = useRef<View>(null);
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef<View>(null);
  const sourcesAnchorRef = useRef<View>(null);
  const walkthrough = useAppWalkthrough({
    route: 'Sleep',
    isWideLayout: layout.isWideLayout,
    scrollRef,
    contentRef,
  });

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
  const caffeineImpact = useMemo(
    () => getCaffeineImpact(sleeps, doses, range, now),
    [doses, now, range, sleeps],
  );
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
  const refreshFailureMessage = refreshError
    ? `Health refresh failed. ${refreshError}`
    : healthSync.importStatus === 'failed'
      ? healthSync.lastMessage ?? 'Health refresh failed. Try again.'
      : undefined;
  const healthState = refreshFailureMessage
    ? 'Health refresh failed'
    : demoMode
      ? 'Sample Data'
      : healthAvailable === false || onboarding.permissionStatus === 'unsupported'
        ? 'Health unavailable'
        : onboarding.permissionStatus === 'denied'
          ? 'Health access denied'
          : onboarding.permissionStatus === 'granted'
            ? 'Health connected'
            : 'Manual mode';
  const healthDescription = refreshFailureMessage
    ? refreshFailureMessage
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
        setHealthSync({ importedCount: 0, importStatus: 'idle', lastSyncedAt: now, lastMessage: 'Health import is unavailable. No sleep samples were imported.' });
        return;
      }
      if (!(await AppleHealth.requestAuthorization())) {
        setOnboarding({ source: 'manual', permissionStatus: 'denied' });
        setHealthSync({ importedCount: 0, importStatus: 'idle', lastSyncedAt: now, lastMessage: 'Health access was denied. No sleep samples were imported.' });
        return;
      }
      setOnboarding({ source: 'healthkit', permissionStatus: 'granted' });
      setHealthSync({
        importStatus: 'importing',
        lastMessage: 'Importing recent sleep from Health.',
      });
      const samples = await AppleHealth.getSleepSamples(now - 30 * DAY_MS, now);
      const sessions = samples.map((sample) => ({
        id: makeHealthSleepSessionId(sample), start: sample.start, end: sample.end, type: 'sleep' as const,
      }));
      upsertSleepSessions(sessions);
      setHealthSync({
        importedCount: sessions.length,
        importStatus: 'succeeded',
        lastSyncedAt: now,
        lastMessage: sessions.length ? `Imported ${sessions.length} sleep ${sessions.length === 1 ? 'sample' : 'samples'} from Health.` : 'Health connected with 0 imported sleep samples.',
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to read sleep data.';
      setRefreshError(message);
      setHealthSync({ importStatus: 'failed', lastSyncedAt: now, lastMessage: `Health refresh failed. ${message}` });
    } finally {
      setLoading(false);
    }
  };

  const saveManualSleep = () => {
    if (!validation.valid) return;
    addSleep({ id: createManualSleepId(now), start: draft.start, end: draft.end, type: 'sleep', ...(draft.note.trim() ? { note: draft.note.trim() } : {}) });
    setPickerField(undefined);
    setShowForm(false);
    setAnnouncement('Sleep session saved.');
    AccessibilityInfo.announceForAccessibility('Sleep session saved.');
  };
  const logFirstPlanDose = () => {
    const first = plan[0];
    if (!first) return;
    addDose({ id: `${now.toString(36)}-${Math.random().toString(36).slice(2)}`, timestamp: now, mg: first.mg, source: 'Plan' });
  };

  const chart = (
    <HealthChartCard title="Time Asleep" value={presentation.headline} dateRange={presentation.dateRange} accessibilitySummary={presentation.accessibilitySummary} emptyState={<HealthEmptyState message="No sleep data for this range." detail="Add a manual session or connect Health." symbol="bed.double.fill" fallback="bed" />}>
      {presentation.points.some((point) => point.durationMs !== null) ? (
        <View><View accessibilityElementsHidden style={{ height: 92, flexDirection: 'row', alignItems: 'flex-end', gap: 3 }}>
          {presentation.points.map((point) => <View key={point.date} style={{ flex: 1, minHeight: 3, height: point.durationMs ? Math.max(6, Math.min(92, point.durationMs / (10 * 60 * 60 * 1000) * 92)) : 3, borderRadius: 2, backgroundColor: point.durationMs ? palette.sleepAccent : palette.separator }} />)}
        </View><ChartTable title="time asleep" rows={presentation.points.map(p=>`${new Date(p.date).toLocaleDateString()}: ${p.durationMs===null?'Missing sleep records':`${(p.durationMs/3600000).toFixed(2)} hours recorded sleep`}`)} /></View>
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
      <HealthHighlightCard
        label="Caffeine Impact"
        value={caffeineImpact.qualifyingNights ? `${caffeineImpact.medianDeltaMin} min` : 'No timing data'}
        detail={caffeineImpact.showCorrelation
          ? 'Timing pattern ready to review.'
          : `${caffeineImpact.qualifyingNights}/14 qualifying nights. Keep logging before reading a pattern.`}
        accentColor={palette.sleepAccent}
      />
      {caffeineImpact.qualifyingNights ? <HealthGroupedList rows={[
        { title: 'Last-dose timing', subtitle: 'Median time between final dose and sleep', value: `${caffeineImpact.medianDeltaMin} min` },
        { title: 'Typical range', subtitle: '10th to 90th percentile', value: `${caffeineImpact.p10}–${caffeineImpact.p90} min` },
        { title: 'Median sleep span', subtitle: 'Across qualifying nights', value: `${Math.round(caffeineImpact.medianSleepMin / 60)}h` },
      ]} /> : null}
    </View>
  );

  const walkthroughCoach = walkthrough.active ? (
    <WalkthroughReveal
      key={walkthrough.step.id}
      active
      revealed={walkthrough.coachVisible}
      reduceMotion={walkthrough.reduceMotion}
    >
      <AppWalkthroughCoach
        step={walkthrough.step}
        locked={walkthrough.locked}
        headingRef={walkthrough.coachHeadingRef}
        onLayout={walkthrough.onCoachLayout}
        onSkip={walkthrough.onSkip}
        onPrimary={walkthrough.onPrimary}
      />
    </WalkthroughReveal>
  ) : null;

  return (
    <AppScreen
      title="Sleep"
      trailing={<Button ref={addDataRef} title="Add Data" variant="plain" onPress={() => { setDraft(createManualSleepDraft(Date.now())); setShowForm(true); }} />}
      scrollRef={scrollRef}
      contentRef={contentRef}
      scrollEnabled={!walkthrough.active}
      interactionEnabled={!walkthrough.active}
      bottomOverlay={walkthroughCoach}
      onScroll={walkthrough.onScroll}
      onViewportLayout={walkthrough.onViewportLayout}
      headerTransform={(header) => (
        <WalkthroughReveal
          active={walkthrough.active}
          revealed={walkthrough.isRevealed('sleep-header')}
          reduceMotion={walkthrough.reduceMotion}
        >
          {header}
        </WalkthroughReveal>
      )}
    >
      <View style={{ gap: spacing.md }}>
        <WalkthroughReveal active={walkthrough.active} revealed={walkthrough.isRevealed('sleep-history')} reduceMotion={walkthrough.reduceMotion} style={{ gap: spacing.md }}>
          <HealthRangeControl accessibilityLabel="Sleep range" value={range} onChange={setRange} options={[{ value: 'week', label: 'W' }, { value: 'month', label: 'M' }]} />
          <View testID={layout.isWideLayout ? 'sleep-wide-layout' : 'sleep-compact-layout'} style={{ flexDirection: layout.isWideLayout ? 'row' : 'column', gap: spacing.md }}>
            <View
              testID="sleep-primary-column"
              style={{ width: layout.isWideLayout ? layout.leftColumnWidth : '100%' }}
            >
              {chart}
            </View>
            {layout.isWideLayout ? (
              <View
                testID="sleep-supporting-column"
                style={{ width: layout.rightColumnWidth }}
              >
                {highlights}
              </View>
            ) : null}
          </View>
          {!layout.isWideLayout ? highlights : null}
        </WalkthroughReveal>
        <WalkthroughReveal active={walkthrough.active} revealed={walkthrough.isRevealed('sleep-sources')} reduceMotion={walkthrough.reduceMotion}>
          <View ref={sourcesAnchorRef} collapsable={false} onLayout={() => walkthrough.measureAnchor('sleep-sources', sourcesAnchorRef.current)} style={{ gap: spacing.md }}>
            <View style={{ gap: spacing.sm }}>
              <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Next Best Actions</Text>
              {plan.length ? <HealthGroupedList rows={plan.map((item) => ({ title: item.label, subtitle: `Recommended at ${formatTime(item.time)}`, value: `${item.mg} mg` }))} /> : <HealthEmptyState message="Add a wake time to see your 200 mg plan." />}
              {plan[0] ? <Button title="Log First Dose Now" variant="tinted" onPress={logFirstPlanDose} /> : null}
              {plan[0] ? <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Based on today’s intake and your cutoff.</Text> : null}
            </View>
            <View style={{ gap: spacing.sm }}>
              <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>Options</Text>
              <HealthGroupedList rows={[{ title: 'Data Sources & Access', subtitle: healthState, onPress: () => setShowSources((visible) => !visible) }, { title: 'Sleep Routines', subtitle: 'Schedule, naps, consistency and reminders', onPress: () => navigate('SleepRoutines') }, { title: 'Show All Data', subtitle: `${sleeps.length} sessions`, onPress: () => navigate('SleepHistory') }]} />
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
        </WalkthroughReveal>
      </View>
      <HealthFormSheet visible={showForm} title="Add Sleep" reduceMotion={reduceMotion} returnFocusRef={addDataRef} onCancel={() => { setPickerField(undefined); setShowForm(false); }} onSave={saveManualSleep} saveDisabled={!validation.valid}>
        <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Choose the local start and end time for this sleep session.</Text>
        <Button title={`Start · ${formatDateTime(draft.start)}`} accessibilityLabel="Start time" accessibilityValue={{ text: formatDateTime(draft.start) }} variant="tinted" onPress={() => setPickerField('start')} />
        <Button title={`End · ${formatDateTime(draft.end)}`} accessibilityLabel="End time" accessibilityValue={{ text: formatDateTime(draft.end) }} variant="tinted" onPress={() => setPickerField('end')} />
        {pickerField ? <DateTimePicker testID={`sleep-${pickerField}-picker`} value={new Date(draft[pickerField])} mode="datetime" display="spinner" onChange={(_event, date) => { if (date) setDraft((current) => ({ ...current, [pickerField]: date.getTime() })); }} /> : null}
        <TextInput accessibilityLabel="Sleep note" value={draft.note} onChangeText={(note) => setDraft((current) => ({ ...current, note }))} placeholder="Optional note" placeholderTextColor={palette.textTertiary} style={{ minHeight: 44, borderWidth: 1, borderColor: palette.separator, borderRadius: radii.control, color: palette.textPrimary, paddingHorizontal: spacing.sm }} />
        {!validation.valid ? <Text accessibilityRole="alert" style={{ ...typeRamp.footnote, color: palette.destructive }}>{validation.message}</Text> : null}
      </HealthFormSheet>
      {announcement ? <Text accessibilityLiveRegion="polite" accessibilityLabel={announcement} style={{ position: 'absolute', width: 1, height: 1, opacity: 0 }}>{announcement}</Text> : null}
    </AppScreen>
  );
}
