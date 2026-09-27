import React, { useMemo, useRef } from 'react';
import type { LayoutChangeEvent } from 'react-native';
import { ScrollView, Text, View } from 'react-native';

import AlertnessRing from '~/components/AlertnessRing';
import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import CaffeineTodayGraph from '~/components/CaffeineTodayGraph';
import {
  Divider,
  Eyebrow,
  HealthAlertCard,
  HealthMetricCard,
  ListRow,
  SectionCard,
  SectionHeader,
  Surface,
} from '~/components/ui';
import {
  estimateAlertness,
  formatSleepHours,
} from '~/features/summary/presentation';
import {
  AppWalkthroughCoach,
  useAppWalkthrough,
  WalkthroughReveal,
} from '~/features/appWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import useLargeText from '~/hooks/useLargeText';
import useNow from '~/hooks/useNow';
import { mgActive as activeCaffeineMg } from '~/domain/algorithm/caffeine';
import useSleepGuidance from '~/hooks/useSleepGuidance';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';
import { createDoseId } from '~/features/caffeine/logging';
import { haptics } from '~/services/platform/haptics';
import { CAFFEINE_PRESETS } from '~/features/caffeine/presets';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { fontScaling, radii, spacing, typeRamp } from '~/theme/tokens';

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

function fmtDateTime(ts: number) {
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toLocaleString();
  }
}

function fmtDay(ts?: number) {
  if (!ts) return 'Today';
  try {
    return new Intl.DateTimeFormat(undefined, {
      month: 'short',
      day: 'numeric',
    }).format(new Date(ts));
  } catch {
    return new Date(ts).toDateString();
  }
}

function fmtDuration(ms?: number) {
  if (!ms || ms <= 0) return 'No Data';
  const hours = Math.floor(ms / 3_600_000);
  const minutes = Math.round((ms % 3_600_000) / 60_000);
  return `${hours}h ${minutes}m`;
}

export default function DashboardScreen() {
  const layout = useAdaptiveLayout();
  const largeText = useLargeText();
  const palette = getAppPalette(useAppScheme());
  const cutoff = useCaffeineCutoff();
  const sleepGuidance = useSleepGuidance();
  // Modeled values depend on the clock, not just stored data.
  const now = useNow();

  const doses = useStore((s) => s.doses);
  const sleeps = useStore((s) => s.sleeps);
  const prefs = useStore((s) => s.prefs);
  const mgActiveNow = useMemo(
    () => activeCaffeineMg(now, doses, prefs.halfLife),
    [now, doses, prefs.halfLife],
  );
  const sleepCount = sleeps.length;
  // Linear scan instead of a copy-and-sort inside the selector, which ran on
  // every store update.
  const latestSleep = useMemo(
    () =>
      sleeps.reduce<(typeof sleeps)[number] | undefined>(
        (latest, sleep) => (!latest || sleep.end > latest.end ? sleep : latest),
        undefined,
      ),
    [sleeps],
  );
  const latestVigilanceSession = useStore((s) => s.vigilanceSessions[0]);
  const addDose = useStore((s) => s.addDose);
  const demoMode = useStore((s) => s.demoMode);
  const loadDemoData = useStore((s) => s.loadDemoData);
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef<View>(null);
  const pinnedAnchorRef = useRef<View>(null);
  const loggingAnchorRef = useRef<View>(null);

  const todaySummary = useMemo(() => {
    const today = new Date(now);
    const key = (value: Date) =>
      `${value.getFullYear()}-${value.getMonth()}-${value.getDate()}`;
    const todayKey = key(today);
    const yesterday = new Date(today);
    yesterday.setDate(yesterday.getDate() - 1);
    const yesterdayKey = key(yesterday);

    let todayTotal = 0;
    let yesterdayTotal = 0;
    const recent = [...doses]
      .filter((dose) => {
        const doseKey = key(new Date(dose.timestamp));
        if (doseKey === todayKey) {
          todayTotal += dose.mg;
          return true;
        }
        if (doseKey === yesterdayKey) {
          yesterdayTotal += dose.mg;
        }
        return false;
      })
      .sort((a, b) => b.timestamp - a.timestamp)
      .slice(0, 4);

    const delta = todayTotal - yesterdayTotal;
    const deltaText = `${delta >= 0 ? '+' : ''}${delta} mg vs yesterday`;
    return { todayTotal, deltaText, recent };
  }, [doses, now]);

  const estimate = useMemo(
    () => estimateAlertness(now, doses, sleeps, prefs),
    [now, doses, sleeps, prefs],
  );

  const quickAdd = (mg: number, source: string) => {
    const timestamp = Date.now();
    haptics.tap();
    addDose({ id: createDoseId(timestamp), timestamp, mg, source });
  };

  const alertCard =
    demoMode || todaySummary.recent.length === 0 ? (
      <HealthAlertCard
        tone="info"
        label={demoMode ? 'Sample Data' : 'New Day'}
        dateLabel={fmtDay(now)}
        icon={demoMode ? 'sparkles-outline' : 'sunny-outline'}
        title={demoMode ? 'You’re viewing sample data.' : 'Nothing logged today.'}
        body={
          demoMode
            ? 'Explore Aurora with a sample week of sleep, caffeine, and reaction tests.'
            : 'Log your first coffee, or try Aurora with sample data.'
        }
        actionLabel={demoMode ? 'More Details' : 'Load Sample Data'}
        onAction={
          demoMode
            ? () => navigate('Insights')
            : loadDemoData
        }
      />
    ) : null;

  const walkthrough = useAppWalkthrough({
    route: 'Summary',
    isWideLayout: layout.isWideLayout,
    scrollRef,
    contentRef,
  });

  const measurePinned = (_event: LayoutChangeEvent) => {
    walkthrough.measureAnchor('summary-pinned', pinnedAnchorRef.current);
  };

  const measureLogging = (_event: LayoutChangeEvent) => {
    walkthrough.measureAnchor('summary-logging', loggingAnchorRef.current);
  };

  const revealedAlert = alertCard ? (
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('summary-alert')}
      reduceMotion={walkthrough.reduceMotion}
      staggerIndex={2}
    >
      {alertCard}
    </WalkthroughReveal>
  ) : null;

  const pinnedMetricCards = [
    {
      key: 'caffeine',
      element: (
        <HealthMetricCard
          icon="cafe"
          label="Caffeine"
          labelColor={palette.caffeineAccent}
          dateLabel="Today"
          value={`${Math.round(todaySummary.todayTotal)} mg`}
          detail={todaySummary.deltaText}
          onPress={() => navigate('Insights')}
        />
      ),
    },
    {
      key: 'active-caffeine',
      element: (
        <HealthMetricCard
          icon="pulse"
          label="Active Caffeine"
          labelColor={palette.activeCaffeineAccent}
          dateLabel="Now"
          value={`${Math.round(mgActiveNow)} mg`}
          detail={
            estimate.status === 'estimated'
              ? `Estimated alertness ${estimate.score}`
              : 'Alertness needs recent sleep'
          }
          onPress={() => navigate('Insights')}
        />
      ),
    },
    {
      key: 'sleep',
      element: (
        <HealthMetricCard
          icon="bed"
          label="Sleep"
          labelColor={palette.sleepAccent}
          dateLabel={fmtDay(latestSleep?.end)}
          value={
            latestSleep
              ? fmtDuration(latestSleep.end - latestSleep.start)
              : 'No Data'
          }
          detail={
            latestSleep
              ? `${sleepCount} session${sleepCount === 1 ? '' : 's'} available`
              : 'Add sleep or connect Health'
          }
          onPress={() => navigate('Sleep')}
        />
      ),
    },
    {
      key: 'vigilance',
      element: (
        <HealthMetricCard
          icon="speedometer"
          label="Reaction Test"
          labelColor={palette.vigilanceAccent}
          dateLabel={
            latestVigilanceSession
              ? fmtDay(latestVigilanceSession.completedAt)
              : 'Today'
          }
          value={
            latestVigilanceSession
              ? `${latestVigilanceSession.score}`
              : 'No Data'
          }
          detail={
            latestVigilanceSession
              ? `${latestVigilanceSession.rating} • ${latestVigilanceSession.medianReactionMs ?? '—'} ms median`
              : 'Run a 60-second test'
          }
          onPress={() => navigate('VigilanceTest')}
        />
      ),
    },
    {
      key: 'cutoff',
      element: (
        <HealthMetricCard
          icon="moon"
          label="Caffeine Cutoff"
          labelColor={palette.cutoffAccent}
          dateLabel="Today"
          value={fmtTime(cutoff?.nextCutoff)}
          detail={`Bed ${fmtTime(sleepGuidance?.bedtime)} • Wake ${fmtTime(sleepGuidance?.wake)}`}
          onPress={() => navigate('Sleep')}
        />
      ),
    },
  ];

  const pinnedCards = (
    <>
      <WalkthroughReveal
        active={walkthrough.active}
        revealed={walkthrough.isRevealed('summary-pinned')}
        reduceMotion={walkthrough.reduceMotion}
        staggerIndex={0}
      >
        <SectionHeader
          prominence="prominent"
          title="Pinned"
        />
      </WalkthroughReveal>
      <View style={{ gap: spacing.md }}>
        {pinnedMetricCards.map((card, index) => (
          <WalkthroughReveal
            key={card.key}
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('summary-pinned')}
            reduceMotion={walkthrough.reduceMotion}
            staggerIndex={index + 1}
          >
            {card.element}
          </WalkthroughReveal>
        ))}
      </View>
    </>
  );

  const revealedLogSection = (
    <>
      <WalkthroughReveal
        active={walkthrough.active}
        revealed={walkthrough.isRevealed('summary-logging')}
        reduceMotion={walkthrough.reduceMotion}
      >
        <SectionHeader title="Log" />
      </WalkthroughReveal>
      <WalkthroughReveal
        active={walkthrough.active}
        revealed={walkthrough.isRevealed('summary-logging')}
        reduceMotion={walkthrough.reduceMotion}
        staggerIndex={1}
      >
        <SectionCard>
          <View
            style={{
              flexDirection: 'row',
              flexWrap: 'wrap',
              gap: spacing.sm,
            }}
          >
            {CAFFEINE_PRESETS.map((preset, index) => (
              <WalkthroughReveal
                key={preset.id}
                active={walkthrough.active}
                revealed={walkthrough.isRevealed('summary-logging')}
                reduceMotion={walkthrough.reduceMotion}
                staggerIndex={index + 2}
              >
                <Button
                  title={`${preset.label} ${preset.mg}mg`}
                  variant="plain"
                  onPress={() => quickAdd(preset.mg, preset.label)}
                />
              </WalkthroughReveal>
            ))}
          </View>
          <WalkthroughReveal
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('summary-logging')}
            reduceMotion={walkthrough.reduceMotion}
            staggerIndex={6}
          >
            <Button
              title="Custom Entry"
              variant="plain"
              onPress={() => navigate('Log')}
            />
          </WalkthroughReveal>
        </SectionCard>
      </WalkthroughReveal>
    </>
  );

  const recentSection = (
    <>
      <SectionHeader
        title="Recent Activity"
        action={
          <Button
            title="See History"
            variant="plain"
            onPress={() => navigate('Insights')}
          />
        }
      />
      <SectionCard>
        {todaySummary.recent.length === 0 ? (
          <Text
            style={{
              ...typeRamp.subheadline,
              color: palette.textTertiary,
            }}
          >
            No doses logged today.
          </Text>
        ) : (
          todaySummary.recent.map((dose) => (
            <ListRow
              key={dose.id}
              title={`${dose.mg} mg${dose.source ? ` • ${dose.source}` : ''}`}
              subtitle={fmtDateTime(dose.timestamp)}
            />
          ))
        )}
      </SectionCard>
    </>
  );

  // Hero: Estimated Alertness from the existing model, paired with the
  // caffeine curve. Without recent sleep the ring shows no score. On iPhone
  // the ring and copy sit side by side so the curve starts on the first
  // screen; at large text sizes the copy moves below the ring and takes the
  // full width.
  const alertnessCopy =
    estimate.status === 'estimated'
      ? {
          title: `From ${formatSleepHours(estimate.sleepHours)} of sleep`,
          body: 'Plus active caffeine and time of day. Not a measurement.',
        }
      : {
          title: 'No recent sleep',
          body: 'Add sleep from the last 24 hours to see an estimate.',
        };

  const todayPanel = (
    <View style={{ gap: spacing.md }}>
      <SectionHeader
        prominence="prominent"
        title="Today"
        actionLabel="Details"
        onAction={() => navigate('Insights')}
      />
      <Surface
        radius={radii.hero}
        style={{
          padding: layout.isWideLayout ? spacing.lg : spacing.md,
          gap: layout.isWideLayout ? spacing.lg : spacing.md,
        }}
      >
        <View
          testID="summary-hero"
          style={{
            flexDirection: largeText ? 'column' : 'row',
            flexWrap: largeText ? 'nowrap' : 'wrap',
            alignItems: largeText ? 'stretch' : 'center',
            gap: layout.isWideLayout ? spacing.lg : spacing.md,
          }}
        >
          <AlertnessRing
            estimate={estimate}
            size={layout.isWideLayout ? 152 : 104}
          />
          <View
            style={
              largeText
                ? { gap: spacing.xxs }
                : { flex: 1, minWidth: 160, gap: spacing.xxs }
            }
          >
            <Eyebrow text="Estimated Alertness" />
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{
                ...(layout.isWideLayout ? typeRamp.title3 : typeRamp.headline),
                color: palette.textPrimary,
              }}
            >
              {alertnessCopy.title}
            </Text>
            <Text
              maxFontSizeMultiplier={fontScaling.body}
              style={{ ...typeRamp.footnote, color: palette.textSecondary }}
            >
              {alertnessCopy.body}
            </Text>
            {estimate.status === 'needs-sleep' ? (
              <Button
                title="Open Sleep"
                variant="tinted"
                onPress={() => navigate('Sleep')}
                style={{
                  alignSelf: 'flex-start',
                  marginTop: spacing.xs,
                  paddingVertical: spacing.xs,
                }}
              />
            ) : null}
          </View>
        </View>
        <Divider />
        <View style={{ gap: spacing.sm }}>
          <Eyebrow text="Caffeine Today" />
          <CaffeineTodayGraph height={layout.isWideLayout ? 240 : 160} />
        </View>
      </Surface>
    </View>
  );

  const revealedRecentSection = (
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('summary-recent')}
      reduceMotion={walkthrough.reduceMotion}
      staggerIndex={7}
      style={{ gap: spacing.md }}
    >
      {recentSection}
    </WalkthroughReveal>
  );

  const revealedTodayPanel = (
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('summary-today')}
      reduceMotion={walkthrough.reduceMotion}
      staggerIndex={1}
    >
      {todayPanel}
    </WalkthroughReveal>
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
      title="Summary"
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
          revealed={walkthrough.isRevealed('summary-header')}
          reduceMotion={walkthrough.reduceMotion}
          staggerIndex={0}
        >
          {header}
        </WalkthroughReveal>
      )}
    >
      {layout.isWideLayout ? (
        <View
          style={{
            flexDirection: 'row',
            alignItems: 'flex-start',
            gap: spacing.xl,
          }}
        >
          <View style={{ width: layout.leftColumnWidth, gap: spacing.md }}>
            {revealedTodayPanel}
            {revealedAlert}
          </View>
          <View style={{ width: layout.rightColumnWidth, gap: spacing.md }}>
            <View
              ref={pinnedAnchorRef}
              collapsable={false}
              onLayout={measurePinned}
              style={{ gap: spacing.md }}
            >
              {pinnedCards}
            </View>
            <View
              ref={loggingAnchorRef}
              collapsable={false}
              onLayout={measureLogging}
              style={{ gap: spacing.md }}
            >
              {revealedLogSection}
              {revealedRecentSection}
            </View>
          </View>
        </View>
      ) : (
        <>
          {revealedTodayPanel}
          {revealedAlert}
          <View
            ref={pinnedAnchorRef}
            collapsable={false}
            onLayout={measurePinned}
            style={{ gap: spacing.md }}
          >
            {pinnedCards}
          </View>
          <View
            ref={loggingAnchorRef}
            collapsable={false}
            onLayout={measureLogging}
            style={{ gap: spacing.md }}
          >
            {revealedLogSection}
            {revealedRecentSection}
          </View>
        </>
      )}
    </AppScreen>
  );
}
