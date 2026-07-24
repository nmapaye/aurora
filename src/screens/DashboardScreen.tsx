import React, { useMemo, useRef } from 'react';
import type { LayoutChangeEvent } from 'react-native';
import { ScrollView, Text, View } from 'react-native';

import AppScreen from '~/components/AppScreen';
import Button from '~/components/Button';
import CaffeineTodayGraph from '~/components/CaffeineTodayGraph';
import {
  HealthAlertCard,
  HealthMetricCard,
  ListRow,
  SectionCard,
  SectionHeader,
} from '~/components/ui';
import {
  isSummaryWalkthroughPending,
  SummaryWalkthroughCoach,
  useSummaryWalkthrough,
  WalkthroughReveal,
} from '~/features/summaryWalkthrough';
import useAdaptiveLayout from '~/hooks/useAdaptiveLayout';
import { useAlertnessSeries } from '~/hooks/useAlertnessSeries';
import useCaffeineCutoff from '~/hooks/useCaffeineCutoff';
import useSleepGuidance from '~/hooks/useSleepGuidance';
import { navigate } from '~/navigation';
import { useStore } from '~/state/store';
import useAppScheme from '~/hooks/useAppScheme';
import { getAppPalette } from '~/theme/colors';
import { radii, spacing, typeRamp } from '~/theme/tokens';

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
  const palette = getAppPalette(useAppScheme());
  const { nowScore, mgActiveNow: mgActive } =
    (useAlertnessSeries() as any) || {};
  const cutoff = useCaffeineCutoff();
  const sleepGuidance = useSleepGuidance();

  const doses = useStore((s) => s.doses);
  const sleepCount = useStore((s) => s.sleeps.length);
  const latestSleep = useStore(
    (s) => [...s.sleeps].sort((a, b) => b.end - a.end)[0],
  );
  const latestVigilanceSession = useStore((s) => s.vigilanceSessions[0]);
  const addDose = useStore((s) => s.addDose);
  const demoMode = useStore((s) => s.demoMode);
  const loadDemoData = useStore((s) => s.loadDemoData);
  const onboarding = useStore((state) => state.onboarding);
  const completeAppWalkthrough = useStore(
    (state) => state.completeAppWalkthrough,
  );
  const scrollRef = useRef<ScrollView>(null);
  const contentRef = useRef<View>(null);
  const pinnedAnchorRef = useRef<View>(null);
  const loggingAnchorRef = useRef<View>(null);
  const walkthroughEnabled =
    isSummaryWalkthroughPending(onboarding);

  const todaySummary = useMemo(() => {
    const now = new Date();
    const key = (value: Date) =>
      `${value.getFullYear()}-${value.getMonth()}-${value.getDate()}`;
    const todayKey = key(now);
    const yesterday = new Date(now);
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
  }, [doses]);

  const quickAdd = (mg: number, source: string) => {
    const id = `${Date.now().toString(36)}-${Math.random()
      .toString(36)
      .slice(2)}`;
    addDose({ id, timestamp: Date.now(), mg, source });
  };

  const alertCard =
    demoMode || todaySummary.recent.length === 0 ? (
      <HealthAlertCard
        tone={demoMode ? 'info' : 'warning'}
        label={demoMode ? 'Sample Data' : 'New Day'}
        dateLabel={fmtDay(Date.now())}
        icon={demoMode ? 'sparkles-outline' : 'alert-circle-outline'}
        title={demoMode ? 'Sample flow is ready.' : 'No data yet.'}
        body={
          demoMode
            ? 'Sleep, caffeine, and vigilance are seeded.'
            : 'Log caffeine or load sample data to fill Summary.'
        }
        actionLabel={demoMode ? 'More Details' : 'Load Sample Data'}
        onAction={
          demoMode
            ? () => navigate('Insights', { section: 'summary' })
            : loadDemoData
        }
      />
    ) : null;

  const walkthrough = useSummaryWalkthrough({
    enabled: walkthroughEnabled,
    hasAlert: alertCard !== null,
    isWideLayout: layout.isWideLayout,
    scrollRef,
    contentRef,
    onComplete: completeAppWalkthrough,
  });

  const measurePinned = (_event: LayoutChangeEvent) => {
    walkthrough.measureAnchor('pinned', pinnedAnchorRef.current);
  };

  const measureLogging = (_event: LayoutChangeEvent) => {
    walkthrough.measureAnchor('logging', loggingAnchorRef.current);
  };

  const revealedAlert = alertCard ? (
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('alert')}
      reduceMotion={walkthrough.reduceMotion}
      staggerIndex={1}
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
          onPress={() => navigate('Insights', { section: 'summary' })}
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
          value={`${Math.round(mgActive ?? 0)} mg`}
          detail={`Alertness ${Math.round(nowScore ?? 0)}`}
          onPress={() => navigate('Insights', { section: 'trends' })}
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
              : 'Connect Health or use demo data'
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
          label="Vigilance"
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
        revealed={walkthrough.isRevealed('pinned')}
        reduceMotion={walkthrough.reduceMotion}
        staggerIndex={0}
      >
        <SectionHeader
          prominence="prominent"
          title="Pinned"
          actionLabel="Edit"
        />
      </WalkthroughReveal>
      <View style={{ gap: spacing.md }}>
        {pinnedMetricCards.map((card, index) => (
          <WalkthroughReveal
            key={card.key}
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('pinned')}
            reduceMotion={walkthrough.reduceMotion}
            staggerIndex={index + 1}
          >
            {card.element}
          </WalkthroughReveal>
        ))}
      </View>
    </>
  );

  const quickAddOptions = [
    ['Espresso', 60],
    ['Drip', 95],
    ['Matcha', 70],
    ['Energy', 160],
  ] as const;

  const revealedLogSection = (
    <>
      <WalkthroughReveal
        active={walkthrough.active}
        revealed={walkthrough.isRevealed('logging')}
        reduceMotion={walkthrough.reduceMotion}
      >
        <SectionHeader title="Log" />
      </WalkthroughReveal>
      <WalkthroughReveal
        active={walkthrough.active}
        revealed={walkthrough.isRevealed('logging')}
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
            {quickAddOptions.map(([label, mg], index) => (
              <WalkthroughReveal
                key={label}
                active={walkthrough.active}
                revealed={walkthrough.isRevealed('logging')}
                reduceMotion={walkthrough.reduceMotion}
                staggerIndex={index + 2}
              >
                <Button
                  title={`${label} ${mg}mg`}
                  variant="plain"
                  onPress={() => quickAdd(mg, label)}
                />
              </WalkthroughReveal>
            ))}
          </View>
          <WalkthroughReveal
            active={walkthrough.active}
            revealed={walkthrough.isRevealed('logging')}
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
            onPress={() => navigate('Insights', { section: 'history' })}
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

  const todayPanel = (
    <SectionCard
      style={{ borderRadius: radii.hero, padding: spacing.lg, gap: spacing.md }}
    >
      <SectionHeader
        prominence="prominent"
        title="Today"
        actionLabel="Details"
        onAction={() => navigate('Insights', { section: 'summary' })}
      />
      <CaffeineTodayGraph
        height={340}
        showCaption={false}
        compact
        variant="panel"
      />
      <View style={{ gap: spacing.xxs }}>
        <ListRow
          title="Caffeine"
          subtitle={todaySummary.deltaText}
          value={`${Math.round(todaySummary.todayTotal)} mg`}
        />
        <ListRow
          title="Active now"
          subtitle={`Alertness ${Math.round(nowScore ?? 0)}`}
          value={`${Math.round(mgActive ?? 0)} mg`}
        />
        <ListRow
          title="Cutoff"
          subtitle={`Bed ${fmtTime(sleepGuidance?.bedtime)}`}
          value={fmtTime(cutoff?.nextCutoff)}
        />
        <ListRow
          title="Vigilance"
          subtitle={
            latestVigilanceSession
              ? `${latestVigilanceSession.rating} • ${latestVigilanceSession.medianReactionMs ?? '—'} ms median`
              : 'No session yet'
          }
          value={
            latestVigilanceSession ? `${latestVigilanceSession.score}` : '—'
          }
        />
      </View>
    </SectionCard>
  );

  const revealedRecentSection = (
    <WalkthroughReveal
      active={walkthrough.active}
      revealed={walkthrough.isRevealed('recent')}
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
      revealed={walkthrough.isRevealed('today')}
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
      <SummaryWalkthroughCoach
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
          revealed={walkthrough.isRevealed('header')}
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
          </View>
          <View style={{ width: layout.rightColumnWidth, gap: spacing.md }}>
            {revealedTodayPanel}
          </View>
        </View>
      ) : (
        <>
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
