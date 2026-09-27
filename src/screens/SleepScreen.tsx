import React, { useEffect, useMemo, useRef, useState } from 'react';
import { AccessibilityInfo, RefreshControl, ScrollView, Text, TextInput, View } from 'react-native';
import DateTimePicker from '@react-native-community/datetimepicker';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import SignalCard from '~/components/SignalCard';
import {
  HealthBarChart,
  HealthChartCard,
  HealthEmptyState,
  HealthFormSheet,
  HealthGroupedList,
  HealthRangeControl,
} from '~/components/health';
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import { createManualSleepDraft, createManualSleepId, validateManualSleep } from '~/features/sleep/manualSleep';
import { describeSleepChartDay, formatSleepDuration, getSleepPresentation, type SleepRange } from '~/features/sleep/presentation';
import { caffeineTimingSignal, recentNightSignal, type CaffeineTimingSignal } from '~/features/sleep/signals';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useNow from '~/hooks/useNow';
import useAppScheme from '~/hooks/useAppScheme';
import useReduceMotion from '~/hooks/useReduceMotion';
import { navigate } from '~/navigation';
import AppleHealth from '~/services/platform/health/appleHealth';
import { importHealthSleep } from '~/features/sleep/healthImport';
import { useStore } from '~/state/store';
import { haptics } from '~/services/platform/haptics';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, radii, spacing, typeRamp } from '~/theme/tokens';

const HOUR_MS = 60 * 60 * 1000;

function formatTime(timestamp: number) {
  return new Intl.DateTimeFormat(undefined, { hour: 'numeric', minute: '2-digit' }).format(new Date(timestamp));
}

function formatDateTime(timestamp: number) {
  return new Intl.DateTimeFormat(undefined, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
  }).format(new Date(timestamp));
}

// Describes when caffeine was last logged before sleep. Below the paired-night
// gate it shows only progress, never a number; at the gate it shows one median
// with its night count, and the distribution stays behind a disclosure.
function CaffeineTiming({ signal, accent }: { signal: CaffeineTimingSignal; accent: string }) {
  const palette = getAppPalette(useAppScheme());
  const [showDetail, setShowDetail] = useState(false);

  if (signal.status === 'gathering') {
    return (
      <View
        testID="caffeine-timing-gathering"
        accessible
        accessibilityLabel={`${signal.label}. ${signal.text}`}
        style={{
          gap: 2,
          paddingHorizontal: spacing.md,
          paddingVertical: spacing.sm,
          borderRadius: radii.card,
          borderWidth: 1,
          borderColor: palette.cardBorder,
        }}
      >
        <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.subheadline, fontWeight: '600', color: palette.textSecondary }}>
          {signal.label}
        </Text>
        <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.footnote, color: palette.textTertiary }}>
          {signal.text}
        </Text>
      </View>
    );
  }

  return (
    <View
      testID="caffeine-timing-observed"
      style={{ gap: spacing.sm, padding: spacing.md, borderRadius: radii.card, backgroundColor: palette.card, borderWidth: 1, borderColor: palette.cardBorder }}
    >
      <View accessible accessibilityLabel={signal.accessibilityLabel} style={{ gap: spacing.xxs }}>
        <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.headline, color: accent }}>
          {signal.label}
        </Text>
        <Text maxFontSizeMultiplier={fontScaling.hero} style={{ ...typeRamp.title3, fontVariant: ['tabular-nums'], color: palette.textPrimary }}>
          {signal.value}
        </Text>
        <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>
          {signal.context}
        </Text>
        <Text maxFontSizeMultiplier={fontScaling.body} style={{ ...typeRamp.footnote, color: palette.textTertiary }}>
          {signal.period}
        </Text>
      </View>
      <HealthGroupedList
        rows={[{
          title: showDetail ? 'Hide Distribution' : 'Show Distribution',
          accessibilityLabel: 'Timing distribution',
          accessibilityHint: showDetail ? 'Hides the timing distribution' : 'Shows the timing distribution',
          expanded: showDetail,
          onPress: () => setShowDetail((visible) => !visible),
        }, ...(showDetail ? signal.detailRows : [])]}
      />
    </View>
  );
}

export default function SleepScreen() {
  const scheme = useAppScheme();
  const palette = getAppPalette(scheme);
  const layout = useAdaptiveLayout();
  const reduceMotion = useReduceMotion();
  const sleeps = useStore((state) => state.sleeps);
  const doses = useStore((state) => state.doses);
  const prefs = useStore((state) => state.prefs);
  const onboarding = useStore((state) => state.onboarding);
  const healthSync = useStore((state) => state.healthSync);
  const demoMode = useStore((state) => state.demoMode);
  const addSleep = useStore((state) => state.addSleep);
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
  const sleepDataAnchorRef = useRef<View>(null);
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

  const now = useNow();
  const presentation = useMemo(
    () => getSleepPresentation(sleeps, prefs.targetSleep, range, now),
    [sleeps, prefs.targetSleep, range, now],
  );
  const recentNight = useMemo(
    () => recentNightSignal(sleeps, prefs.targetSleep, now),
    [sleeps, prefs.targetSleep, now],
  );
  const caffeineTiming = useMemo(
    () => caffeineTimingSignal(sleeps, doses, now),
    [doses, now, sleeps],
  );
  // Validation uses the live clock: the shared minute clock can lag a fresh draft.
  const validation = validateManualSleep(draft, Date.now());
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
          ? 'Health not connected'
          : onboarding.permissionStatus === 'granted'
            ? healthSync.importStatus === 'succeeded'
              ? healthSync.importedCount > 0 ? 'Health sleep imported' : 'No sleep found'
              : healthSync.importStatus === 'importing' ? 'Importing sleep' : 'Health access requested'
            : 'Manual mode';
  const healthDescription = refreshFailureMessage
    ? refreshFailureMessage
    : ['Health sleep imported', 'No sleep found', 'Importing sleep', 'Health access requested'].includes(healthState)
      ? healthSync.importStatus === 'succeeded' && healthSync.importedCount === 0
        ? 'Check sleep records and Aurora’s read access in Health, or add sleep manually.'
        : 'Refresh reads the last 30 days of sleep from Health.'
      : healthState === 'Health not connected'
        ? 'Health access wasn’t set up. You can still log sleep manually.'
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
        setHealthSync({ importedCount: 0, importStatus: 'idle', lastSyncedAt: now, lastMessage: 'Health isn’t available on this device. No sleep was imported.' });
        return;
      }
      if (!(await AppleHealth.requestAuthorization())) {
        setOnboarding({ source: 'manual', permissionStatus: 'denied' });
        setHealthSync({ importedCount: 0, importStatus: 'idle', lastSyncedAt: now, lastMessage: 'Health access wasn’t set up. No sleep was imported.' });
        return;
      }
      setOnboarding({ source: 'healthkit', permissionStatus: 'granted' });
      const result = await importHealthSleep({ days: 30, now });
      if (!result.ok) setRefreshError(result.error);
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unable to read sleep data.';
      setRefreshError(message);
      setHealthSync({ importStatus: 'failed', lastSyncedAt: now, lastMessage: `Health refresh failed. ${message}` });
    } finally {
      setLoading(false);
    }
  };

  const openAddSleep = () => {
    setDraft(createManualSleepDraft(Date.now()));
    setShowForm(true);
  };

  const saveManualSleep = () => {
    if (!validation.valid) return;
    haptics.success();
    addSleep({ id: createManualSleepId(now), start: draft.start, end: draft.end, type: 'sleep', ...(draft.note.trim() ? { note: draft.note.trim() } : {}) });
    setPickerField(undefined);
    setShowForm(false);
    setAnnouncement('Sleep session saved.');
    AccessibilityInfo.announceForAccessibility('Sleep session saved.');
  };

  const hasChartData = presentation.recordedNights > 0;
  const latestRecordedIndex = presentation.points.reduce(
    (latest, point, index) => (point.durationMs !== null ? index : latest),
    presentation.points.length - 1,
  );
  const chart = (
    <HealthChartCard
      title="Time Asleep"
      value={presentation.averageDurationMs !== null ? formatSleepDuration(presentation.averageDurationMs) : undefined}
      dateRange={hasChartData
        ? `Average of ${presentation.recordedNights} recorded ${presentation.recordedNights === 1 ? 'night' : 'nights'} · ${presentation.dateRange}`
        : presentation.dateRange}
      accessibilitySummary={presentation.accessibilitySummary}
      interactiveChildren
      emptyState={<HealthEmptyState message="No sleep recorded in this range." detail="Add a night or connect Health in Sleep Data." symbol="bed.double.fill" fallback="bed" />}
    >
      {hasChartData ? (
        <HealthBarChart
          testID="sleep-bars"
          height={layout.isWideLayout ? 140 : 104}
          points={presentation.points.map((point) => ({ key: point.date, value: point.durationMs === null ? null : point.durationMs / HOUR_MS }))}
          max={10}
          color={palette.sleepAccent}
          reference={{ value: prefs.targetSleep, label: `${prefs.targetSleep}h target` }}
          startLabel={new Date(presentation.points[0].date).toLocaleDateString(undefined, { month: 'short', day: 'numeric' })}
          endLabel="Today"
          inspection={{
            accessibilityLabel: presentation.accessibilitySummary,
            defaultIndex: latestRecordedIndex,
            describe: (index) => describeSleepChartDay(presentation.points[index]),
          }}
        />
      ) : undefined}
    </HealthChartCard>
  );
  const supporting = (
    <View style={{ gap: spacing.sm }}>
      <SignalCard
        model={recentNight}
        icon="bed"
        accent={palette.sleepAccent}
        onPress={recentNight.status === 'empty' ? openAddSleep : () => navigate('SleepHistory')}
      />
      <CaffeineTiming signal={caffeineTiming} accent={palette.sleepAccent} />
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
      trailing={<Button ref={addDataRef} title="Add Data" variant="plain" onPress={openAddSleep} />}
      scrollRef={scrollRef}
      contentRef={contentRef}
      scrollEnabled={!walkthrough.active}
      interactionEnabled={!walkthrough.active}
      bottomOverlay={walkthroughCoach}
      onScroll={walkthrough.onScroll}
      refreshControl={
        onboarding.permissionStatus === 'granted' && !demoMode && !walkthrough.active ? (
          <RefreshControl refreshing={loading} onRefresh={connectHealth} tintColor={palette.sleepAccent} />
        ) : undefined
      }
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
          <HealthRangeControl accessibilityLabel="Sleep range" value={range} onChange={setRange} options={[{ value: 'week', label: 'W', accessibilityLabel: 'Week' }, { value: 'month', label: 'M', accessibilityLabel: 'Month' }]} />
          <View testID={layout.isWideLayout ? 'sleep-wide-layout' : 'sleep-compact-layout'} style={{ flexDirection: layout.isWideLayout ? 'row' : 'column', gap: spacing.md }}>
            <View
              testID="sleep-primary-column"
              style={{ width: layout.isWideLayout ? layout.leftColumnWidth : '100%' }}
            >
              {chart}
            </View>
            <View
              testID={layout.isWideLayout ? 'sleep-supporting-column' : undefined}
              style={{ width: layout.isWideLayout ? layout.rightColumnWidth : '100%' }}
            >
              {supporting}
            </View>
          </View>
        </WalkthroughReveal>
        <WalkthroughReveal active={walkthrough.active} revealed={walkthrough.isRevealed('sleep-data')} reduceMotion={walkthrough.reduceMotion}>
          <View testID="sleep-data-anchor" ref={sleepDataAnchorRef} collapsable={false} onLayout={() => walkthrough.measureAnchor('sleep-data', sleepDataAnchorRef.current)} style={{ gap: spacing.sm }}>
            <HealthGroupedList rows={[{
              title: 'Sleep Data',
              subtitle: healthState,
              accessibilityLabel: `Sleep Data, ${healthState}`,
              accessibilityHint: showSources ? 'Hides Health, manual, and sample data controls' : 'Shows Health, manual, and sample data controls',
              expanded: showSources,
              onPress: () => setShowSources((visible) => !visible),
            }]} />
            {showSources ? <View testID="sleep-data-panel" style={{ gap: spacing.sm, padding: spacing.md, borderRadius: radii.card, backgroundColor: palette.card }}>
              <Text style={{ ...typeRamp.headline, color: palette.textPrimary }}>{healthState}</Text>
              <Text style={{ ...typeRamp.subheadline, color: palette.textSecondary }}>{healthDescription}</Text>
              <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Health access is read-only. Imported: {healthSync.importedCount} {healthSync.importedCount === 1 ? 'night' : 'nights'}</Text>
              {healthSync.lastSyncedAt ? <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>Last sync: {formatTime(healthSync.lastSyncedAt)}</Text> : null}
              {healthSync.lastMessage ? <Text style={{ ...typeRamp.footnote, color: palette.textSecondary }}>{healthSync.lastMessage}</Text> : null}
              <Button title={onboarding.permissionStatus === 'granted' ? 'Refresh Sleep' : 'Connect to Health'} variant="primary" onPress={connectHealth} disabled={loading || healthAvailable === false} loading={loading} />
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}><Button title="Add Sleep Manually" onPress={openAddSleep} /><Button title="Show All Data" accessibilityLabel={`Show All Data, ${sleeps.length} ${sleeps.length === 1 ? 'session' : 'sessions'}`} onPress={() => navigate('SleepHistory')} /></View>
              <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: spacing.sm }}><Button title={demoMode ? 'Refresh Sample Data' : 'Load Sample Data'} onPress={loadDemoData} /><Button title="Clear Samples" variant="plain" role="destructive" onPress={clearDemoData} disabled={!demoMode} /></View>
            </View> : null}
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
